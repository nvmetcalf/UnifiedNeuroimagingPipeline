#!/usr/bin/env python3

import argparse
import json
import math
from pathlib import Path

import nibabel as nib
import numpy as np


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Sum selected frames from a dynamic PET 4D NIfTI using a PET JSON sidecar. "
            "This reproduces the core behavior of sum_pet_4dfp.c using NIfTI + JSON."
        )
    )

    parser.add_argument(
        "--input",
        required=True,
        help="Input 4D PET NIfTI file"
    )
    parser.add_argument(
        "--metadata",
        required=True,
        help="Input PET JSON metadata file"
    )
    parser.add_argument(
        "--start-frame",
        type=int,
        required=True,
        help="First frame to include, 1-based"
    )
    parser.add_argument(
        "--end-frame",
        type=int,
        required=True,
        help="Last frame to include, 1-based"
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output 3D NIfTI file"
    )

    parser.add_argument(
        "--half-life",
        type=float,
        default=None,
        help="Half-life in seconds for recomputed decay correction"
    )
    parser.add_argument(
        "--use-json-half-life",
        action="store_true",
        help="Use RadionuclideHalfLife from JSON if available"
    )
    parser.add_argument(
        "--use-first-decay",
        action="store_true",
        help="Use first selected frame's decay factor instead of computed common decay correction"
    )
    parser.add_argument(
        "--scale-factor",
        type=float,
        default=1.0,
        help="Final multiplicative scale factor"
    )
    parser.add_argument(
        "--output-json",
        default=None,
        help="Optional output JSON sidecar path"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print per-frame details"
    )

    return parser.parse_args()


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def get_required_array(meta, key):
    if key not in meta:
        raise ValueError(f"Missing required JSON field: {key}")
    value = meta[key]
    if not isinstance(value, list):
        raise ValueError(f"JSON field '{key}' must be a list")
    return value


def get_optional_float(meta, key):
    if key not in meta:
        return None
    value = meta[key]
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        raise ValueError(f"JSON field '{key}' must be convertible to float, got: {value!r}")


def compute_decay_correction(half_life, start_time, duration_total):
    if half_life <= 0:
        raise ValueError("half_life must be > 0")
    if duration_total <= 0:
        raise ValueError("duration_total must be > 0")

    lam = math.log(2.0) / half_life
    numerator = duration_total * lam
    denominator = math.exp(-lam * start_time) * (1.0 - math.exp(-lam * duration_total))

    if denominator == 0:
        raise ZeroDivisionError("Decay correction denominator is zero")

    return numerator / denominator


