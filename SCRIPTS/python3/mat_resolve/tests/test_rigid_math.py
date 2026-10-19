"""
Tests for mat_resolve.rigid_math
=================================
The most important test here is ``test_jacobian_finite_difference``, which
verifies the analytical Jacobians in ``compose_rigid_with_jacobians`` against
central-difference numerical estimates.  This catches any sign errors or
chain-rule mistakes in the ported Fortran math.
"""

# pylint: disable=invalid-name

import numpy as np
import pytest
from scipy.spatial.transform import Rotation

from mat_resolve.rigid_math import (
    ck6_to_matrix,
    compose_rigid_with_jacobians,
    decompose_rigid,
    matrix_to_ck6,
    quaternion_multiply_with_jacobians,
    quaternion_to_rotation,
    quaternion_to_rotation_with_jacobian,
    rotation_to_quaternion_vec,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def random_ck6(rng, max_angle_deg=30.0, max_trans_mm=20.0):
    """
    Generate a random CK6 parameter vector representing a small rigid transform.

    Keeps rotation angles well below 90 degrees so we stay in the regime
    where the quaternion vector parameterisation is well-behaved.
    """
    # Random unit-quaternion vector part with limited rotation magnitude
    angle_rad = rng.uniform(0, np.deg2rad(max_angle_deg))
    axis = rng.standard_normal(3)
    axis /= np.linalg.norm(axis)
    e_vec = np.sin(angle_rad / 2.0) * axis  # [e1, e2, e3]
    t = rng.uniform(-max_trans_mm, max_trans_mm, 3)
    return np.concatenate([e_vec, t])


def numerical_jacobian(func, x, eps=1e-5):
    """
    Compute a numerical Jacobian of ``func`` at ``x`` via central differences.

    Parameters
    ----------
    func : callable
        Maps ndarray of shape (n,) -> ndarray of shape (m,).
    x : ndarray, shape (n,)
        Point at which to evaluate the Jacobian.
    eps : float
        Step size for finite differences.

    Returns
    -------
    J_num : ndarray, shape (m, n)
        Numerical Jacobian.
    """
    x = np.asarray(x, dtype=float)
    f0 = func(x)
    m, n = len(f0), len(x)
    J_num = np.zeros((m, n))
    for k in range(n):
        xp, xm = x.copy(), x.copy()
        xp[k] += eps
        xm[k] -= eps
        J_num[:, k] = (func(xp) - func(xm)) / (2.0 * eps)
    return J_num


# ---------------------------------------------------------------------------
# quaternion_to_rotation
# ---------------------------------------------------------------------------


def test_quaternion_to_rotation_identity():
    """Zero rotation vector should give a 3x3 identity matrix."""
    R = quaternion_to_rotation(np.zeros(3))
    np.testing.assert_allclose(R, np.eye(3), atol=1e-12)


def test_quaternion_to_rotation_known():
    """90-degree rotation around z-axis: known closed-form result."""
    angle = np.pi / 2
    e_vec = np.array([0.0, 0.0, np.sin(angle / 2)])
    R = quaternion_to_rotation(e_vec)
    expected = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]], dtype=float)
    np.testing.assert_allclose(R, expected, atol=1e-12)


def test_quaternion_to_rotation_is_rotation_matrix():
    """Result must be a proper rotation matrix: orthogonal with det = +1."""
    rng = np.random.default_rng(42)
    for _ in range(20):
        e_vec = random_ck6(rng)[:3]
        R = quaternion_to_rotation(e_vec)
        np.testing.assert_allclose(R @ R.T, np.eye(3), atol=1e-12)
        np.testing.assert_allclose(np.linalg.det(R), 1.0, atol=1e-12)


# ---------------------------------------------------------------------------
# rotation_to_quaternion_vec  (roundtrip with quaternion_to_rotation)
# ---------------------------------------------------------------------------


def test_quaternion_roundtrip(seed=0):
    """R -> e_vec -> R should recover the original rotation matrix."""
    rng = np.random.default_rng(seed)
    for _ in range(30):
        R_orig = Rotation.random(random_state=rng).as_matrix()
        e_vec = rotation_to_quaternion_vec(R_orig)
        R_back = quaternion_to_rotation(e_vec)
        np.testing.assert_allclose(R_back, R_orig, atol=1e-10)


