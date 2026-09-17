#!/usr/bin/env python3
"""
fsl_mat_to_par.py

Convert a list of FSL FLIRT/MCFLIRT 4x4 affine matrices into motion parameter files.

Outputs
-------
1. A standard `.par` file containing frame-to-frame DIFFERENCES
   in the convention:
       rx ry rz tx ty tz
   where rotations are radians by default, or degrees with --degrees.

2. A mean-relative `.par` file containing the UNDifferentiated
   trajectory of each frame relative to the run mean rigid transform,
   computed via rigid-transform averaging on SE-3.

Notes
-----
- Input matrices are assumed to be rigid or near-rigid 4x4 transforms.
- Any small non-rigid component in the 3x3 block is projected to the nearest
  proper rotation matrix via SVD.
- The run mean transform is computed by:
    - averaging rotations via quaternion Markley averaging
    - averaging translations in Euclidean space
- Rotation extraction for output uses XYZ Euler angles.
- Output convention is:
      rx ry rz tx ty tz
"""

import argparse
from pathlib import Path
import numpy as np


def load_fsl_mat(path):
    """Load a 4x4 matrix from a text file."""
    mat = np.loadtxt(path)
    if mat.shape != (4, 4):
        raise ValueError(f"{path} does not contain a 4x4 matrix, got shape {mat.shape}")
    return mat


def project_to_rotation(R):
    """
    Project a 3x3 matrix to the nearest proper rotation matrix using SVD.
    """
    U, _, Vt = np.linalg.svd(R)
    Rproj = U @ Vt
    if np.linalg.det(Rproj) < 0:
        U[:, -1] *= -1
        Rproj = U @ Vt
    return Rproj


def rotmat_to_quat(R):
    """
    Convert a proper rotation matrix to quaternion [w, x, y, z].
    """
    R = np.asarray(R, dtype=float)
    tr = np.trace(R)

    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2.0
        w = 0.25 * s
        x = (R[2, 1] - R[1, 2]) / s
        y = (R[0, 2] - R[2, 0]) / s
        z = (R[1, 0] - R[0, 1]) / s
    else:
        if R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
            s = np.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2.0
            w = (R[2, 1] - R[1, 2]) / s
            x = 0.25 * s
            y = (R[0, 1] + R[1, 0]) / s
            z = (R[0, 2] + R[2, 0]) / s
        elif R[1, 1] > R[2, 2]:
            s = np.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2.0
            w = (R[0, 2] - R[2, 0]) / s
            x = (R[0, 1] + R[1, 0]) / s
            y = 0.25 * s
            z = (R[1, 2] + R[2, 1]) / s
        else:
            s = np.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2.0
            w = (R[1, 0] - R[0, 1]) / s
            x = (R[0, 2] + R[2, 0]) / s
            y = (R[1, 2] + R[2, 1]) / s
            z = 0.25 * s

    q = np.array([w, x, y, z], dtype=float)
    q /= np.linalg.norm(q)
    return q


def quat_to_rotmat(q):
    """
    Convert quaternion [w, x, y, z] to a rotation matrix.
    """
    q = np.asarray(q, dtype=float)
    q /= np.linalg.norm(q)
    w, x, y, z = q

    return np.array([
        [1 - 2*(y*y + z*z),     2*(x*y - z*w),     2*(x*z + y*w)],
        [    2*(x*y + z*w), 1 - 2*(x*x + z*z),     2*(y*z - x*w)],
        [    2*(x*z - y*w),     2*(y*z + x*w), 1 - 2*(x*x + y*y)],
    ], dtype=float)


def average_quaternions_markley(quats):
    """
    Average unit quaternions using the Markley method.

    Parameters
    ----------
    quats : array, shape [N, 4]
        Quaternions in [w, x, y, z] format.

    Returns
    -------
    q_mean : array, shape [4]
        Mean unit quaternion.
    """
    quats = np.asarray(quats, dtype=float)
    A = np.zeros((4, 4), dtype=float)

    for q in quats:
        q = q / np.linalg.norm(q)
        # Hemisphere consistency
        if q[0] < 0:
            q = -q
        A += np.outer(q, q)

    eigvals, eigvecs = np.linalg.eigh(A)
    q_mean = eigvecs[:, np.argmax(eigvals)]
    if q_mean[0] < 0:
        q_mean = -q_mean
    q_mean /= np.linalg.norm(q_mean)
    return q_mean


def invert_rigid_transform(T):
    """
    Invert a rigid 4x4 transform.
    """
    R = T[:3, :3]
    t = T[:3, 3]
    Tinv = np.eye(4, dtype=float)
    Tinv[:3, :3] = R.T
    Tinv[:3, 3] = -R.T @ t
    return Tinv


