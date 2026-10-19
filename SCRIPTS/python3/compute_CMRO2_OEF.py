#!/usr/bin/env python3
"""
trio2oem_nifti.py

Create OEF and CMRO2 images from oxygen, water, carbon monoxide, and mask images
using the model from the original C implementation:

    [OO]  := m1[HO] + m2[OC]
    OEF   := ([OO] - m2[OC]) / (m1[HO] / 0.4)
    CMRO2 := [OO] - m2[OC]

where:
    [OO] = oxygen
    [HO] = water
    [OC] = carbon monoxide

Behavior matched to the original C code:
- mask is required
- regression fit uses only voxels where mask is valid and all needed inputs are valid
- by default, outputs are written only inside the valid mask
- with -u, outputs are written to all valid voxels regardless of mask

Usage:
    python3 trio2oem_nifti.py oxygen.nii.gz water.nii.gz carbon_monoxide.nii.gz \
        mask.nii.gz cmro2_out.nii.gz oef_out.nii.gz [-u]

Dependencies:
    pip install nibabel numpy
"""

import argparse
import os
import sys
import numpy as np
import nibabel as nib


INVALID_SENTINEL = np.float32(1.0e-37)


def is_valid(arr: np.ndarray) -> np.ndarray:
    """
    Match the C validity rule as closely as practical:

        isnormal(f) && f != 1.e-37f && f != 0.f
    """
    arr32 = np.asarray(arr, dtype=np.float32)
    return (
        np.isfinite(arr32)
        & (arr32 != np.float32(0.0))
        & (arr32 != INVALID_SENTINEL)
        & (np.abs(arr32) >= np.finfo(np.float32).tiny)
    )


def load_nifti_float32(path: str):
    """
    Read NIfTI values as interpreted by the NIfTI header.
    """
    img = nib.load(path)
    data = np.asarray(img.get_fdata(dtype=np.float32), dtype=np.float32)
    return img, data


def check_compatibility(ref_img, ref_data, test_img, test_data, label: str):
    if len(ref_data.shape) != 3 or len(test_data.shape) != 3:
        raise ValueError(f"{label} must be a 3D image")

    if ref_data.shape != test_data.shape:
        raise ValueError(f"{label} dimension mismatch: {test_data.shape} != {ref_data.shape}")

    if not np.allclose(ref_img.affine, test_img.affine, atol=1e-5):
        raise ValueError(f"{label} affine mismatch")


def validate_nifti_output_path(path: str):
    lower = path.lower()
    if not (lower.endswith(".nii") or lower.endswith(".nii.gz")):
        raise ValueError(f"Output path must end with .nii or .nii.gz: {path}")


def save_like(reference_img, data: np.ndarray, out_path: str, descrip: str):
    out_data = np.asarray(data, dtype=np.float32)
    header = reference_img.header.copy()
    header.set_data_dtype(np.float32)

    out_img = nib.Nifti1Image(out_data, reference_img.affine, header=header)
    out_img.set_data_dtype(np.float32)

    try:
        out_img.header["descrip"] = descrip.encode("utf-8")[:80]
    except Exception:
        pass

    nib.save(out_img, out_path)


def metrics_txt_path(cmro2_out: str, oef_out: str) -> str:
    cmro2_dir = os.path.abspath(os.path.dirname(cmro2_out) or ".")
    oef_dir = os.path.abspath(os.path.dirname(oef_out) or ".")
    if cmro2_dir != oef_dir:
        raise ValueError(
            "CMRO2 and OEF outputs must be in the same directory when using a fixed metrics filename M1_M2_RMS.txt"
        )
    return os.path.join(cmro2_dir, "M1_M2_RMS.txt")