# ---------------------------------------------------------------------------
# quaternion_to_rotation_with_jacobian
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("seed", [0, 1, 2, 7, 99])
def test_rotation_jacobian_finite_difference(seed):
    """
    Analytical dR/de_k should match central-difference numerical estimate.

    This is the key correctness test for the e2rd port from CKsub.f.
    """
    rng = np.random.default_rng(seed)
    e_vec = random_ck6(rng, max_angle_deg=45.0)[:3]

    R, dR = quaternion_to_rotation_with_jacobian(e_vec)

    for k in range(3):

        def R_flat(ev, _k=k):
            return quaternion_to_rotation(ev).ravel()

        J_num = numerical_jacobian(R_flat, e_vec)
        # J_num[:, k] = d(R.ravel())/d(e_k)
        # dR[:, :, k] is the 3x3 derivative matrix
        np.testing.assert_allclose(
            dR[:, :, k].ravel(),
            J_num[:, k],
            atol=1e-5,
            err_msg=f"dR/de{k+1} mismatch at seed={seed}",
        )


# ---------------------------------------------------------------------------
# quaternion_multiply_with_jacobians
# ---------------------------------------------------------------------------


def test_quaternion_multiply_identity():
    """Multiplying any quaternion by the identity quaternion (0,0,0) gives itself."""
    rng = np.random.default_rng(10)
    e_vec = random_ck6(rng)[:3]
    zero = np.zeros(3)
    g_vec, _, _ = quaternion_multiply_with_jacobians(e_vec, zero)
    np.testing.assert_allclose(g_vec, e_vec, atol=1e-12)


def test_quaternion_multiply_inverse():
    """q * q^{-1} should equal the identity quaternion (zero vector part)."""
    rng = np.random.default_rng(20)
    e_vec = random_ck6(rng)[:3]
    inv_e = -e_vec  # negating vector part = quaternion inverse
    g_vec, _, _ = quaternion_multiply_with_jacobians(e_vec, inv_e)
    np.testing.assert_allclose(g_vec, np.zeros(3), atol=1e-12)


@pytest.mark.parametrize("seed", [0, 3, 17, 42, 88])
def test_quaternion_multiply_jacobian_finite_difference(seed):
    """
    Analytical Jacobians of quaternion multiplication should match
    central-difference estimates.  Tests both dg/de and dg/df.
    """
    rng = np.random.default_rng(seed)
    e_vec = random_ck6(rng)[:3]
    f_vec = random_ck6(rng)[:3]

    g_vec, dg_de, dg_df = quaternion_multiply_with_jacobians(e_vec, f_vec)

    # dg/de: rows = [g0,g1,g2,g3], cols = [e1,e2,e3]
    # We only return the vector part g_vec, but dg_de covers the full g.
    # Test only rows 1-3 (vector part) since that is what compose uses.
    def g_of_e(ev):
        gv, _, _ = quaternion_multiply_with_jacobians(ev, f_vec)
        return gv

    def g_of_f(fv):
        gv, _, _ = quaternion_multiply_with_jacobians(e_vec, fv)
        return gv

    J_de_num = numerical_jacobian(g_of_e, e_vec)  # shape (3, 3)
    J_df_num = numerical_jacobian(g_of_f, f_vec)

    np.testing.assert_allclose(
        dg_de[1:, :],
        J_de_num,
        atol=1e-5,
        err_msg=f"dg/de mismatch at seed={seed}",
    )
    np.testing.assert_allclose(
        dg_df[1:, :],
        J_df_num,
        atol=1e-5,
        err_msg=f"dg/df mismatch at seed={seed}",
    )


# ---------------------------------------------------------------------------
# ck6_to_matrix / matrix_to_ck6
# ---------------------------------------------------------------------------


def test_ck6_matrix_roundtrip():
    """CK6 -> 4x4 matrix -> CK6 should recover original parameters."""
    rng = np.random.default_rng(5)
    for _ in range(20):
        params = random_ck6(rng)
        T = ck6_to_matrix(params)
        params_back = matrix_to_ck6(T)
        np.testing.assert_allclose(params_back, params, atol=1e-10)


def test_ck6_to_matrix_structure():
    """Output 4x4 matrix must have the correct homogeneous structure."""
    params = np.array([0.1, 0.05, -0.08, 5.0, -3.0, 2.0])
    T = ck6_to_matrix(params)
    # Bottom row must be [0, 0, 0, 1]
    np.testing.assert_allclose(T[3, :], [0, 0, 0, 1], atol=1e-12)
    # Top-left 3x3 must be a rotation matrix
    R = T[:3, :3]
    np.testing.assert_allclose(R @ R.T, np.eye(3), atol=1e-12)
    np.testing.assert_allclose(np.linalg.det(R), 1.0, atol=1e-12)
    # Translation column
    np.testing.assert_allclose(T[:3, 3], [5.0, -3.0, 2.0], atol=1e-12)