def compose_rigid(R, t):
    """
    Compose a 4x4 rigid transform from rotation and translation.
    """
    T = np.eye(4, dtype=float)
    T[:3, :3] = R
    T[:3, 3] = t
    return T


def rigid_mean_transform(mats):
    """
    Compute the mean rigid transform from a list of 4x4 transforms:
    - rotations averaged with quaternion Markley averaging
    - translations averaged arithmetically
    """
    rotations = []
    translations = []

    for M in mats:
        R = project_to_rotation(M[:3, :3])
        t = M[:3, 3]
        rotations.append(rotmat_to_quat(R))
        translations.append(t)

    q_mean = average_quaternions_markley(np.array(rotations))
    R_mean = quat_to_rotmat(q_mean)
    t_mean = np.mean(np.array(translations), axis=0)

    return compose_rigid(R_mean, t_mean)


def rotation_matrix_to_euler_xyz(R):
    """
    Extract XYZ Euler angles from a rotation matrix.

    Returns angles in radians: rx, ry, rz
    """
    R = np.asarray(R, dtype=float)
    sy = np.clip(R[0, 2], -1.0, 1.0)

    if abs(sy) < 1.0 - 1e-8:
        ry = np.arcsin(sy)
        rx = np.arctan2(-R[1, 2], R[2, 2])
        rz = np.arctan2(-R[0, 1], R[0, 0])
    else:
        ry = np.pi / 2 * np.sign(sy)
        rx = np.arctan2(R[2, 1], R[1, 1])
        rz = 0.0

    return np.array([rx, ry, rz], dtype=float)


def matrix_to_params(mat, degrees=False):
    """
    Convert a 4x4 rigid transform to motion parameters:
        rx ry rz tx ty tz
    """
    R = project_to_rotation(mat[:3, :3])
    t = mat[:3, 3]

    rot = rotation_matrix_to_euler_xyz(R)
    if degrees:
        rot = np.degrees(rot)

    return np.concatenate([rot, t])


def save_par(path, rows):
    np.savetxt(path, rows, fmt="%.6f")


def main():
    parser = argparse.ArgumentParser(
        description="Convert FSL .mat transforms to differentiated .par and mean-relative trajectory .par using rigid-transform averaging"
    )
    parser.add_argument(
        "--mat-list",
        required=True,
        help="Text file containing one matrix filename per line"
    )
    parser.add_argument(
        "--output-par",
        required=True,
        help="Output differentiated .par file"
    )
    parser.add_argument(
        "--output-mean-par",
        default=None,
        help="Output undifferentiated trajectory relative to run mean"
    )
    parser.add_argument(
        "--degrees",
        action="store_true",
        help="Write rotations in degrees instead of radians"
    )

    args = parser.parse_args()

    with open(args.mat_list, "r") as f:
        mat_paths = [line.strip() for line in f if line.strip()]

    if not mat_paths:
        raise ValueError("No matrix paths found in --mat-list")

    mats = [load_fsl_mat(p) for p in mat_paths]

    # Parameters relative to original reference
    rows_ref = np.array([matrix_to_params(M, degrees=args.degrees) for M in mats], dtype=float)

    # Frame-to-frame differentiated output
    drows = np.zeros_like(rows_ref)
    drows[1:] = rows_ref[1:] - rows_ref[:-1]
    save_par(args.output_par, drows)

    # Mean-relative output path
    output_mean_par = args.output_mean_par
    if output_mean_par is None:
        outp = Path(args.output_par)
        if outp.suffix:
            output_mean_par = str(outp.with_suffix("")) + ".mean.par"
        else:
            output_mean_par = str(outp) + ".mean.par"

    # Rigid-transform mean
    mean_T = rigid_mean_transform(mats)
    mean_T_inv = invert_rigid_transform(mean_T)

    rows_mean = []
    for M in mats:
        R = project_to_rotation(M[:3, :3])
        t = M[:3, 3]
        Mrigid = compose_rigid(R, t)

        T_mean = Mrigid @ mean_T_inv
        rows_mean.append(matrix_to_params(T_mean, degrees=args.degrees))

    rows_mean = np.array(rows_mean, dtype=float)
    save_par(output_mean_par, rows_mean)

    print(f"Wrote differentiated motion parameters to: {args.output_par}")
    print(f"Wrote mean-relative trajectory to:        {output_mean_par}")
    print(f"Rotation units: {'degrees' if args.degrees else 'radians'}")


if __name__ == "__main__":
    main()
