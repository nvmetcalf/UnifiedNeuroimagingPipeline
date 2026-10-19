#!/usr/bin/env python3
"""
NIfTI-only rewrite of residual_4dfp.c.

This script preserves the core numerical behavior of the original C code while
replacing all 4dfp-specific I/O with NIfTI I/O.

Features
--------
- Input images: .nii or .nii.gz
- Optional mask: .nii or .nii.gz
- Output image: NIfTI, typically .nii.gz
- Optional text export of valid voxel pairs via -t
- Optional stdout mirroring to a flat text file via --stdout-file
- Extensive comments for easier debugging
- Citations included in docstrings/comments

References
----------
[^1]: NiBabel documentation: https://nipy.org/nibabel/
[^2]: Python Standard Library documentation: https://docs.python.org/3/
[^3]: IEEE Standard for Floating-Point Arithmetic, IEEE 754.
[^4]: Standard formulas for simple linear regression and Pearson correlation.
"""

from __future__ import annotations

import math
import os
import sys
from typing import List, Optional, Tuple

import nibabel as nib
import numpy as np


# -----------------------------------------------------------------------------
# Stdout mirroring helper
# -----------------------------------------------------------------------------

class TeeStdout:
    """
    Mirror stdout to both the terminal and an optional text file.

    Citation:
    [^2] Python file-like object behavior and stream handling are documented in
    the Python standard library.
    """

    def __init__(self, stream, file_handle=None):
        self.stream = stream
        self.file_handle = file_handle

    def write(self, data: str) -> None:
        self.stream.write(data)
        if self.file_handle is not None:
            self.file_handle.write(data)

    def flush(self) -> None:
        self.stream.flush()
        if self.file_handle is not None:
            self.file_handle.flush()


# -----------------------------------------------------------------------------
# Error helpers
# -----------------------------------------------------------------------------

def errr(program: str, path: str) -> None:
    """
    Report a read error and exit.

    Citation:
    [^2] Python exception and stderr behavior.
    """
    print(f"{program}: error reading {path}", file=sys.stderr)
    sys.exit(-1)


def errw(program: str, path: str) -> None:
    """
    Report a write error and exit.

    Citation:
    [^2] Python exception and stderr behavior.
    """
    print(f"{program}: error writing {path}", file=sys.stderr)
    sys.exit(-1)


# -----------------------------------------------------------------------------
# Basic helpers
# -----------------------------------------------------------------------------

def setprog(argv0: str) -> str:
    """
    Return the program name from argv[0], similar to the C helper.

    Citation:
    [^2] os.path.basename documentation.
    """
    return os.path.basename(argv0)


def is_nifti_path(path: str) -> bool:
    """
    Return True if the path ends with .nii or .nii.gz.

    Citation:
    [^2] Python string methods.
    """
    return path.endswith(".nii") or path.endswith(".nii.gz")


def ensure_nifti_input(path: str, program: str) -> str:
    """
    Validate that an input path is a NIfTI path.

    Citation:
    [^2] Python string handling and validation.
    """
    if not is_nifti_path(path):
        print(f"{program}: input must be .nii or .nii.gz -> {path}", file=sys.stderr)
        sys.exit(1)
    return path


def make_output_nifti_path(outroot: str) -> str:
    """
    Convert an output root or filename into a NIfTI output path.

    Rules:
    - if user already supplies .nii or .nii.gz, keep it
    - otherwise append .nii.gz

    Citation:
    [^2] Python string handling.
    """
    if outroot.endswith(".nii") or outroot.endswith(".nii.gz"):
        return outroot
    return f"{outroot}.nii.gz"


def make_text_root(outroot: str) -> str:
    """
    Strip .nii or .nii.gz from an output path for sidecar text naming.

    Examples:
    - out.nii.gz -> out
    - out.nii    -> out
    - out        -> out

    Citation:
    [^2] Python string handling.
    """
    if outroot.endswith(".nii.gz"):
        return outroot[:-7]
    if outroot.endswith(".nii"):
        return outroot[:-4]
    return outroot


def isvalid(f: float) -> bool:
    """
    Preserve the original C validity rule as closely as possible.

    Original C:
        return (isnormal(f) && f != (float) 1.e-37 && f != 0.);

    In practice this means:
    - finite
    - not zero
    - not exactly 1e-37
    - not subnormal

    Since the original C code works with float values, we apply a float32-style
    threshold for normal values.

    Citations:
    [^2] Python math.isfinite.
    [^3] IEEE 754 normal and subnormal floating-point values.
    """
    if not math.isfinite(f):
        return False
    if f == 0.0 or f == 1.0e-37:
        return False

    # Smallest positive normal IEEE-754 binary32 value.
    return abs(f) >= 1.1754943508222875e-38


# -----------------------------------------------------------------------------
# NIfTI I/O helpers
# -----------------------------------------------------------------------------

