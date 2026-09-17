#!/usr/bin/env python3
"""
par_to_diff.py

Convert a nondifferentiated 6-column motion parameter `.par` file into a
frame-to-frame differentiated `.par` file.

Input convention
----------------
    rx ry rz tx ty tz

Output convention
-----------------
    rx ry rz tx ty tz

Methods
-------
1. simple
   Simple parameter differencing:
       d_0 = 0
       d_i = p_i - p_{i-1}

   This is the conventional finite-difference style derivative used for motion
   parameter regressors in many fMRI preprocessing and nuisance-regression
   workflows. It treats the six motion parameters as ordinary Euclidean
   coordinates and differences them column-wise.

2. rigid
   Treat each row as a rigid transform T_i and compute:
       d_0 = identity
       T_rel_i = T_i @ inv(T_{i-1})
   then convert T_rel_i back to rx ry rz tx ty tz

   This is a more geometrically faithful rigid-body differencing method because
   it computes the relative motion in SE(3) rather than subtracting parameter
   coordinates directly.

References
----------
Simple parameter differencing for motion regressors:
- Friston, K. J., Williams, S., Howard, R., Frackowiak, R. S. J., & Turner, R.
  (1996). Movement-related effects in fMRI time-series. Magnetic Resonance in
  Medicine, 35(3), 346-355. https://doi.org/10.1002/mrm.1910350312

Background on rigid-body transforms and composition:
- Murray, R. M., Li, Z., & Sastry, S. S. (1994). A Mathematical Introduction
  to Robotic Manipulation. CRC Press.

Background on averaging and geometry of rotations:
- Moakher, M. (2002). Means and averaging in the group of rotations.
  SIAM Journal on Matrix Analysis and Applications, 24(1), 1-16.
  https://doi.org/10.1137/S0895479801383877

Notes
-----
- The `simple` method is the more conventional choice for standard fMRI motion
  derivative regressors.
- The `rigid` method is more geometrically principled, but is not the usual
  default in most neuroimaging software when motion "derivatives" are requested.
- This script assumes a consistent Euler-angle convention for converting between
  parameter rows and rigid transforms.
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


def invert_rigid_transform(T):
    R = T[:3, :3]
    t = T[:3, 3]
    out = np.eye(4, dtype=float)
    out[:3, :3] = R.T
    out[:3, 3] = -R.T @ t
    return out


def diff_simple(rows):
    drows = np.zeros_like(rows)
    drows[1:] = rows[1:] - rows[:-1]
    return drows


def diff_rigid(rows):
    out = np.zeros_like(rows)

    for i in range(1, len(rows)):
        T_prev = params_to_transform(rows[i - 1])
        T_curr = params_to_transform(rows[i])
        T_rel = T_curr @ invert_rigid_transform(T_prev)
        out[i] = transform_to_params(T_rel)

    return out


def main():
    parser = argparse.ArgumentParser(
        description="Convert a nondifferentiated .par file to a differentiated .par file"
    )
    parser.add_argument(
        "--input-par",
        required=True,
        help="Input nondifferentiated .par file"
    )
    parser.add_argument(
        "--output-par",
        required=True,
        help="Output differentiated .par file"
    )
    parser.add_argument(
        "--method",
        choices=["simple", "rigid"],
        default="simple",
        help="Differencing method"
    )
    parser.add_argument(
        "--degrees",
        action="store_true",
        help="Interpret input rotations as degrees and write output rotations as degrees"
    )
    args = parser.parse_args()

    rows = load_par(args.input_par, degrees=args.degrees)

    if args.method == "simple":
        out = diff_simple(rows)
    elif args.method == "rigid":
        out = diff_rigid(rows)
    else:
        raise ValueError(f"Unknown method: {args.method}")

    save_par(args.output_par, out, degrees=args.degrees)

    print(f"Wrote differentiated motion parameters to: {args.output_par}")
    print(f"Method: {args.method}")
    print(f"Rotation units: {'degrees' if args.degrees else 'radians'}")


if __name__ == "__main__":
    main()