def main():
    args = parse_args()

    # Load image
    nii = nib.load(args.input)
    data = nii.get_fdata(dtype=np.float32)

    if data.ndim != 4:
        raise ValueError(f"Input image must be 4D, got shape {data.shape}")

    nx, ny, nz, nt = data.shape

    # Validate frame range
    if args.start_frame < 1 or args.end_frame < 1:
        raise ValueError("Frame indices must be 1-based positive integers")
    if args.start_frame > args.end_frame:
        raise ValueError("start-frame must be <= end-frame")
    if args.end_frame > nt:
        raise ValueError(
            f"Requested end-frame {args.end_frame} exceeds image frame count {nt}"
        )

    # Load metadata
    meta = load_json(args.metadata)

    decay_factors = get_required_array(meta, "DecayFactor")
    frame_starts = get_required_array(meta, "FrameTimesStart")
    frame_durations = get_required_array(meta, "FrameDuration")
    frame_reference_times = get_required_array(meta, "FrameReferenceTime")

    # Validate array lengths
    for key, arr in [
        ("DecayFactor", decay_factors),
        ("FrameTimesStart", frame_starts),
        ("FrameDuration", frame_durations),
        ("FrameReferenceTime", frame_reference_times),
    ]:
        if len(arr) < nt:
            raise ValueError(
                f"JSON field '{key}' has {len(arr)} entries but image has {nt} frames"
            )

    # Determine half-life
    half_life = args.half_life
    if half_life is None and args.use_json_half_life:
        half_life = get_optional_float(meta, "RadionuclideHalfLife")

    start_idx = args.start_frame - 1
    end_idx = args.end_frame - 1

    summed = np.zeros((nx, ny, nz), dtype=np.float64)
    duration_total = 0.0

    first_decay_factor = None
    first_start_time = None

    frame_records = []

    for k in range(start_idx, end_idx + 1):
        decay_factor = float(decay_factors[k])
        frame_start = float(frame_starts[k])
        duration = float(frame_durations[k])
        reference_time = float(frame_reference_times[k])

        if k == start_idx:
            first_decay_factor = decay_factor
            # Preserve original C behavior:
            first_start_time = reference_time - duration / 2.0

        frame = data[..., k].astype(np.float64, copy=True)

        # Undo input decay correction, matching original behavior
        if decay_factor > 0:
            frame /= decay_factor

        # Weight by duration
        if duration > 0:
            frame *= duration
            duration_total += duration

        summed += frame

        frame_records.append({
            "frame_1_based": k + 1,
            "decay_factor": decay_factor,
            "frame_start_seconds": frame_start,
            "duration_seconds": duration,
            "reference_time_seconds": reference_time
        })

        if args.verbose:
            print(
                f"Frame {k+1:3d}: "
                f"start={frame_start:8.3f} s, "
                f"dur={duration:8.3f} s, "
                f"ref={reference_time:8.3f} s, "
                f"decay={decay_factor:10.6f}"
            )

    if duration_total <= 0:
        raise ValueError("Total selected duration is <= 0")

    # Duration-weighted average
    out = summed / duration_total

    # Reapply common decay correction if requested
    applied_decay_factor = 1.0
    decay_mode = "none"

    if args.use_first_decay:
        applied_decay_factor = first_decay_factor
        decay_mode = "first_selected_frame_decay_factor"
    elif half_life is not None:
        applied_decay_factor = compute_decay_correction(
            half_life=half_life,
            start_time=first_start_time,
            duration_total=duration_total
        )
        decay_mode = "computed_from_half_life"

    # Apply common decay correction
    out *= applied_decay_factor

    # Apply final scale factor
    out *= args.scale_factor

    out = out.astype(np.float32)

    # Create output image
    out_header = nii.header.copy()
    out_img = nib.Nifti1Image(out, affine=nii.affine, header=out_header)
    out_img.header.set_data_shape(out.shape)
    nib.save(out_img, args.output)

    # Output JSON sidecar
    output_json = args.output_json
    if output_json is None:
        output_json = str(Path(args.output).with_suffix("").with_suffix("")) + ".json"

    result = {
        "SourceImage": args.input,
        "SourceMetadata": args.metadata,
        "OutputImage": args.output,
        "FrameRange": {
            "StartFrame1Based": args.start_frame,
            "EndFrame1Based": args.end_frame,
            "FrameCount": args.end_frame - args.start_frame + 1
        },
        "SelectedFrames": frame_records,
        "TotalDurationSeconds": duration_total,
        "FirstSelectedFrameStartTimeSeconds": first_start_time,
        "HalfLifeSecondsUsed": half_life,
        "DecayCorrectionMode": decay_mode,
        "AppliedDecayFactor": applied_decay_factor,
        "ScaleFactor": args.scale_factor,
        "InputUnits": meta.get("Units"),
        "InputDecayCorrection": meta.get("DecayCorrection"),
        "Algorithm": {
            "PerFrameOperation": "divide by DecayFactor, multiply by FrameDuration, sum over selected frames",
            "FinalOperation": "divide by total duration, optionally apply common decay correction, then scale"
        }
    }

    with open(output_json, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    if args.verbose:
        print("")
        print(f"Output image: {args.output}")
        print(f"Output json : {output_json}")
        print(f"Total duration: {duration_total:.6f} s")
        print(f"First start time: {first_start_time:.6f} s")
        print(f"Decay mode: {decay_mode}")
        print(f"Applied decay factor: {applied_decay_factor:.8f}")
        print(f"Scale factor: {args.scale_factor:.8f}")


if __name__ == "__main__":
    main()