def load_nifti(path: str, program: str) -> Tuple[nib.Nifti1Image, np.ndarray]:
    """
    Load a NIfTI image and return:
    - the nibabel image object
    - the image data as float32 ndarray

    This script requires 3D images to match the original C program's behavior.

    Citations:
    [^1] NiBabel image loading.
    [^2] NumPy array conversion and shape handling.
    """
    try:
        img = nib.load(path)
    except Exception:
        errr(program, path)

    try:
        # Force float32 for closer behavior to the C program's float arrays.
        data = np.asanyarray(img.get_fdata(dtype=np.float32), dtype=np.float32)
    except Exception:
        errr(program, path)

    if data.ndim != 3:
        print(f"{program}: only 3D NIfTI images are supported -> {path}", file=sys.stderr)
        sys.exit(-1)

    return img, data


def save_nifti(program: str, outpath: str, data: np.ndarray, reference_img: nib.Nifti1Image) -> None:
    """
    Save output data as a NIfTI image, preserving affine and using a copied
    header from the reference image where possible.

    The output datatype is set to float32 to match the original C program's
    float output.

    Citations:
    [^1] NiBabel image creation and saving.
    [^2] NumPy dtype handling.
    """
    try:
        header = reference_img.header.copy()
        header.set_data_dtype(np.float32)
        out_img = nib.Nifti1Image(data.astype(np.float32), reference_img.affine, header=header)
        nib.save(out_img, outpath)
    except Exception:
        errw(program, outpath)


# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

def parse_args(argv: List[str]) -> Tuple[str, str, str, str, float, bool, Optional[str]]:
    """
    Parse arguments in a style close to the original C program, but allow both
    attached and space-separated flag values.

    Supported forms:
    -m mask.nii.gz
    -mmask.nii.gz
    -n 1000
    -n1000
    -t
    --stdout-file run.log

    Positional:
    1. image1.nii or image1.nii.gz
    2. image2.nii or image2.nii.gz
    3. outroot or output.nii or output.nii.gz

    Returns:
        image1_path, image2_path, outroot, mask_path, normal, text_flag, stdout_file

    Citation:
    [^2] Manual argv parsing and list traversal in Python.
    """
    program = setprog(argv[0])

    positional: List[str] = []
    mask_path = ""
    normal = 0.0
    text_flag = False
    stdout_file: Optional[str] = None

    i = 1
    while i < len(argv):
        arg = argv[i]

        if arg == "--stdout-file":
            if i + 1 >= len(argv):
                print(f"{program}: missing value for --stdout-file", file=sys.stderr)
                sys.exit(1)
            stdout_file = argv[i + 1]
            i += 2
            continue

        if arg == "-m":
            if i + 1 >= len(argv):
                print(f"{program}: missing value for -m", file=sys.stderr)
                sys.exit(1)
            mask_path = argv[i + 1]
            i += 2
            continue

        if arg.startswith("-m") and arg != "-m":
            mask_path = arg[2:]
            if not mask_path:
                print(f"{program}: missing value for -m", file=sys.stderr)
                sys.exit(1)
            i += 1
            continue

        if arg == "-n":
            if i + 1 >= len(argv):
                print(f"{program}: missing value for -n", file=sys.stderr)
                sys.exit(1)
            try:
                normal = float(argv[i + 1])
            except ValueError:
                print(f"{program}: invalid -n value: {argv[i + 1]}", file=sys.stderr)
                sys.exit(1)
            i += 2
            continue

        if arg.startswith("-n") and arg != "-n":
            try:
                normal = float(arg[2:])
            except ValueError:
                print(f"{program}: invalid -n value in {arg}", file=sys.stderr)
                sys.exit(1)
            i += 1
            continue

        if arg == "-t":
            text_flag = True
            i += 1
            continue

        if arg.startswith("-") and arg not in ("-", "--"):
            recognized = True
            for c in arg[1:]:
                if c == "t":
                    text_flag = True
                else:
                    recognized = False
                    break
            if recognized:
                i += 1
                continue

        positional.append(arg)
        i += 1

    if len(positional) != 3:
        print(f"Usage:\t{program} <image1.nii|image1.nii.gz> <image2.nii|image2.nii.gz> <outroot|output.nii.gz>", file=sys.stderr)
        print(f" e.g.:\t{program} om.nii.gz fdg.nii.gz out -m mask.nii.gz -n 1000", file=sys.stderr)
        print("\toptions", file=sys.stderr)
        print("\t-m <mask>\tuse only within mask voxels", file=sys.stderr)
        print("\t-n <float>\tscale image2 mean to <float>", file=sys.stderr)
        print("\t-t\trecord voxel values in a text file", file=sys.stderr)
        print("\t--stdout-file <file>\tmirror standard output to a text file", file=sys.stderr)
        sys.exit(1)

    image1_path = ensure_nifti_input(positional[0], program)
    image2_path = ensure_nifti_input(positional[1], program)

    if mask_path:
        mask_path = ensure_nifti_input(mask_path, program)

    outroot = positional[2]

    return image1_path, image2_path, outroot, mask_path, normal, text_flag, stdout_file


# -----------------------------------------------------------------------------
# Main computation
# -----------------------------------------------------------------------------

