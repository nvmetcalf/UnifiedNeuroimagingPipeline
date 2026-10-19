"""
resolve.py
==========
The core "resolve a set of pairwise FSL transforms" algorithm, as a plain
Python API independent of the command-line tool. ``cli.py`` is a thin
wrapper around ``resolve()`` that adds file discovery, argument parsing, and
writing results back out to disk

Algorithm summary
-----------------
1.  Parameterise each unknown transform as 6 numbers [e1,e2,e3,tx,ty,tz]
    (quaternion vector part + translation).  The chosen ``reference`` image
    is fixed at identity. Internally, Tbar[k] maps the resolved space into
    image k's own space (x_k = Tbar[k] @ x_resolved) — see the "Convention"
    section of ``rigid_math.compose_rigid_with_jacobians`` for the full
    derivation of why this is the direction, and why it's the opposite of FSL matrices
2.  For each (moving, fixed) image pair, the *predicted* transform satisfies
    x_moving = predicted @ x_fixed, computed as:

        predicted = Tbar[moving] @ Tbar[fixed]^{-1}

    The residual is predicted - T_hat, where T_hat is the *inverse* of the
    raw observed FSL matrix for the pair
    
    Rotation residuals are scaled by 2*radius (mm) so they are commensurate
    with the translation residuals.
3.  ``scipy.optimize.least_squares`` (Levenberg-Marquardt) minimises the sum
    of squared residuals using the analytical Jacobian.
4.  The optimised Tbar[k] are inverted back to FSL's own convention before
    being returned, so ``ResolveResult.resolved`` is directly usable the
    same way as any real ``flirt``-produced ``.mat`` file.

Ported from: t4_resolve.c, ft4_resolve.f (Avi Synder lab, Washington University)
"""
# pylint: disable=invalid-name
# Rationale: T, J, R are standard mathematical notation in this domain.

from dataclasses import dataclass, field
import numpy as np
from scipy.optimize import least_squares
from .rigid_math import compose_rigid_with_jacobians, ck6_to_matrix, matrix_to_ck6, rigid_inv

def _unpack_params(x, n):
    """
    Unpack the flat optimisation variable into a list of CK6 transform vectors.

    Parameters
    ----------
    x : ndarray, shape (6*(n-1),)
        Concatenated CK6 parameters for images 1 .. n-1.  Image 0 is the
        reference and is always identity (not included in x).
    n : int
        Total number of images (including the reference image 0).

    Returns
    -------
    ck6_list : list of ndarray, shape (6,)
        ``ck6_list[0]`` = identity (image 0, fixed reference).
        ``ck6_list[k]`` = x[6*(k-1) : 6*k] for k = 1 .. n-1.
    """
    zero = np.zeros(6)  # image 0 is always identity
    return [zero] + [x[6 * k : 6 * (k + 1)] for k in range(n - 1)]


def _build_residuals_and_jacobian(x, transforms, image_names, radius=50.0, verbose=False):
    """
    Compute the full residual vector and analytical Jacobian for all pairs.

    Called by ``scipy.optimize.least_squares`` on each iteration.

    Parameters
    ----------
    x : ndarray, shape (6*(n-1),)
        Current estimate of all free transform parameters.
    transforms : dict
        ``(moving, fixed)`` -> observed 4x4 FSL matrix.
    image_names : list of str
        All N image names; image_names[0] is the fixed reference.
    radius : float
        VOI RMS radius (mm).  Rotation residuals are multiplied by 2*radius
        so they have mm-equivalent units in the least-squares norm.
    verbose : bool
        If True, print per-pair residual norms each call.

    Returns
    -------
    residuals : ndarray, shape (6*n*(n-1),)
        Stacked residual vectors for every ordered pair.
    J : ndarray, shape (6*n*(n-1), 6*(n-1))
        Analytical Jacobian: J[r, c] = d(residuals[r]) / d(x[c]).
    """ 
    # pylint: disable=too-many-locals
    n = len(image_names)
    m = n * (n - 1)  # total number of ordered pairs
    ck6_list = _unpack_params(x, n)

    residuals = np.zeros(6 * m)
    # columns of J correspond to free parameters only
    J = np.zeros((6 * m, 6 * (n - 1)))

    pair_idx = 0
    for moving_idx in range(n):
        for fixed_idx in range(n):
            if fixed_idx == moving_idx:
                continue

            # transforms[(moving, fixed)] holds the RAW FSL matrix from file
            # "{moving}_to_{fixed}.mat". FSL's own convention is x_fixed =
            # M_fsl @ x_moving so we need to invert it to get x_moving = T_hat @ x_fixed
            M_fsl = transforms[(image_names[moving_idx], image_names[fixed_idx])]
            ck6_hat = matrix_to_ck6(rigid_inv(M_fsl))

            ck6_moving = ck6_list[moving_idx]  # Tbar[moving]: resolved coordinates -> moving image's coordinates
            ck6_fixed = ck6_list[fixed_idx]  # Tbar[fixed]:  resolved coordinates -> fixed image's coordinates

            _, err6, J_moving, J_fixed = compose_rigid_with_jacobians(
                ck6_moving, ck6_fixed, ck6_hat
            )

            # Scale rotation rows (first 3) by 2*radius to give mm-equivalent units
            err6 = err6.copy()
            err6[:3] *= 2.0 * radius
            J_moving = J_moving.copy()
            J_moving[:3, :] *= 2.0 * radius
            J_fixed = J_fixed.copy()
            J_fixed[:3, :] *= 2.0 * radius

            row = 6 * pair_idx
            residuals[row : row + 6] = err6

            # Image 0 is fixed (identity, not optimised) — skip its Jacobian block
            if moving_idx > 0:
                col = 6 * (moving_idx - 1)
                J[row : row + 6, col : col + 6] = J_moving
            if fixed_idx > 0:
                col = 6 * (fixed_idx - 1)
                J[row : row + 6, col : col + 6] += J_fixed

            if verbose:
                print(
                    f"  pair ({image_names[moving_idx]}->{image_names[fixed_idx]}): "
                    f"rot_err={np.linalg.norm(err6[:3]):.4f} mm-equiv  "
                    f"trans_err={np.linalg.norm(err6[3:]):.4f} mm"
                )

            pair_idx += 1

    return residuals, J


