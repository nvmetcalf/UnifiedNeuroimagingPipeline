"""
rigid_math.py
=============
Core mathematics for composing 6-DOF rigid-body transforms and computing
analytical Jacobians needed by the Gauss-Newton optimizer.

Background
----------
A rigid-body transform is stored as a 6-vector called CK6 (Cayley-Klein 6):

    params = [e1, e2, e3, tx, ty, tz]

where (e1, e2, e3) are the *vector part* of a unit quaternion representing
the rotation, and (tx, ty, tz) is the translation.  The scalar part of the
quaternion is derived:

    e0 = sqrt(1 - e1^2 - e2^2 - e3^2)

This parameterization avoids singularities for small-to-moderate rotations
and gives clean closed-form Jacobians — both properties the optimizer needs.

Ported from: CKsub.f and getjxy.f (Avi Synder, Washington University)
"""

# pylint: disable=invalid-name
# Rationale: R, T, J, dR etc. are universally understood mathematical notation
# for rotation matrices, transforms, Jacobians, and their derivatives.
# Renaming them to snake_case (e.g. rotation_matrix) would obscure the math.

import numpy as np
from scipy.spatial.transform import Rotation


def quaternion_to_rotation(e_vec):
    """
    Build a 3x3 rotation matrix from the vector part of a unit quaternion using
    scipy's from_quat

    Parameters
    ----------
    e_vec : array_like, shape (3,)
        Vector part (e1, e2, e3) of the unit quaternion.  The scalar part
        e0 = sqrt(1 - e1^2 - e2^2 - e3^2) is computed internally.

    Returns
    -------
    R : ndarray, shape (3, 3)
        Rotation matrix corresponding to the quaternion.
    """
    e1, e2, e3 = e_vec
    e0 = np.sqrt(max(0.0, 1.0 - e1**2 - e2**2 - e3**2))
    # scipy scalar-last convention: [x, y, z, w] = [e1, e2, e3, e0]
    return Rotation.from_quat([e1, e2, e3, e0]).as_matrix()


def rotation_to_quaternion_vec(R):
    """
    Extract the vector part (e1, e2, e3) of the unit quaternion for a
    rotation matrix using scipy Rotation. 

    Parameters
    ----------
    R : array_like, shape (3, 3)
        Rotation matrix.

    Returns
    -------
    e_vec : ndarray, shape (3,)
        Vector part (e1, e2, e3) of the unit quaternion.  The scalar part
        e0 is always taken as positive (principal rotation, angle in [0, pi]).
    """
    q = Rotation.from_matrix(np.asarray(R, dtype=float)).as_quat()  # [x,y,z,w]
    # Ensure e0 (scalar part = w) is positive so we stay in the principal branch
    if q[3] < 0:
        q = -q
    return q[:3]  # return only (e1, e2, e3)


