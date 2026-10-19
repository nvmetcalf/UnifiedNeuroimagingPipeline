"""
symmetry.py
===========
Diagnostic functions that measure how self-consistent a set of pairwise
rigid-body transforms is *before* any averaging is applied.

Background
----------
If registration were perfect, every closed loop of transforms would return to
the identity.  For example, for three images A, B, C, walking A->B->C->A:

    T_{C->A} * T_{B->C} * T_{A->B}  should equal  I

(the first-applied transform goes on the right, matching the convention
x_fixed = T_{moving->fixed} @ x_moving of the raw ``transforms`` dict this
module receives -- i.e. un-inverted FSL matrices. The
RMS deviation from identity over all such loops tells you how much "slack"
exists in your registrations — essentially the measurement noise floor for
the subsequent averaging step.

Two loop lengths are checked by default, plus an optional third:
  * Pairs      : T_{ji} * T_{ij} = I   (N*(N-1) pairs)
  * Triples    : T_{ki} * T_{jk} * T_{ij} = I   (N*(N-1)*(N-2) triples)
  * Quadruples : T_{li} * T_{kl} * T_{jk} * T_{ij} = I   (N*(N-1)*(N-2)*(N-3)
    quadruples) -- O(N^4), off by default; pass ``quadruples=True`` to
    ``compute_symmetry_error`` to enable it.

Ported from: subroutine ``symerr`` in ft4_resolve.f
             (Avi Synder, Washington University)
"""
# pylint: disable=invalid-name
# Rationale: T, R, M are standard mathematical notation for transforms,
# rotation matrices, and general matrices.  See rigid_math.py for full note.

import itertools
import numpy as np
from scipy.spatial.transform import Rotation


def _rotation_error_deg(R):
    """
    Return the rotation angle (degrees) of a matrix that should be identity.

    Parameters
    ----------
    R : ndarray, shape (3, 3)
        A rotation matrix representing the deviation from identity.

    Returns
    -------
    float
        The rotation angle in degrees (always >= 0).
    """
    return abs(Rotation.from_matrix(R).magnitude() * 180.0 / np.pi)


def _translation_error_mm(t):
    """
    Return the Euclidean norm of a translation that should be zero.

    Parameters
    ----------
    t : ndarray, shape (3,)
        Translation vector (mm).

    Returns
    -------
    float
        L2 norm of the translation (mm).
    """
    return float(np.linalg.norm(t))


def _compose_chain(matrices):
    """
    Left-multiply a sequence of 4x4 homogeneous matrices.

    Parameters
    ----------
    matrices : list of ndarray, each shape (4, 4)
        Transforms to compose in order: result = M[0] @ M[1] @ ... @ M[-1].

    Returns
    -------
    ndarray, shape (4, 4)
        The composed transform.
    """
    result = np.eye(4)
    for M in matrices:
        result = result @ M
    return result


def _loop_error(T_loop):
    """
    Measure how far a composed loop of transforms deviates from identity.

    Parameters
    ----------
    T_loop : ndarray, shape (4, 4)
        A transform that should equal the identity if registration is perfect.

    Returns
    -------
    rot_err_deg : float
        Rotation deviation in degrees.
    trans_err_mm : float
        Translation deviation in mm.
    """
    rot_err_deg = _rotation_error_deg(T_loop[:3, :3])
    trans_err_mm = _translation_error_mm(T_loop[:3, 3])
    return rot_err_deg, trans_err_mm