def _per_frame_rms(residuals, n):
    """
    Compute the total RMS residual attributable to each image.

    Every ordered (fixed, moving) pair contributes its 6 residual components
    (already scaled to mm-equivalent units by ``_build_residuals_and_jacobian``) 
    to both of the images involved.  Pooling across all 2*(n-1) pairs an image appears
    in gives a single per-frame RMS figure, on the same mm-equivalent scale as the
    overall "Final RMS residual" reported after optimisation.

    Parameters
    ----------
    residuals : ndarray, shape (6*n*(n-1),)
        Final stacked residual vector (e.g. ``opt_result.fun``), in the same
        pair order produced by ``_build_residuals_and_jacobian`` (outer loop
        over ``moving_idx``, inner loop over ``fixed_idx``, skipping
        fixed_idx == moving_idx).
    n : int
        Number of images.

    Returns
    -------
    rms : ndarray, shape (n,)
        RMS residual (mm-equivalent) for each image.
    """
    residuals = np.asarray(residuals).reshape(-1, 6)
    frame_sumsq = np.zeros(n)
    frame_count = np.zeros(n)

    pair_idx = 0
    for moving_idx in range(n):
        for fixed_idx in range(n):
            if fixed_idx == moving_idx:
                continue
            sumsq = np.sum(residuals[pair_idx] ** 2)
            frame_sumsq[fixed_idx] += sumsq
            frame_sumsq[moving_idx] += sumsq
            frame_count[fixed_idx] += 6
            frame_count[moving_idx] += 6
            pair_idx += 1

    return np.sqrt(frame_sumsq / frame_count)


def _residuals_fn(x, transforms, image_names, radius=50.0, verbose=False):
    """Wrapper returning only residuals (for least_squares ``fun`` argument)."""
    res, _ = _build_residuals_and_jacobian(x, transforms, image_names, radius=radius, verbose=verbose)
    return res


def _jacobian_fn(x, transforms, image_names, radius=50.0, verbose=False):
    """Wrapper returning only the Jacobian (for least_squares ``jac`` argument)."""
    _, jac = _build_residuals_and_jacobian(x, transforms, image_names, radius=radius, verbose=verbose)
    return jac


def _initialise_params(transforms, image_names):
    """
    Build the initial guess for the optimiser from the observed transforms.

    Image 0 is the reference (identity), standing in for the resolved space
    before any optimisation has happened.  For each other image k, the direct
    observed transform between image k and image 0 gives a starting estimate
    for Tbar[k].

    Parameters
    ----------
    transforms : dict
        ``(moving, fixed)`` -> observed 4x4 FSL matrix.
    image_names : list of str
        All N image names; ``image_names[0]`` is the reference.

    Returns
    -------
    x0 : ndarray, shape (6*(n-1),)
        Initial CK6 parameter vector.

    Notes
    -----
    ``transforms[(image_names[k], image_names[0])]`` is the RAW FSL matrix
    from file "{k}_to_0.mat" (moving=k, fixed=0), satisfying FSL's own
    convention ``x_0 = M_fsl @ x_k``. Tbar[k] must satisfy the opposite direction,
    so the seed is ``rigid_inv(M_fsl)``, not ``M_fsl`` directly.
    """
    n = len(image_names)
    x0 = np.zeros(6 * (n - 1))

    for k in range(1, n):
        M_fsl = transforms[(image_names[k], image_names[0])]
        x0[6 * (k - 1) : 6 * k] = matrix_to_ck6(rigid_inv(M_fsl))

    return x0