def quaternion_to_rotation_with_jacobian(e_vec):
    """
    Build a 3x3 rotation matrix and its partial derivatives with respect to
    the three quaternion vector components.

    Parameters
    ----------
    e_vec : array_like, shape (3,)
        Vector part (e1, e2, e3) of the unit quaternion.

    Returns
    -------
    R : ndarray, shape (3, 3)
        Rotation matrix.
    dR : ndarray, shape (3, 3, 3)
        dR[i, j, k] = partial derivative of R[i,j] with respect to e_{k+1}.
        That is, dR[:, :, 0] = dR/de1, dR[:, :, 1] = dR/de2,
        dR[:, :, 2] = dR/de3.

    Notes
    -----
    Ported from subroutine ``e2rd`` in CKsub.f.  The derivatives account for
    the constraint e0 = sqrt(1 - e1^2 - e2^2 - e3^2), i.e. de0/dek = -ek/e0.

    ``quaternion_to_rotation`` uses scipy's convention, which gives a matrix
    that is the *transpose* of the Fortran ``e2r`` result.  The Fortran
    ``e2rd`` formulas therefore compute derivatives of Rf = R.T.  We apply
    those formulas using Rf, then convert back:

        dR_scipy[i, j, k] = dR_fortran[j, i, k]   (i.e. transpose axes 0,1)
    """
    e1, e2, e3 = e_vec
    e0 = np.sqrt(max(1e-12, 1.0 - e1**2 - e2**2 - e3**2))

    # R in scipy convention; Rf is the equivalent Fortran rotation matrix
    R = quaternion_to_rotation(e_vec)
    Rf = R.T  # Fortran e2r gives R.T relative to scipy

    # Jacobian in the Fortran convention: dR_f[i,j,k] = d(Rf[i,j])/d(e_{k+1})
    dR_f = np.zeros((3, 3, 3))

    # -- derivatives with respect to e1 (k=0) --------------------------------
    dR_f[0, 0, 0] = 0.0
    dR_f[0, 1, 0] = -Rf[0, 2] / e0
    dR_f[0, 2, 0] = Rf[0, 1] / e0
    dR_f[1, 0, 0] = Rf[2, 0] / e0
    dR_f[1, 1, 0] = -4.0 * e1
    dR_f[1, 2, 0] = (Rf[1, 1] + Rf[2, 2]) / e0
    dR_f[2, 0, 0] = -Rf[1, 0] / e0
    dR_f[2, 1, 0] = -dR_f[1, 2, 0]
    dR_f[2, 2, 0] = dR_f[1, 1, 0]

    # -- derivatives with respect to e2 (k=1) --------------------------------
    dR_f[0, 0, 1] = -4.0 * e2
    dR_f[0, 1, 1] = -Rf[2, 1] / e0
    dR_f[0, 2, 1] = -(Rf[0, 0] + Rf[2, 2]) / e0
    dR_f[1, 0, 1] = Rf[1, 2] / e0
    dR_f[1, 1, 1] = 0.0
    dR_f[1, 2, 1] = dR_f[2, 0, 0]  # = -Rf[1,0]/e0
    dR_f[2, 0, 1] = -dR_f[0, 2, 1]
    dR_f[2, 1, 1] = dR_f[0, 2, 0]  # = Rf[0,1]/e0
    dR_f[2, 2, 1] = dR_f[0, 0, 1]

    # -- derivatives with respect to e3 (k=2) --------------------------------
    dR_f[0, 0, 2] = -4.0 * e3
    dR_f[0, 1, 2] = (Rf[0, 0] + Rf[1, 1]) / e0
    dR_f[0, 2, 2] = dR_f[1, 0, 1]  # = Rf[1,2]/e0
    dR_f[1, 0, 2] = -dR_f[0, 1, 2]
    dR_f[1, 1, 2] = dR_f[0, 0, 2]
    dR_f[1, 2, 2] = dR_f[0, 1, 0]  # = -Rf[0,2]/e0
    dR_f[2, 0, 2] = dR_f[0, 1, 1]  # = -Rf[2,1]/e0
    dR_f[2, 1, 2] = dR_f[1, 0, 0]  # = Rf[2,0]/e0
    dR_f[2, 2, 2] = 0.0

    # Convert Fortran Jacobian to scipy convention by swapping the two matrix axes
    dR = dR_f.transpose(1, 0, 2)

    return R, dR


