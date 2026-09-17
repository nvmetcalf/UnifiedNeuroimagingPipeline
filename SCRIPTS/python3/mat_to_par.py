#!/usr/bin/env python3
"""
mat_to_par.py

Convert a list of FSL FLIRT/MCFLIRT 4x4 affine matrices into a nondifferentiated
motion parameter `.par` file.

Output convention
-----------------
    rx ry rz tx ty tz

Rotations are written in radians by default, or degrees with --degrees.

Notes
-----
- This is intended to approximate a standard MCFLIRT-like parameter trajectory
  from saved affine matrices.
- It does not guarantee exact numerical identity to MCFLIRT's native `.par`
  output, because MCFLIRT may use internal conventions not perfectly reproduced
  by Euler extraction from stored matrices.
"""

import argparse
import numpy as np


def load_fsl_mat(path):
    mat = np.loadtxt(path)
    if mat.shape != (4, 4):
        raise ValueError(f"{path} does not contain a 4x4 matrix, got shape {mat.shape}")
    return mat


def rotation_matrix_to_euler_xyz(R):
    """
    Extract XYZ Euler angles from a rotation matrix.

    Returns
    -------
    np.ndarray, shape [3]
        rx, ry, rz in radians
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
    R = mat[:3, :3]
    t = mat[:3, 3]
    rot = rotation_matrix_to_euler_xyz(R)
    if degrees:
        rot = np.degrees(rot)
    return np.concatenate([rot, t])


def main():
    parser = argparse.ArgumentParser(
        description="Convert FSL .mat transforms to a nondifferentiated .par file"
    )
    parser.add_argument(
        "--mat-list",
        required=True,
        help="Text file containing one matrix filename per line"
    )
    parser.add_argument(
        "--output-par",
        required=True,
        help="Output nondifferentiated .par file"
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
    rows = np.array([matrix_to_params(M, degrees=args.degrees) for M in mats], dtype=float)

    np.savetxt(args.output_par, rows, fmt="%.6f")
    print(f"Wrote nondifferentiated motion parameters to: {args.output_par}")
    print(f"Rotation units: {'degrees' if args.degrees else 'radians'}")


if __name__ == "__main__":
    main()