def write_metrics_log(txt_path: str, m1: float, m2: float, rms: float):
    with open(txt_path, "w", encoding="utf-8") as f:
        f.write(f"M1: {m1:.10g}\n")
        f.write(f"M2: {m2:.10g}\n")
        f.write(f"RMS: {rms:.10g}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Create OEF and CMRO2 images from NIfTI oxygen, water, carbon monoxide, and mask inputs."
    )
    parser.add_argument("oxygen", help="oxygen NIfTI")
    parser.add_argument("water", help="water NIfTI")
    parser.add_argument("carbon_monoxide", help="carbon monoxide NIfTI")
    parser.add_argument("mask", help="mask NIfTI")
    parser.add_argument("cmro2_out", help="output CMRO2 NIfTI, must end in .nii or .nii.gz")
    parser.add_argument("oef_out", help="output OEF NIfTI, must end in .nii or .nii.gz")
    parser.add_argument(
        "-u",
        action="store_true",
        dest="u_flag",
        help="write values to all valid voxels, not just those within the mask",
    )

    args = parser.parse_args()

    validate_nifti_output_path(args.cmro2_out)
    validate_nifti_output_path(args.oef_out)
    txt_path = metrics_txt_path(args.cmro2_out, args.oef_out)

    print(f"Reading: {args.oxygen}")
    oo_img, oo = load_nifti_float32(args.oxygen)

    print(f"Reading: {args.water}")
    ho_img, ho = load_nifti_float32(args.water)

    print(f"Reading: {args.carbon_monoxide}")
    co_img, co = load_nifti_float32(args.carbon_monoxide)

    print(f"Reading: {args.mask}")
    msk_img, msk_raw = load_nifti_float32(args.mask)

    check_compatibility(oo_img, oo, ho_img, ho, "water")
    check_compatibility(oo_img, oo, co_img, co, "carbon monoxide")
    check_compatibility(oo_img, oo, msk_img, msk_raw, "mask")

    # Match the C behavior: mask voxels are considered included if mask is valid
    msk = is_valid(msk_raw)

    oo_valid = is_valid(oo)
    ho_valid = is_valid(ho)
    co_valid = is_valid(co)

    # Fit only inside valid mask and where all required inputs are valid
    fit_mask = msk & oo_valid & ho_valid & co_valid
    fit_voxels = int(np.count_nonzero(fit_mask))
    if fit_voxels == 0:
        raise ValueError("No valid voxels found in mask for regression")

    oo_m = oo[fit_mask].astype(np.float64, copy=False)
    ho_m = ho[fit_mask].astype(np.float64, copy=False)
    co_m = co[fit_mask].astype(np.float64, copy=False)

    oooo = np.sum(oo_m * oo_m, dtype=np.float64)
    ooho = np.sum(oo_m * ho_m, dtype=np.float64)
    ooco = np.sum(oo_m * co_m, dtype=np.float64)
    hoho = np.sum(ho_m * ho_m, dtype=np.float64)
    hoco = np.sum(ho_m * co_m, dtype=np.float64)
    coco = np.sum(co_m * co_m, dtype=np.float64)

    denom = hoho * coco - hoco * hoco
    if denom == 0.0:
        raise ZeroDivisionError("Degenerate regression system: denominator is zero")

    m1 = (ooho * coco - ooco * hoco) / denom
    m2 = (ooco * hoho - ooho * hoco) / denom

    # Preserve the original C RMS expression exactly
    rms_arg = (
        oooo
        + m1 * hoho
        + m2 * coco
        - 2.0 * m1 * ooho
        - 2.0 * m2 * ooco
        + 2.0 * m1 * m2 * coco
    ) / fit_voxels

    if rms_arg < 0 and abs(rms_arg) < 1e-12:
        rms_arg = 0.0
    rms = np.sqrt(rms_arg)

    print(f"m1 := {m1:f}")
    print(f"m2 := {m2:f}")
    print(f"rms := {rms:f}")

    # OEF output
    if args.u_flag:
        oef_mask = oo_valid & ho_valid & co_valid
    else:
        oef_mask = msk & oo_valid & ho_valid & co_valid

    oef = np.zeros(oo.shape, dtype=np.float32)
    oef[oef_mask] = (
        (oo[oef_mask].astype(np.float64) - m2 * co[oef_mask].astype(np.float64))
        / (m1 * ho[oef_mask].astype(np.float64) / 0.4)
    ).astype(np.float32)

    print(f"Writing: {args.oef_out}")
    save_like(
        oo_img,
        oef,
        args.oef_out,
        descrip=f"OEF from trio2oem_nifti; m1={m1:.6g}; m2={m2:.6g}; rms={rms:.6g}",
    )

    # CMRO2 output
    if args.u_flag:
        cmro2_mask = oo_valid & co_valid
    else:
        cmro2_mask = msk & oo_valid & co_valid

    cmro2 = np.zeros(oo.shape, dtype=np.float32)
    cmro2[cmro2_mask] = (
        oo[cmro2_mask].astype(np.float64) - m2 * co[cmro2_mask].astype(np.float64)
    ).astype(np.float32)

    print(f"Writing: {args.cmro2_out}")
    save_like(
        oo_img,
        cmro2,
        args.cmro2_out,
        descrip=f"CMRO2 from trio2oem_nifti; m1={m1:.6g}; m2={m2:.6g}; rms={rms:.6g}",
    )

    print(f"Writing: {txt_path}")
    write_metrics_log(txt_path, m1, m2, rms)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)