def quaternion_multiply_with_jacobians(e_vec, f_vec):
    """
    Multiply two unit quaternions and return the product plus analytical
    Jacobians.

    Given quaternions e = (e0; e_vec) and f = (f0; f_vec), computes their
    Hamilton product g = e * f and the 4x3 Jacobians dg/de and dg/df.

    Parameters
    ----------
    e_vec : array_like, shape (3,)
        Vector part of the left quaternion e.
    f_vec : array_like, shape (3,)
        Vector part of the right quaternion f.

    Returns
    -------
    g_vec : ndarray, shape (3,)
        Vector part of the product quaternion g = e * f.
    dg_de : ndarray, shape (4, 3)
        Jacobian of the full product quaternion [g0, g1, g2, g3] with respect
        to [e1, e2, e3].
    dg_df : ndarray, shape (4, 3)
        Jacobian of the full product quaternion with respect to [f1, f2, f3].

    Notes
    -----
    Ported from subroutine ``ckmuld`` in CKsub.f, reformulated below using
    the standard quaternion left/right-multiplication matrices instead of
    CKsub.f's original Levi-Civita-style lookup table (verified to produce
    identical output).

    The Hamilton product g = e * f can be written as a matrix-vector product
    two equivalent ways, using the standard left- and right-multiplication
    matrices of a quaternion — called ``L_e`` and ``R_f``:

        g_full = L_e @ f_full = R_f @ e_full

        L_e = [ e0  -e1  -e2  -e3 ]      R_f = [ f0  -f1  -f2  -f3 ]
              [ e1   e0  -e3   e2 ]            [ f1   f0   f3  -f2 ]
              [ e2   e3   e0  -e1 ]            [ f2  -f3   f0   f1 ]
              [ e3  -e2   e1   e0 ]            [ f3   f2  -f1   f0 ]

    Since g_full = L_e @ f_full is *linear* in e with f_full held fixed, the
    product rule gives the Jacobian directly without differentiating L_e
    itself — only e's own components need differentiating:

        dg_full/de_k = R_f @ (de_full/de_k)
        dg_full/df_k = L_e @ (df_full/df_k)

    where de_full/de_k = (-e_k/e0, delta_1k, delta_2k, delta_3k)
    """
    # pylint: disable=too-many-locals
    
    e1, e2, e3 = float(e_vec[0]), float(e_vec[1]), float(e_vec[2])
    f1, f2, f3 = float(f_vec[0]), float(f_vec[1]), float(f_vec[2])

    e0 = np.sqrt(max(1e-12, 1.0 - e1**2 - e2**2 - e3**2))
    f0 = np.sqrt(max(1e-12, 1.0 - f1**2 - f2**2 - f3**2))

    e_full = np.array([e0, e1, e2, e3])
    f_full = np.array([f0, f1, f2, f3])

    # Left-multiplication matrix of e=(e0,e1,e2,e3) and right-multiplication
    # matrix of f=(f0,f1,f2,f3): g_full = L_e @ f_full = R_f @ e_full.
    L_e = np.array(
        [
            [e0, -e1, -e2, -e3],
            [e1, e0, -e3, e2],
            [e2, e3, e0, -e1],
            [e3, -e2, e1, e0],
        ]
    )
    R_f = np.array(
        [
            [f0, -f1, -f2, -f3],
            [f1, f0, f3, -f2],
            [f2, -f3, f0, f1],
            [f3, f2, -f1, f0],
        ]
    )
    g_full = L_e @ f_full
    g_vec = g_full[1:]  # scalar part g_full[0] not needed for Jacobians

    # Form the derivatives using the chain rule (de0/dek, de1/dek, de2/dek, de3/dek).
    dg_de = np.zeros((4, 3))
    dg_df = np.zeros((4, 3))
    for k in range(3):
        de_dek = np.zeros(4)
        de_dek[0] = -e_full[k + 1] / e0
        de_dek[k + 1] = 1.0
        dg_de[:, k] = R_f @ de_dek

        df_dfk = np.zeros(4)
        df_dfk[0] = -f_full[k + 1] / f0
        df_dfk[k + 1] = 1.0
        dg_df[:, k] = L_e @ df_dfk

    return g_vec, dg_de, dg_df


def ck6_to_matrix(params):
    """
    Convert a CK6 6-vector to a 4x4 homogeneous rigid-body transform matrix.

    Parameters
    ----------
    params : array_like, shape (6,)
        CK6 parameters [e1, e2, e3, tx, ty, tz].

    Returns
    -------
    T : ndarray, shape (4, 4)
        Homogeneous matrix  T = | R  t |
                                | 0  1 |
    """
    params = np.asarray(params, dtype=float)
    T = np.eye(4)
    T[:3, :3] = quaternion_to_rotation(params[:3])
    T[:3, 3] = params[3:]
    return T


