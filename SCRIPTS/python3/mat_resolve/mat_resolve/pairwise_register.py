"""
pairwise_register.py
====================
Register every pair of frames in a 4D NIfTI using FSL flirt (6 DOF, rigid body).

Frames are extracted to a temporary directory, all ordered pairs are submitted
to a thread pool (one flirt subprocess per thread), and the resulting ``.mat``
files are written to the output directory.  The output naming matches the
default pattern expected by ``mat_resolve``.

Usage
-----
   mat_resolve_pairwise INPUT_4D OUTPUT_DIR \\
        [--skip-before IDX] \\
        [--workers N] \\
        [--pattern TMPL] \\
        [--full-search] \\
        [--verbose]

``INPUT`` normally takes a single 4D NIfTI, whose frames are extracted and
registered pairwise (as above). Passing *more than one* path instead switches
to a standalone-images mode: each path must be its own 3D NIfTI (e.g. one
representative volume per scan session), named by its filename stem, and
every ordered pair among them is registered directly -- useful for
between-session registration. ``--skip-before`` does not apply in this mode.

The pairwise flirt call defaults to ``-nosearch -usesqform``, which assumes
the two images already share a common sqform alignment (true for frames of
one 4D series, but not generally true across sessions). Pass ``--full-search``
to drop both flags and let flirt do a normal blind search instead.
"""
# pylint: disable=invalid-name

import argparse
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import nibabel as nib

from .bolus_onset import estimate_bolus_onset as _estimate_bolus_onset
from .bolus_onset import read_frame_durations as _read_frame_durations
from .bolus_onset import write_bolus_onset_outputs as _write_bolus_onset_outputs
from .nifti_frames import extract_frames as _extract_frames
from .nifti_frames import load_images as _load_images
from .nifti_frames import stem as _stem

_PROG = "mat_resolve_pairwise"


def _run_flirt(
    moving_name, moving_path, fixed_name, fixed_path, output_dir, pattern,
    apply=False, full_search=False,
):
    """
    Run ``flirt -dof 6`` for one (moving, fixed) pair.

    Parameters
    ----------
    moving_name, fixed_name : str
        Frame name labels used to build the output filename.
    moving_path, fixed_path : Path
        Extracted 3D NIfTI files.
    output_dir : Path
        Directory to write the ``.mat`` file into.
    pattern : str
        Filename template, e.g. ``"{moving}_to_{fixed}.mat"``.
    full_search : bool
        If False (default), pass ``-nosearch -usesqform`` (assumes the pair
        already shares a common sqform alignment). If True, omit both flags
        and let flirt do a normal blind search.

    Returns
    -------
    label : str
    success : bool
    error : str or None
    """
    mat_path = output_dir / pattern.format(moving=moving_name, fixed=fixed_name)
    cmd = [
        "flirt",
        "-in", str(moving_path),
        "-ref", str(fixed_path),
        "-dof", "6",
        "-omat", str(mat_path),
    ]
    if not full_search:
        cmd.extend(["-nosearch", "-usesqform"])
    if apply:
        out_path = output_dir / f"{moving_name}_on_{fixed_name}.nii.gz"
        cmd.extend(["-o", str(out_path)])

    result = subprocess.run(cmd, capture_output=True, text=True)
    label = f"{moving_name} -> {fixed_name}"
    if result.returncode != 0:
        return label, False, result.stderr.strip()
    return label, True, None


def _skip_before_value(value):
    """argparse ``type`` for ``--skip-before``: the literal 'auto', or an int."""
    if value == "auto":
        return value
    try:
        return int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"--skip-before must be an integer or 'auto', got {value!r}"
        ) from exc


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        prog=_PROG,
        description=(
            "Register every pair of frames in a 4D NIfTI using FSL flirt "
            "(6 DOF rigid body).  Output .mat files are named to match the "
            "default pattern expected by mat_resolve."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "inputs",
        metavar="INPUT",
        nargs="+",
        help=(
            "A single 4D NIfTI file (.nii or .nii.gz), whose frames are "
            "extracted and registered pairwise; or two or more standalone "
            "3D NIfTI files to register pairwise directly (e.g. one "
            "representative image per scan session), named by filename "
            "stem. --skip-before only applies to the single-4D-file case."
        ),
    )
    parser.add_argument(
        "output_dir",
        metavar="OUTPUT_DIR",
        help="Directory to write pairwise .mat files into (created if needed).",
    )
    parser.add_argument(
        "--skip-before",
        type=_skip_before_value,
        default=0,
        metavar="IDX",
        help=(
            "Ignore frames with index < IDX (zero-based), or 'auto' to "
            "estimate IDX from the data (requires --bids-json)."
        ),
    )
    parser.add_argument(
        "--bids-json",
        default=None,
        metavar="PATH",
        help=(
            "PET-BIDS sidecar JSON (with a FrameDuration array) for the "
            "single 4D input. Required when --skip-before auto is used."
        ),
    )
    parser.add_argument(
        "--bolus-threshold",
        type=float,
        default=25.0,
        metavar="X",
        help=(
            "Only with --skip-before auto: flag the onset frame where the "
            "mean-signal derivative exceeds X times the fixed end-of-scan "
            "baseline (a multiplier, not a percentage)."
        ),
    )
    parser.add_argument(
        "--bolus-window",
        type=int,
        default=4,
        metavar="N",
        help=(
            "Only with --skip-before auto: number of frames, taken from "
            "the end of the scan, used to compute the fixed baseline."
        ),
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=None,
        metavar="N",
        help=(
            "Number of parallel flirt jobs.  Defaults to min(pairs, cpu_count). "
            "Reduce if flirt's internal threading over-subscribes your CPUs."
        ),
    )
    parser.add_argument(
        "--pattern",
        default="{moving}_to_{fixed}.mat",
        metavar="TMPL",
        help="Output filename template; must contain {moving} and {fixed}.",
    )
    parser.add_argument(
        "--apply", action='store_true', help="Apply each pairwise transformation",
    )
    parser.add_argument(
        "--full-search",
        action="store_true",
        help=(
            "Run flirt without -nosearch/-usesqform, i.e. a full blind "
            "search instead of assuming the pair already shares a common "
            "sqform alignment. Needed when registering standalone images "
            "that don't come from the same scan session."
        ),
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print a line for each completed pair.",
    )
    parser.add_argument(
        "--fwhm",
        type=float,
        default=None,
        help="FWHM (mm) for smoothing frames prior to registration.",
    )
    return parser.parse_args()