@dataclass
class ResolveResult:
    """
    Result of :func:`resolve`.

    Attributes
    ----------
    image_names : list of str
        Image names, reordered so ``image_names[0]`` is the reference image
        (identity transform) used to anchor the resolved space.
    resolved : dict
        Mapping image name -> 4x4 ndarray, rigid body transform in FSL convention
    initial_rms : float
        RMS residual (mm-equivalent) before optimisation
    final_rms : float
        RMS residual (mm-equivalent) at the converged solution.
    per_frame_rms : dict
        Mapping image name -> RMS residual (mm-equivalent) attributable to
        that image, pooled over every pair it appears in.
    radius : float
        The VOI radius (mm) used to scale rotation residuals, echoed back
        for convenience.
    opt_result : scipy.optimize.OptimizeResult
        The raw result from ``scipy.optimize.least_squares``, for callers
        who want convergence diagnostics beyond what's summarised above.
    """

    image_names: list
    resolved: dict
    initial_rms: float
    final_rms: float
    per_frame_rms: dict
    radius: float
    opt_result: object = field(repr=False)


def resolve(transforms, image_names, radius=50.0, reference=0, verbose=False):
    """
    Resolve a set of pairwise FSL rigid-body registration matrices into a
    single self-consistent set of transforms, one per image, mapping each
    image into a common resolved space.

    Parameters
    ----------
    transforms : dict
        Mapping ``(moving_name, fixed_name)`` -> 4x4 ndarray, rigid body transformation
        in FSL convention. Must contain an entry for every ordered pair of
        ``image_names``.
    image_names : list of str
        All N image names.
    radius : float, optional
        VOI RMS radius in mm (default 50.0).  Rotation residuals are scaled
        by ``2*radius`` so they are commensurate with translation residuals
        in the least-squares norm.
    reference : int, optional
        Index into ``image_names`` to use as the fixed reference (identity
        transform) that anchors the resolved space (default 0).  Negative
        indices are supported (e.g. -1 for the last image).
    verbose : bool, optional
        If True, print per-pair residual norms at each optimiser iteration.

    Returns
    -------
    ResolveResult

    Raises
    ------
    ValueError
        If fewer than 2 images are given.
    IndexError
        If ``reference`` is out of range for ``image_names``.
    """
    image_names = list(image_names)
    n = len(image_names)
    if n < 2:
        raise ValueError(f"Need at least 2 images to resolve, got {n}.")

    try:
        ref_name = image_names[reference]
    except IndexError as exc:
        raise IndexError(
            f"reference={reference} is out of range for {n} images "
            f"(valid range: {-n} to {n - 1})."
        ) from exc

    # Reorder so the reference is first; everything below treats
    # image_names[0] as the fixed reference (identity transform).
    image_names = [ref_name] + [name for name in image_names if name != ref_name]

    # Evaluate the same residual formula at the initial guess (before
    # optimising) as at the converged result, so initial_rms and final_rms
    # are directly comparable — same units, same pooling, no conversion
    # needed.
    x0 = _initialise_params(transforms, image_names)
    initial_residuals = _residuals_fn(
        x0, transforms, image_names, radius=radius, verbose=False
    )
    initial_rms = float(np.sqrt(np.mean(initial_residuals**2)))

    # Run optimization to compute the "average" resolved transforms
    opt_result = least_squares(
        _residuals_fn,
        x0,
        jac=_jacobian_fn,
        method="lm",
        ftol=1e-9,
        xtol=1e-9,
        gtol=1e-9,
        args=(transforms, image_names),
        kwargs={"radius": radius, "verbose": verbose},
    )

    # Extract results
    final_rms = float(np.sqrt(opt_result.cost * 2.0 / len(opt_result.fun)))
    ck6_list = _unpack_params(opt_result.x, n)
    per_frame_rms_arr = _per_frame_rms(opt_result.fun, n)

    # ck6_list[k] holds Tbar[k], which satisfies x_k = Tbar[k] @ x_resolved
    # Invert before returning so  `resolved` is directly usable in FSL
    resolved = {
        name: rigid_inv(ck6_to_matrix(ck6_list[k])) for k, name in enumerate(image_names)
    }
    per_frame_rms = {
        name: float(per_frame_rms_arr[k]) for k, name in enumerate(image_names)
    }

    return ResolveResult(
        image_names=image_names,
        resolved=resolved,
        initial_rms=initial_rms,
        final_rms=final_rms,
        per_frame_rms=per_frame_rms,
        radius=radius,
        opt_result=opt_result,
    )