def test_identity_ck6():
    """Zero CK6 vector should give the 4x4 identity matrix."""
    T = ck6_to_matrix(np.zeros(6))
    np.testing.assert_allclose(T, np.eye(4), atol=1e-12)


# ---------------------------------------------------------------------------
# compose_rigid_with_jacobians — the core of the optimizer
# ---------------------------------------------------------------------------


def test_compose_rigid_self_inverse():
    """
    Composing Tbar[moving] with Tbar[fixed] = Tbar[moving] (same transform)
    should give identity: predicted = Tbar[moving] * Tbar[moving]^{-1} = I,
    so ck6_predicted should be all zeros.
    """
    rng = np.random.default_rng(7)
    ck6 = random_ck6(rng)
    ck6_hat = np.zeros(6)
    ck6_predicted, residual, _, _ = compose_rigid_with_jacobians(ck6, ck6, ck6_hat)
    np.testing.assert_allclose(ck6_predicted, np.zeros(6), atol=1e-10)
    np.testing.assert_allclose(residual, np.zeros(6), atol=1e-10)


def test_compose_rigid_identity_fixed():
    """
    If Tbar[fixed] = identity (zero CK6), then predicted = Tbar[moving] *
    I^{-1} = Tbar[moving], so ck6_predicted should equal ck6_moving.
    """
    rng = np.random.default_rng(8)
    ck6_moving = random_ck6(rng)
    ck6_fixed = np.zeros(6)
    ck6_hat = np.zeros(6)
    ck6_predicted, _, _, _ = compose_rigid_with_jacobians(ck6_moving, ck6_fixed, ck6_hat)
    np.testing.assert_allclose(ck6_predicted, ck6_moving, atol=1e-10)


@pytest.mark.parametrize("seed", [0, 1, 2, 5, 13, 42])
def test_compose_jacobian_moving_finite_difference(seed):
    """
    Analytical J_moving = d(residual)/d(ck6_moving) should match central
    differences.

    This is the most critical correctness test in the entire test suite —
    it validates the full chain rule through e2rd and ckmuld (ported from
    the Fortran CKsub.f and getjxy.f).
    """
    rng = np.random.default_rng(seed)
    ck6_moving = random_ck6(rng)
    ck6_fixed = random_ck6(rng)
    ck6_hat = random_ck6(rng)

    _, _, J_moving, _ = compose_rigid_with_jacobians(ck6_moving, ck6_fixed, ck6_hat)

    def residual_of_moving(moving):
        _, err, _, _ = compose_rigid_with_jacobians(moving, ck6_fixed, ck6_hat)
        return err

    J_moving_num = numerical_jacobian(residual_of_moving, ck6_moving)
    np.testing.assert_allclose(
        J_moving,
        J_moving_num,
        atol=1e-4,
        err_msg=f"J_moving analytical vs numerical mismatch at seed={seed}",
    )


@pytest.mark.parametrize("seed", [0, 1, 2, 5, 13, 42])
def test_compose_jacobian_fixed_finite_difference(seed):
    """
    Analytical J_fixed = d(residual)/d(ck6_fixed) should match central
    differences.
    """
    rng = np.random.default_rng(seed)
    ck6_moving = random_ck6(rng)
    ck6_fixed = random_ck6(rng)
    ck6_hat = random_ck6(rng)

    _, _, _, J_fixed = compose_rigid_with_jacobians(ck6_moving, ck6_fixed, ck6_hat)

    def residual_of_fixed(fixed):
        _, err, _, _ = compose_rigid_with_jacobians(ck6_moving, fixed, ck6_hat)
        return err

    J_fixed_num = numerical_jacobian(residual_of_fixed, ck6_fixed)
    np.testing.assert_allclose(
        J_fixed,
        J_fixed_num,
        atol=1e-4,
        err_msg=f"J_fixed analytical vs numerical mismatch at seed={seed}",
    )


def test_decompose_rigid_known_transform():
    """A known translation+rotation matrix decomposes to the expected values."""
    R = Rotation.from_euler("ZYX", [30.0, -10.0, 5.0], degrees=True).as_matrix()
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = [1.5, -2.0, 3.25]

    tx, ty, tz, rx, ry, rz = decompose_rigid(T)

    np.testing.assert_allclose([tx, ty, tz], [1.5, -2.0, 3.25])
    np.testing.assert_allclose([rz, ry, rx], [30.0, -10.0, 5.0], atol=1e-8)


def test_decompose_rigid_identity_is_zero():
    tx, ty, tz, rx, ry, rz = decompose_rigid(np.eye(4))
    np.testing.assert_allclose([tx, ty, tz, rx, ry, rz], [0.0] * 6, atol=1e-10)