def main():
    """Entry point."""
    args = parse_args()

    # Check that all inputs exist
    input_paths = [Path(p) for p in args.inputs]
    for p in input_paths:
        if not p.exists():
            print(f"ERROR: {p} not found.", file=sys.stderr)
            sys.exit(1)

    # --skip-before only applies to the single-4D-file case
    if len(input_paths) > 1 and args.skip_before != 0:
        print(
            "ERROR: --skip-before only applies to a single 4D input, not "
            "multiple standalone images.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Check output pattern
    if "{moving}" not in args.pattern or "{fixed}" not in args.pattern:
        print(
            "ERROR: --pattern must contain both {moving} and {fixed}.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Make sure output directory exists
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Record the arguments this run was invoked with. Named after the
    # input(s)' filename stem(s) -- unlike mat_resolve, there's no separate
    # "output" name argument here, just OUTPUT_DIR.
    stem = "_".join(_stem(p) for p in input_paths)
    with open(output_dir / f"{stem}_args.json", "w", encoding="utf-8") as f:
        json.dump({"script": _PROG, **vars(args)}, f, indent=2)

    # Resolve --skip-before auto into a concrete frame index
    skip_before = args.skip_before
    if skip_before == "auto":
        if not args.bids_json:
            print(
                "ERROR: --skip-before auto requires --bids-json (a PET-BIDS "
                "sidecar JSON with a FrameDuration array).",
                file=sys.stderr,
            )
            sys.exit(1)
        n_total = nib.load(str(input_paths[0])).shape[3]
        frame_durations = _read_frame_durations(args.bids_json, n_total)
        skip_before, diagnostics = _estimate_bolus_onset(
            input_paths[0],
            frame_durations,
            fwhm=args.fwhm,
            threshold=args.bolus_threshold,
            window=args.bolus_window,
        )
        _write_bolus_onset_outputs(diagnostics, output_dir)
        if diagnostics["fallback_used"]:
            print("Auto --skip-before: no bolus onset detected, using all frames.")
        else:
            print(f"Auto --skip-before: detected skip_before = {skip_before}.")

    # Split frames (or load standalone images)
    with tempfile.TemporaryDirectory() as tmpdir:
        if len(input_paths) == 1:
            frame_paths = _extract_frames(
                input_paths[0], tmpdir, skip_before, fwhm=args.fwhm
            )
        else:
            frame_paths = _load_images(input_paths, tmpdir, fwhm=args.fwhm)
        frame_names = sorted(frame_paths)
        n = len(frame_names)
        n_pairs = n * (n - 1)

        print(f"Submitting {n_pairs} ordered pairs ({n} frames).")
        max_workers = args.workers or min(n_pairs, os.cpu_count() or 1)
        futures = {}
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            for moving in frame_names:
                for fixed in frame_names:
                    if moving == fixed:
                        continue
                    f = executor.submit(
                        _run_flirt,
                        moving,
                        frame_paths[moving],
                        fixed,
                        frame_paths[fixed],
                        output_dir,
                        args.pattern,
                        apply=args.apply,
                        full_search=args.full_search,
                    )
                    futures[f] = (moving, fixed)

            # Check status of transforms
            n_ok = n_fail = 0
            for future in as_completed(futures):
                label, success, err = future.result()
                if success:
                    n_ok += 1
                    if args.verbose:
                        print(f"  OK   {label}")
                else:
                    n_fail += 1
                    print(f"  FAIL {label}: {err}", file=sys.stderr)

    print(f"\nDone: {n_ok}/{n_pairs} succeeded, {n_fail} failed.")
    if n_fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