def compute_symmetry_error(transforms, image_names, quadruples=False):
    """
    Report the RMS symmetry error of a set of pairwise FSL transforms over
    pairs and triples of images (and, if requested, quadruples).

    Prints a formatted report to stdout.  No return value — this is a
    diagnostic function only, used before optimization begins.

    Parameters
    ----------
    transforms : dict
        Mapping from (moving_name, fixed_name) -> ndarray shape (4, 4).
        Must contain an entry for every ordered pair of distinct image names.
    image_names : list of str
        All N image names.  Order does not affect the result.
    quadruples : bool, optional
        Also report the RMS error over all N*(N-1)*(N-2)*(N-3) ordered
        quadruples. This is O(N^4) and can be slow for large N; off by
        default.

    Notes
    -----
    Ported from subroutine ``symerr`` in ft4_resolve.f.

    The RMS is computed over all distinct ordered loops (not just unique ones),
    matching the Fortran convention.  The variance for a loop of length L is
    divided by L to account for each transform appearing once per loop.

    Rotation errors are reported in degrees; translation errors in mm.
    """  # pylint: disable=too-many-locals
    n = len(image_names)
    names = image_names

    # -- Pairs: walk i->j->i should return to identity ----------------------
    rot_sq, tra_sq = 0.0, 0.0
    n_pairs = 0
    for i, j in itertools.permutations(range(n), 2):
        T_ij = transforms[(names[i], names[j])]
        T_ji = transforms[(names[j], names[i])]
        T_loop = _compose_chain([T_ji, T_ij])
        r, t = _loop_error(T_loop)
        rot_sq += r**2
        tra_sq += t**2
        n_pairs += 1

    # divide by loop length (2) then by count — matches Fortran 2*n*(n-1) denom
    rot_rms_pairs = np.sqrt(rot_sq / (2.0 * n_pairs))
    tra_rms_pairs = np.sqrt(tra_sq / (2.0 * n_pairs))

    print(f"\nSymmetry error over {n_pairs} ordered pairs:")
    print(f"  Rotation  RMS : {rot_rms_pairs:.4f} deg")
    print(f"  Translation RMS: {tra_rms_pairs:.4f} mm")

    if n < 3:
        return

    # -- Triples: walk i->j->k->i should return to identity -----------------
    # T_ij satisfies x_j = T_ij @ x_i (FSL convention), so walking the loop
    # means applying T_ij first, then T_jk, then T_ki -- as a matrix product
    # that's T_ki @ T_jk @ T_ij (the first-applied transform goes on the
    # right), not T_ij @ T_jk @ T_ki.
    rot_sq, tra_sq = 0.0, 0.0
    n_triples = 0
    for i, j, k in itertools.permutations(range(n), 3):
        T_ij = transforms[(names[i], names[j])]
        T_jk = transforms[(names[j], names[k])]
        T_ki = transforms[(names[k], names[i])]
        T_loop = _compose_chain([T_ki, T_jk, T_ij])
        r, t = _loop_error(T_loop)
        rot_sq += r**2
        tra_sq += t**2
        n_triples += 1

    rot_rms_triples = np.sqrt(rot_sq / (3.0 * n_triples))
    tra_rms_triples = np.sqrt(tra_sq / (3.0 * n_triples))

    print(f"\nSymmetry error over {n_triples} ordered triples:")
    print(f"  Rotation  RMS : {rot_rms_triples:.4f} deg")
    print(f"  Translation RMS: {tra_rms_triples:.4f} mm")

    if n < 4 or not quadruples:
        return

    # -- Quadruples: walk i->j->k->l->i should return to identity ----------
    # Same right-to-left composition order as the triples case above.
    rot_sq, tra_sq = 0.0, 0.0
    n_quads = 0
    for i, j, k, l in itertools.permutations(range(n), 4):
        T_ij = transforms[(names[i], names[j])]
        T_jk = transforms[(names[j], names[k])]
        T_kl = transforms[(names[k], names[l])]
        T_li = transforms[(names[l], names[i])]
        T_loop = _compose_chain([T_li, T_kl, T_jk, T_ij])
        r, t = _loop_error(T_loop)
        rot_sq += r**2
        tra_sq += t**2
        n_quads += 1

    rot_rms_quads = np.sqrt(rot_sq / (4.0 * n_quads))
    tra_rms_quads = np.sqrt(tra_sq / (4.0 * n_quads))

    print(f"\nSymmetry error over {n_quads} ordered quadruples:")
    print(f"  Rotation  RMS : {rot_rms_quads:.4f} deg")
    print(f"  Translation RMS: {tra_rms_quads:.4f} mm")
