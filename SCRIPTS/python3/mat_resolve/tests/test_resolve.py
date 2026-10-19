"""
Tests for mat_resolve.resolve
==============================
Covers the public ``resolve()`` API directly (as opposed to test_cli.py,
which exercises the same underlying machinery through cli.py's lower-level
helpers).
"""

# pylint: disable=invalid-name

import numpy as np
from scipy.spatial.transform import Rotation

from mat_resolve.resolve import ResolveResult, resolve
from mat_resolve.rigid_math import rigid_inv


def _make_rigid_matrix(angle_deg, axis, translation):
    """Build a 4x4 rigid transform from a rotation and translation."""
    R = Rotation.from_rotvec(np.deg2rad(angle_deg) * np.asarray(axis)).as_matrix()
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = translation
    return T


def _make_synthetic_dataset(n_images, rng):
    """
    Build a noiseless synthetic dataset of FSL-convention pairwise matrices,
    plus the ground-truth "image k maps to reference" transforms.

    Returns
    -------
    image_names : list of str
    true_T : list of ndarray, shape (4, 4)
        true_T[k] maps image k to the reference (image 0 = identity), i.e.
        x_resolved = true_T[k] @ x_k.
    transforms : dict
        (moving, fixed) -> 4x4 ndarray, in FSL's own convention
        (x_fixed = M @ x_moving) — exactly what resolve() expects.
    """
    image_names = [f"img{k:02d}" for k in range(n_images)]

    true_T = [np.eye(4)]
    for _ in range(n_images - 1):
        angle = rng.uniform(20, 60)
        axis = rng.standard_normal(3)
        axis /= np.linalg.norm(axis)
        trans = rng.uniform(-10, 10, 3)
        true_T.append(_make_rigid_matrix(angle, axis, trans))

    # T_{j->i} (moving=j, fixed=i) = inv(true_T[i]) @ true_T[j], matching
    # FSL's convention x_fixed = M @ x_moving.
    transforms = {}
    for i in range(n_images):
        for j in range(n_images):
            if i == j:
                continue
            transforms[(image_names[j], image_names[i])] = (
                np.linalg.inv(true_T[i]) @ true_T[j]
            )

    return image_names, true_T, transforms


def test_resolve_returns_resolve_result():
    """resolve() should return a ResolveResult with the expected fields."""
    rng = np.random.default_rng(3)
    image_names, _, transforms = _make_synthetic_dataset(4, rng)

    result = resolve(transforms, image_names)

    assert isinstance(result, ResolveResult)
    assert set(result.resolved) == set(image_names)
    assert set(result.per_frame_rms) == set(image_names)
    assert result.radius == 50.0
    assert result.opt_result.success or result.opt_result.cost < 1e-10


def test_resolve_recovers_ground_truth_noiseless():
    """
    With perfectly consistent (noiseless) pairwise transforms, resolve()
    should recover the ground truth to high precision, and every returned
    matrix should be a valid FSL-convention matrix directly comparable to
    the ground-truth "image k to reference" transforms.
    """
    rng = np.random.default_rng(11)
    n = 4
    image_names, true_T, transforms = _make_synthetic_dataset(n, rng)

    result = resolve(transforms, image_names, radius=50.0)

    assert result.final_rms < 1e-6, f"RMS residual too large: {result.final_rms:.2e}"

    for k, name in enumerate(image_names):
        np.testing.assert_allclose(
            result.resolved[name],
            true_T[k],
            atol=1e-5,
            err_msg=f"Resolved matrix for {name} does not match ground truth",
        )


def test_resolve_reference_selects_identity_image():
    """The chosen reference image should come back with an identity matrix."""
    rng = np.random.default_rng(23)
    image_names, _, transforms = _make_synthetic_dataset(4, rng)

    result = resolve(transforms, image_names, reference=2)

    assert result.image_names[0] == image_names[2]
    np.testing.assert_allclose(result.resolved[image_names[2]], np.eye(4), atol=1e-10)


def test_resolve_rejects_too_few_images():
    """resolve() should raise ValueError (not sys.exit) for < 2 images."""
    try:
        resolve({}, ["only_one"])
    except ValueError:
        pass
    else:
        raise AssertionError("Expected ValueError for fewer than 2 images")


def test_resolve_rejects_out_of_range_reference():
    """resolve() should raise IndexError (not sys.exit) for a bad reference."""
    rng = np.random.default_rng(5)
    image_names, _, transforms = _make_synthetic_dataset(3, rng)

    try:
        resolve(transforms, image_names, reference=99)
    except IndexError:
        pass
    else:
        raise AssertionError("Expected IndexError for out-of-range reference")


def test_resolve_output_is_valid_fsl_matrix_roundtrip():
    """
    result.resolved[name] should be usable exactly like a raw FSL matrix:
    inverting it should satisfy x_name = inv(M) @ x_resolved, matching the
    internal Tbar[name] convention (x_name = Tbar[name] @ x_resolved).
    """
    rng = np.random.default_rng(7)
    image_names, true_T, transforms = _make_synthetic_dataset(4, rng)

    result = resolve(transforms, image_names)

    for k, name in enumerate(image_names):
        Tbar_k = rigid_inv(result.resolved[name])
        np.testing.assert_allclose(Tbar_k, rigid_inv(true_T[k]), atol=1e-5)