def matrix_to_ck6(T):
    """
    Convert a 4x4 homogeneous rigid-body transform matrix to CK6 parameters using
    scipy Rotation

    Parameters
    ----------
    T : array_like, shape (4, 4)
        Homogeneous matrix with a rotation block and translation column.

    Returns
    -------
    params : ndarray, shape (6,)
        CK6 parameters [e1, e2, e3, tx, ty, tz].
    """
    T = np.asarray(T, dtype=float)
    e_vec = rotation_to_quaternion_vec(T[:3, :3])
    t = T[:3, 3]
    return np.concatenate([e_vec, t])


def rigid_inv(T):
    """
    Invert a 4x4 rigid-body homogeneous transform matrix analytically.

    Parameters
    ----------
    T : array_like, shape (4, 4)
        Homogeneous matrix  T = | R  t |
                                | 0  1 |

    Returns
    -------
    T_inv : ndarray, shape (4, 4)
        The inverse transform: T_inv = | R.T  -R.T @ t |
                                       | 0     1        |

    Notes
    -----
    Exists because rigid-body inversion should never go through a general
    ``np.linalg.inv`` becaue it is numerically wasteful and can amplify floating-point
    error
    """
    T = np.asarray(T, dtype=float)
    R, t = T[:3, :3], T[:3, 3]
    T_inv = np.eye(4)
    T_inv[:3, :3] = R.T
    T_inv[:3, 3] = -R.T @ t
    return T_inv


def decompose_rigid(T):
    """
    Decompose a 4x4 rigid-body homogeneous transform matrix into a
    translation (mm) and ZYX Euler angles (degrees).

    Parameters
    ----------
    T : array_like, shape (4, 4)
        Homogeneous rigid-body transform matrix.

    Returns
    -------
    tx, ty, tz : float
        Translation components, mm.
    rx, ry, rz : float
        Intrinsic ZYX Euler angles, degrees -- matches FSL's convention for
        reporting rotation from a rigid-body matrix.
    """
    T = np.asarray(T, dtype=float)
    tx, ty, tz = T[:3, 3]
    rx, ry, rz = Rotation.from_matrix(T[:3, :3]).as_euler("ZYX", degrees=True)[::-1]
    return tx, ty, tz, rx, ry, rz


