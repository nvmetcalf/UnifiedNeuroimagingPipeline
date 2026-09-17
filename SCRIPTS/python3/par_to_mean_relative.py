#!/usr/bin/env python3
"""
par_to_mean_relative.py

Convert a nondifferentiated motion parameter `.par` file into a mean-relative
trajectory using one of two methods:

Methods
-------
1. demean
   Subtract the column-wise mean from each parameter.

2. rigid
   Interpret each row as a rigid transform:
       rx ry rz tx ty tz
   compute a rigid-body mean transform, then express each frame relative to it.

	Markley, F. L., Cheng, Y., Crassidis, J. L., & Oshman, Y. (2007). Average quaternion. Journal of Guidance, Control, and Dynamics, 30(4), 1193-1197. https://doi.org/10.2514/1.28949

Input convention
----------------
    rx ry rz tx ty tz

Rotations are assumed to be radians by default, or degrees with --degrees.
"""

import argparse
import numpy as np


def load_par(path, degrees=False):
    rows = np.loadtxt(path)
    if rows.ndim == 1:
        rows = rows[None, :]
    if rows.shape[1] != 6:
        raise ValueError(f"{path} must have 6 columns, got shape {rows.shape}")
    rows = rows.astype(float)
    if degrees:
        rows[:, :3] = np.radians(rows[:, :3])
    return rows


def save_par(path, rows, degrees=False):
    rows = np.array(rows, dtype=float)
    out = rows.copy()
    if degrees:
        out[:, :3] = np.degrees(out[:, :3])
    np.savetxt(path, out, fmt="%.6f")


def euler_xyz_to_rotmat(rx, ry, rz):
    cx, sx = np.cos(rx), np.sin(rx)
    cy, sy = np.cos(ry), np.sin(ry)
    cz, sz = np.cos(rz), np.sin(rz)

    Rx = np.array([
        [1, 0, 0],
        [0, cx, -sx],
        [0, sx, cx]
    ], dtype=float)

    Ry = np.array([
        [cy, 0, sy],
        [0, 1, 0],
        [-sy, 0, cy]
    ], dtype=float)

    Rz = np.array([
        [cz, -sz, 0],
        [sz, cz, 0],
        [0, 0, 1]
    ], dtype=float)

    return Rx @ Ry @ Rz


def rotation_matrix_to_euler_xyz(R):
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


def params_to_transform(row):
    rx, ry, rz, tx, ty, tz = row
    R = euler_xyz_to_rotmat(rx, ry, rz)
    T = np.eye(4, dtype=float)
    T[:3, :3] = R
    T[:3, 3] = [tx, ty, tz]
    return T


def transform_to_params(T):
    R = T[:3, :3]
    t = T[:3, 3]
    rot = rotation_matrix_to_euler_xyz(R)
    return np.concatenate([rot, t])


def rotmat_to_quat(R):
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
    q = np.asarray(q, dtype=float)
    q /= np.linalg.norm(q)
    w, x, y, z = q

    return np.array([
        [1 - 2*(y*y + z*z),     2*(x*y - z*w),     2*(x*z + y*w)],
        [    2*(x*y + z*w), 1 - 2*(x*x + z*z),     2*(y*z - x*w)],
        [    2*(x*z - y*w),     2*(y*z + x*w), 1 - 2*(x*x + y*y)],
    ], dtype=float)


def average_quaternions_markley(quats):
    quats = np.asarray(quats, dtype=float)
    A = np.zeros((4, 4), dtype=float)

    for q in quats:
        q = q / np.linalg.norm(q)
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
    R = T[:3, :3]
    t = T[:3, 3]
    out = np.eye(4, dtype=float)
    out[:3, :3] = R.T
    out[:3, 3] = -R.T @ t
    return out


def rigid_mean_from_par(rows):
    quats = []
    translations = []

    for row in rows:
        T = params_to_transform(row)
        quats.append(rotmat_to_quat(T[:3, :3]))
        translations.append(T[:3, 3])

    q_mean = average_quaternions_markley(np.array(quats))
    R_mean = quat_to_rotmat(q_mean)
    t_mean = np.mean(np.array(translations), axis=0)

    T_mean = np.eye(4, dtype=float)
    T_mean[:3, :3] = R_mean
    T_mean[:3, 3] = t_mean
    return T_mean


def main():
    parser = argparse.ArgumentParser(
        description="Compute mean-relative motion trajectory from a .par file"
    )
    parser.add_argument(
        "--input-par",
        required=True,
        help="Input nondifferentiated .par file"
    )
    parser.add_argument(
        "--output-par",
        required=True,
        help="Output mean-relative .par file"
    )
    parser.add_argument(
        "--method",
        choices=["demean", "rigid"],
        default="demean",
        help="Method for computing mean-relative trajectory"
    )
    parser.add_argument(
        "--degrees",
        action="store_true",
        help="Interpret input rotations as degrees and write output rotations as degrees"
    )
    args = parser.parse_args()

    rows = load_par(args.input_par, degrees=args.degrees)

    if args.method == "demean":
        out = rows - np.mean(rows, axis=0, keepdims=True)

    elif args.method == "rigid":
        T_mean = rigid_mean_from_par(rows)
        T_mean_inv = invert_rigid_transform(T_mean)

        out = []
        for row in rows:
            T = params_to_transform(row)
            T_rel = T @ T_mean_inv
            out.append(transform_to_params(T_rel))
        out = np.array(out, dtype=float)

    save_par(args.output_par, out, degrees=args.degrees)
    print(f"Wrote mean-relative motion trajectory to: {args.output_par}")
    print(f"Method: {args.method}")
    print(f"Rotation units: {'degrees' if args.degrees else 'radians'}")


if __name__ == "__main__":
    main()