def main(argv: List[str]) -> int:
    """
    Main entry point.

    Preserved core formulas from the C program:
    - slope     = (n*xy - x*y) / (n*xx - x*x)
    - intercept = (y - slope*x) / n
    - pearson   = (n*xy - x*y) / sqrt(n*xx - x*x) / sqrt(n*yy - y*y)

    If -n<float> is used:
    - normal = target_mean / observed_mean_of_image2_over_valid_voxels
    - slope and intercept are scaled by normal

    Output voxel formula preserved from the active C code:
    - out = normal*img2 - slope*img1 - intercept
      where both img1 and img2 are valid, else 0

    Citations:
    [^2] Python math and I/O behavior.
    [^4] Standard linear regression and Pearson correlation formulas.
    """
    program = setprog(argv[0])

    image1_path, image2_path, outroot, mask_path, normal, text_flag, stdout_file = parse_args(argv)

    stdout_log_handle = None
    original_stdout = sys.stdout
    if stdout_file is not None:
        try:
            stdout_log_handle = open(stdout_file, "w", encoding="utf-8")
            sys.stdout = TeeStdout(sys.stdout, stdout_log_handle)
        except OSError:
            print(f"{program}: error writing {stdout_file}", file=sys.stderr)
            return -1

    try:
        img1_nii, img1 = load_nifti(image1_path, program)
        _, img2 = load_nifti(image2_path, program)

        if img1.shape != img2.shape:
            print(f"{program}: {image2_path} dimension mismatch", file=sys.stderr)
            return -1

        if mask_path:
            _, mask_data = load_nifti(mask_path, program)
            if img1.shape != mask_data.shape:
                print(f"{program}: {mask_path} dimension mismatch", file=sys.stderr)
                return -1

            mask_bool = np.zeros(img1.shape, dtype=bool)
            it = np.nditer(mask_data, flags=["multi_index"])
            while not it.finished:
                mask_bool[it.multi_index] = isvalid(float(it[0]))
                it.iternext()
        else:
            mask_bool = np.ones(img1.shape, dtype=bool)

        valid1 = np.zeros(img1.shape, dtype=bool)
        valid2 = np.zeros(img2.shape, dtype=bool)

        it1 = np.nditer(img1, flags=["multi_index"])
        while not it1.finished:
            valid1[it1.multi_index] = isvalid(float(it1[0]))
            it1.iternext()

        it2 = np.nditer(img2, flags=["multi_index"])
        while not it2.finished:
            valid2[it2.multi_index] = isvalid(float(it2[0]))
            it2.iternext()

        stats_mask = mask_bool & valid1 & valid2

        mskvol = int(np.count_nonzero(stats_mask))
        if mskvol == 0:
            print(f"{program}: no valid voxels", file=sys.stderr)
            return -1

        v1 = img1[stats_mask].astype(np.float64)
        v2 = img2[stats_mask].astype(np.float64)

        xx = float(np.sum(v1 * v1))
        xy = float(np.sum(v1 * v2))
        yy = float(np.sum(v2 * v2))
        x = float(np.sum(v1))
        y = float(np.sum(v2))

        denom_slope = (mskvol * xx - x * x)
        denom_pearson_left = (mskvol * xx - x * x)
        denom_pearson_right = (mskvol * yy - y * y)

        if denom_slope == 0.0:
            print(f"{program}: zero slope denominator", file=sys.stderr)
            return -1

        if denom_pearson_left <= 0.0 or denom_pearson_right <= 0.0:
            print(f"{program}: invalid pearson denominator", file=sys.stderr)
            return -1

        slope = (mskvol * xy - x * y) / denom_slope
        intercept = (y - slope * x) / mskvol
        pearson = (mskvol * xy - x * y) / (
            math.sqrt(denom_pearson_left) * math.sqrt(denom_pearson_right)
        )

        if normal != 0.0:
            normal = normal / (y / mskvol)
            slope *= normal
            intercept *= normal
        else:
            normal = 1.0

        print(f"scale    := {normal:f}")
        print(f"slope     := {slope:f}")
        print(f"intercept := {intercept:f}")
        print(f"pearson   := {pearson:f}")

        if text_flag:
            txt_root = make_text_root(outroot)
            txt_path = f"{txt_root}.txt"
            try:
                with open(txt_path, "w", encoding="utf-8") as fp:
                    flat_v1 = v1.tolist()
                    flat_v2 = v2.tolist()
                    for a, b in zip(flat_v1, flat_v2):
                        fp.write(f"{a:10.6f}\t{b:10.6f}\n")
            except OSError:
                errw(program, txt_path)

        out = np.zeros(img1.shape, dtype=np.float32)
        out_valid = valid1 & valid2
        out[out_valid] = (
            normal * img2[out_valid].astype(np.float64)
            - slope * img1[out_valid].astype(np.float64)
            - intercept
        ).astype(np.float32)

        outpath = make_output_nifti_path(outroot)
        print(f"Writing: {outpath}")
        save_nifti(program, outpath, out, img1_nii)

        return 0

    finally:
        if stdout_log_handle is not None:
            sys.stdout.flush()
            sys.stdout = original_stdout
            stdout_log_handle.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