def compose_rigid_with_jacobians(ck6_moving, ck6_fixed, ck6_hat):
    """
    Compose two rigid transforms as predicted = Tbar[moving] * Tbar[fixed]^{-1}
    and compute the residual error relative to an observed transform, plus
    analytical Jacobians.

    Tbar[k] is the transform from resolved coordinates to image k's
    coordinates: x_k = Tbar[k] @ x_resolved.

    This is the key function called for every (moving, fixed) image pair
    during optimization. The composed ``predicted`` satisfies:

        x_moving = predicted @ x_fixed

    i.e. given a fixed-image coordinate, ``predicted`` gives you the
    corresponding moving-image coordinate. See "Convention" below for the
    derivation, and for why that's the *opposite* direction from a raw FSL
    matrix.

    Parameters
    ----------
    ck6_moving : array_like, shape (6,)
        CK6 parameters of Tbar for the *moving* image.
    ck6_fixed : array_like, shape (6,)
        CK6 parameters of Tbar for the *fixed* image. A zero vector means
        Tbar = identity (image 0, the reference frame).
    ck6_hat : array_like, shape (6,)
        CK6 parameters of the observed transform for this pair, satisfying
        x_moving = T_hat @ x_fixed

    Returns
    -------
    ck6_predicted : ndarray, shape (6,)
        Predicted transform Tbar[moving] * Tbar[fixed]^{-1} in CK6 form.
    residual : ndarray, shape (6,)
        Error vector predicted - T_hat.  First 3 elements are rotation
        residuals (in the tangent-space quaternion metric); last 3 are
        translation residuals (mm).
    J_moving : ndarray, shape (6, 6)
        Jacobian of the residual with respect to the 6 CK6 parameters of
        Tbar[moving].  J_moving[k, j] = d(residual[k]) / d(ck6_moving[j]).
    J_fixed : ndarray, shape (6, 6)
        Jacobian of the residual with respect to the 6 CK6 parameters of
        Tbar[fixed].

    Conventions
    -----------
    
        Transforms
        ----------
        ``ck6_hat`` is computed using FSL's flirt using the moving image as the input
        and the fixed image as the reference. FSL transformation matrices follow 
        the convention x_fixed = T_fsl @ x_moving. However, because this code expects 
        x_moving = T_hat @ x_fixed, we need to invert the FSL transformation: 
        T_hat = inv(T_fsl)
        
        See ``resolve.py``'s ``_build_residuals_and_jacobian`` and
        ``_initialise_params``, and ``transforms_io.py``'s ``write_output``, for the
        three places that conversion has to happen (reading an observed
        matrix, seeding the initial guess from one, and writing the final
        result back out as one).
        
        Rotation residual
        -----------------
        If q_predicted = quaternion of ``predicted`` than:

            rotation_residual[k] = sum_m  E4hat_vec[k, m] * q_predicted[m]   for k=1,2,3

        where E4hat_vec encodes (the vector-part rows of) multiplication by
        q_hat^{-1} on the left. This linearises the quaternion
        composition error around q_hat, making the residual proportional to the
        rotation angle error for small errors — suitable for a least-squares norm.
    """ 
    # pylint: disable=too-many-locals
    
    ck6_moving = np.asarray(ck6_moving, dtype=float)
    ck6_fixed = np.asarray(ck6_fixed, dtype=float)
    ck6_hat = np.asarray(ck6_hat, dtype=float)

    # Unpack quaternion vector parts
    e_moving = ck6_moving[:3]  # quaternion of Tbar[moving]
    e_fixed_inv = -ck6_fixed[:3]  # quaternion of Tbar[fixed]^{-1} (negate vector part)
    e_hat = ck6_hat[:3]
    e0h = np.sqrt(max(1e-12, 1.0 - np.dot(e_hat, e_hat)))
    e1h, e2h, e3h = e_hat

    # Rows 1-3 of the 4x4 left-multiplication-by-q_hat^{-1} matrix — used to
    # linearise the rotation residual around q_hat. Row 0 (the scalar part)
    # is never needed
    E4hat_vec = np.array(
        [
            [-e1h, e0h, -e3h, e2h],
            [-e2h, e3h, e0h, -e1h],
            [-e3h, -e2h, e1h, e0h],
        ]
    )

    # Compose rotations: q_predicted = q_moving * q_fixed^{-1}
    q_predicted_vec, dqpred_dmoving, dqpred_dfixed_inv = quaternion_multiply_with_jacobians(
        e_moving, e_fixed_inv
    )

    # Rotation residual: E4hat_vec @ [q0_predicted; q_predicted_vec]
    q0_predicted = np.sqrt(max(1e-12, 1.0 - np.dot(q_predicted_vec, q_predicted_vec)))
    q_predicted_full = np.concatenate([[q0_predicted], q_predicted_vec])
    rot_residual = E4hat_vec @ q_predicted_full  # shape (3,)

    # Build rotation matrices and their Jacobian 
    R_moving, dR_moving = quaternion_to_rotation_with_jacobian(e_moving)
    R_fixed_inv, dR_fixed_inv = quaternion_to_rotation_with_jacobian(e_fixed_inv)
    R_predicted = R_moving @ R_fixed_inv  # composed rotation

    # dR_predicted / d(e_moving_k) = (dR_moving/de_moving_k) @ R_fixed_inv
    dR_pred_dmoving = np.einsum("ijk,jl->ilk", dR_moving, R_fixed_inv)  # shape (3,3,3)
    # dR_predicted / d(e_fixed_inv_k) = R_moving @ (dR_fixed_inv/de_fixed_inv_k)
    dR_pred_dfixed_inv = np.einsum("ij,jlk->ilk", R_moving, dR_fixed_inv)  # shape (3,3,3)

    # Translation of predicted
    t_moving = ck6_moving[3:]
    t_fixed = ck6_fixed[3:]
    t_predicted = t_moving - R_predicted @ t_fixed

    # Assemble ck6_predicted and residual
    ck6_predicted = np.concatenate([q_predicted_vec, t_predicted])
    trans_residual = t_predicted - ck6_hat[3:]
    residual = np.concatenate([rot_residual, trans_residual])

    # Jacobian of residual w.r.t. ck6_moving -------------------------------
    # J_moving is a 6x6 block matrix. Rows split by residual type, columns
    # split by parameter type (e_moving = moving's rotation params,
    # t_moving = moving's translation params):
    #
    #            e_moving (3 cols)                t_moving (3 cols)
    #   rot   [ d(rot_residual)/d(e_moving)    |  0 ]
    #   trans [ d(trans_residual)/d(e_moving)  |  I ]
    #
    # Top-right is zero because the rotation residual doesn't depend on any
    # translation parameter at all; bottom-right is d(t_predicted)/d(t_moving), which is
    # identify because t_moving appears directly and linearly in t_predicted
    #
    # Below, the bottom row is computed as d(t_predicted)/d(...) because
    # trans_residual = t_predicted - ck6_hat[3:], and ck6_hat (the observed
    # data for this pair) is a constant with respect to every parameter.
    J_moving = np.zeros((6, 6))
    J_moving[3:, 3:] = np.eye(3)

    # Top-left: chain rule through q_predicted, same E4hat_vec linearisation
    # used for rot_residual itself.
    J_moving[:3, :3] = E4hat_vec @ dqpred_dmoving  # shape (3, 3)

    # Bottom-left: t_predicted = t_moving - R_predicted @ t_fixed, and only
    # the R_predicted factor depends on e_moving
    for k in range(3):
        J_moving[3:, k] = -dR_pred_dmoving[:, :, k] @ t_fixed
    
    # -- Jacobian of residual w.r.t. ck6_fixed --------------------------------
    # Same 6x6 block layout as J_moving above but columns are now e_fixed/t_fixed 
    # (e_fixed's own rotation/translation params — note e_fixed_inv = -e_fixed, so
    # d(e_fixed_inv)/d(e_fixed) = -I throughout, which is where the extra
    # sign flips below come from):
    #
    #            e_fixed (3 cols)                 t_fixed (3 cols)
    #   rot   [ d(rot_residual)/d(e_fixed)     |  0            ]
    #   trans [ d(trans_residual)/d(e_fixed)   |  -R_predicted ]
    J_fixed = np.zeros((6, 6))

    # Top-left: chain rule through e_fixed_inv, with the extra -1 from
    # d(e_fixed_inv)/d(e_fixed) = -I
    J_fixed[:3, :3] = -(E4hat_vec @ dqpred_dfixed_inv)  # shape (3, 3)

    # Bottom-left:
    # t_predicted = t_moving - R_predicted @ t_fixed
    # d(t_predicted)/d(e_fixed_k) = d(t_moving) / d(e_fixed_k) - d(R_predicted) / d(e_fixed_k) @ t_fixed
    # d(R_predicted) / d(e_fixed_k) = -d(R_predicted) / d(e_fixed_inv_k) because
    # d(e_fixed_inv_k) / d(e_fixed_k) = -1.
    # d(t_moving) / d(e_fixed_k) = 0
    # so d(t_predicted)/d(e_fixed_k) = d(R_predicted) / d(e_fixed_inv_k) @ t_fixed
    for k in range(3):
        J_fixed[3:, k] = dR_pred_dfixed_inv[:, :, k] @ t_fixed

    # Bottom-right: t_fixed appears in t_predicted only through
    # -R_predicted @ t_fixed, so d(t_predicted)/d(t_fixed) = -R_predicted
    J_fixed[3:, 3:] = -R_predicted

    return ck6_predicted, residual, J_moving, J_fixed
