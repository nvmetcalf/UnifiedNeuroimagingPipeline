#!/usr/bin/env python3
"""
mat_resolve.py
==============
Command-line tool: discovers pairwise FSL rigid-body registration matrices,
resolves them into a self-consistent set of transforms via
``resolve.resolve()``, and writes the result back out to disk (plus optional
resampling via FSL ``flirt``).

To resolve a set of transforms directly from Python — matrices already in
memory, no filesystem involved — use ``mat_resolve.resolve.resolve()``
directly instead of this CLI; see that module for the actual algorithm.

Usage
-----
    python mat_resolve.py ./transforms resolved \\
        [--pattern "{moving}_to_{fixed}.mat"] \\
        [--radius 50] \\
        [--apply] [--qc-report] [--fwhm 0] \\
        [--image-dir ./images | --input-4d bold.nii.gz --skip-before 2] \\
        [--image-ext .nii.gz] \\
        [--verbose]

``--apply`` and ``--qc-report`` are independent flags that both draw frames
from either a directory of pre-extracted per-frame images (``--image-dir``)
or directly from the original 4D file that was fed to
``mat_resolve_pairwise`` (``--input-4d``). The latter re-extracts frames
using the same naming convention as ``mat_resolve_pairwise`` (shared via
``nifti_frames.py``).

- ``--apply`` resamples every frame into the resolved space via FSL
  ``flirt`` (requires FSL on PATH) and, with ``--input-4d``, restacks the
  resampled frames into a single ``<OUTPUT>_resolved.nii.gz``, deleting the
  intermediate per-frame ``<frame>_on_<OUTPUT>.nii.gz`` files once they're
  stacked (with ``--image-dir`` instead there's no restacking, so those
  per-frame files are the deliverable and are kept). Frames dropped via
  ``--exclude`` or upstream ``--skip-before`` are resampled too, using their
  nearest surviving frame's resolved matrix, so the restacked output keeps
  the original frame count.
- ``--qc-report`` writes a self-contained, browser-viewable motion QC report
  with a frame slider and a framewise-displacement/drift plot. It does not
  require ``--apply`` or FSL: the "after" panels are produced by
  analytically resampling only the handful of orthogonal-view pixels
  needed, in-process (see ``qc_report.py``).
- ``--fwhm`` (default 0, i.e. no smoothing) Gaussian-smooths every frame
  before it's used by either ``--apply`` or ``--qc-report`` -- both draw
  from the same (optionally smoothed) source data, via
  ``nifti_frames.extract_frames``/``load_images``, which already implement
  this smoothing for ``mat_resolve_pairwise``.

The tool scans ``folder`` for files matching ``--pattern`` and automatically
discovers all image names from the filenames.

Algorithm summary
-----------------
1.  Discover transforms and image names from the folder and filename pattern.
2.  Report pre-optimisation symmetry errors (pairs, triples, and optionally
    quadruples via --symmetry-quadruples).
3.  Call ``resolve.resolve()`` to solve for the set of transforms that
    minimises the total squared discrepancy between every predicted pairwise
    transform and its observed FSL matrix.
4.  Write one output FSL ``.mat`` file per image plus a summary table.
5.  Optionally resample each image into the resolved space using ``flirt``
    (requires FSL to be installed on PATH), and/or write a motion QC report.

Output naming
-------------
- Resolved transform matrices: ``{frame}_to_{output}.mat``
- Resampled images (with ``--apply``): ``{frame}_on_{output}{ext}``
- Summary table: ``{output}_summary.txt``
- QC report (with ``--qc-report``): ``{output}_qc_report.html`` +
  ``{output}_qc/`` (per-frame orthogonal-view PNGs)

Ported from: t4_resolve.c, ft4_resolve.f (Avi Synder, Washington University)
"""
# pylint: disable=invalid-name
# Rationale: T, J, R are standard mathematical notation in this domain.

import argparse
import bisect
import json
import re
import sys
import tempfile
from pathlib import Path

from .nifti_frames import extract_frames, load_images
from .qc_report import generate_qc_report
from .resolve import resolve
from .symmetry import compute_symmetry_error
from .transforms_io import (
    _natural_sort_key,
    apply_transforms,
    discover_transforms,
    write_output,
    write_resolved_4d,
)


_PROG = "mat_resolve"
_TRAILING_DIGITS_RE = re.compile(r"(\d+)$")


def _trailing_index(name):
    """Return the int value of the trailing digit run in `name`, or None if it has none."""
    m = _TRAILING_DIGITS_RE.search(name)
    return int(m.group(1)) if m else None


def _reference_value(value):
    """
    argparse ``type`` for ``--reference``: int if `value` parses as one
    (preserving the existing trailing-numeric-suffix matching), otherwise
    the raw string, to be matched against a discovered image's full name.
    """
    try:
        return int(value)
    except ValueError:
        return value


def _match_by_index(image_names, value):
    """
    Return the single name in `image_names` whose trailing numeric suffix
    equals `value` (e.g. value=51 matches "bold_51").

    Raises
    ------
    LookupError
        If zero or more than one image matches.
    """
    matches = [name for name in image_names if _trailing_index(name) == value]
    if not matches:
        raise LookupError(f"no discovered image has a numeric suffix matching {value}")
    if len(matches) > 1:
        raise LookupError(
            f"{value} matches multiple discovered images (ambiguous): "
            + ", ".join(matches)
        )
    return matches[0]


def _prefix_and_pad(name):
    """
    Split `name` into (prefix, pad) where `pad` is the width of its trailing
    digit run, or None if `name` has no trailing digit run.
    """
    m = _TRAILING_DIGITS_RE.search(name)
    if m is None:
        return None
    return name[: m.start(1)], len(m.group(1))


def _skip_before_names(all_image_names, skip_before):
    """
    Reconstruct the names of frames with numeric suffix < `skip_before` that
    were dropped upstream by ``mat_resolve_pairwise --skip-before`` and so
    never appear in `all_image_names` (no pairwise .mat file references
    them, since they were never registered).

    Relies on every discovered image sharing one consistent
    ``{prefix}{index:0pad}`` naming convention (as produced by
    ``mat_resolve_pairwise``/``nifti_frames.extract_frames``). Returns []
    (with a warning) if that convention can't be inferred, or if
    `skip_before` <= 0.
    """
    if skip_before <= 0:
        return []
    infos = {_prefix_and_pad(name) for name in all_image_names}
    if len(infos) != 1 or None in infos:
        print(
            "WARNING: discovered images don't share a single consistent "
            "naming convention; skipping --skip-before link generation.",
            file=sys.stderr,
        )
        return []
    ((prefix, pad),) = infos
    return [f"{prefix}{idx:0{pad}d}" for idx in range(skip_before)]


def _nearest_valid_name(idx, sorted_valid):
    """
    Return the name from `sorted_valid` (list of (index, name) tuples
    sorted by index) whose index is nearest to `idx`. Ties favor the lower
    index.
    """
    pos = bisect.bisect_left(sorted_valid, (idx,))
    best_name, best_dist = None, None
    for cand in (pos - 1, pos):
        if 0 <= cand < len(sorted_valid):
            vidx, vname = sorted_valid[cand]
            dist = abs(vidx - idx)
            if best_dist is None or dist < best_dist:
                best_dist, best_name = dist, vname
    return best_name


def _nearest_valid_mapping(linked_names, valid_names):
    """
    For every name in `linked_names` (dropped via --exclude, or never
    discovered because of ``mat_resolve_pairwise --skip-before``), find
    whichever name in `valid_names` has the nearest trailing numeric index.

    Shared by ``_write_nearest_valid_links`` (which symlinks the linked
    frame's output ``.mat`` to its nearest valid frame's) and the QC report
    (which reuses that same neighbour's resolved transform so a linked
    frame's "after" panel matches what its symlinked ``.mat`` actually
    contains) -- so both agree on "nearest."

    Returns
    -------
    dict
        Mapping linked name -> nearest valid name. Omits any linked name
        with no trailing numeric suffix, or if no valid name has one either
        (nothing to map to).
    """
    sorted_valid = sorted(
        (idx, name)
        for name in valid_names
        for idx in [_trailing_index(name)]
        if idx is not None
    )
    if not sorted_valid:
        return {}
    mapping = {}
    for name in linked_names:
        idx = _trailing_index(name)
        if idx is not None:
            mapping[name] = _nearest_valid_name(idx, sorted_valid)
    return mapping


def _write_nearest_valid_links(linked_names, valid_names, outroot, output_dir):
    """
    For every frame name in `linked_names` (dropped via --exclude, or never
    discovered because of ``mat_resolve_pairwise --skip-before``), symlink
    its ``{name}_to_{outroot}.mat`` to the resolved matrix of whichever
    surviving image in `valid_names` has the nearest trailing numeric
    index -- so every original frame index ends up with an output
    transform, even if it wasn't part of the optimisation.
    """
    mapping = _nearest_valid_mapping(linked_names, valid_names)
    if not mapping:
        print(
            "WARNING: surviving images have no trailing numeric suffix; "
            "skipping nearest-valid-frame link generation.",
            file=sys.stderr,
        )
        return

    print(f"\nLinking {len(linked_names)} skipped/excluded frame(s) to nearest valid frame:")
    for name in sorted(linked_names, key=_natural_sort_key):
        nearest = mapping.get(name)
        if nearest is None:
            print(
                f"  WARNING: {name} has no trailing numeric suffix; cannot link.",
                file=sys.stderr,
            )
            continue
        link_path = output_dir / f"{name}_to_{outroot}.mat"
        target_name = f"{nearest}_to_{outroot}.mat"
        link_path.unlink(missing_ok=True)
        link_path.symlink_to(target_name)
        print(f"  {link_path.name} -> {target_name}")


def _expand_resolved_for_qc(result, linked_names):
    """
    Extend ``result.image_names``/``result.resolved`` with linked
    (--exclude'd or upstream --skip-before'd) frames, so the QC report can
    show every original frame -- even ones that weren't part of the
    optimisation -- by reusing whichever surviving frame's resolved
    transform they're nearest to (see ``_nearest_valid_mapping``; the same
    transform already symlinked to their own ``<frame>_to_<OUTPUT>.mat``).

    Returns
    -------
    image_names : list of str
    resolved : dict
    """
    mapping = _nearest_valid_mapping(linked_names, result.image_names)
    image_names = list(result.image_names)
    resolved = dict(result.resolved)
    for name, nearest in mapping.items():
        image_names.append(name)
        resolved[name] = result.resolved[nearest]
    return image_names, resolved


def parse_args():
    """
    Parse command-line arguments.

    Returns
    -------
    argparse.Namespace
        Parsed arguments.
    """
    parser = argparse.ArgumentParser(
        prog=_PROG,
        description=(
            "Average a set of pairwise FSL rigid-body registration matrices "
            "into a self-consistent set of transforms to a common resolved space."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    # -- Required positional arguments ----------------------------------------
    parser.add_argument(
        "folder",
        metavar="FOLDER",
        help="Directory containing the pairwise FSL .mat files.",
    )
    parser.add_argument(
        "output",
        metavar="OUTPUT",
        help=(
            "Output file root.  Resolved matrices are written as "
            "<image>_to_<OUTPUT>.mat; summary as <OUTPUT>_summary.txt."
        ),
    )
    # -- Optional arguments ---------------------------------------------------
    parser.add_argument(
        "--pattern",
        default="{moving}_to_{fixed}.mat",
        metavar="TMPL",
        help=(
            "Filename template for pairwise transforms.  Must contain "
            "{moving} and {fixed} placeholders."
        ),
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        metavar="DIR",
        help="Directory to write resolved matrices and summary into. Defaults to FOLDER.",
    )
    parser.add_argument(
        "--radius",
        type=float,
        default=50.0,
        metavar="MM",
        help=(
            "VOI RMS radius in mm.  Rotation residuals are scaled by 2*radius "
            "to make them commensurate with translation residuals in mm."
        ),
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help=(
            "After resolving, resample each image into the common space via FSL flirt "
            "(requires FSL on PATH, and --image-dir or --input-4d)."
        ),
    )
    parser.add_argument(
        "--qc-report",
        action="store_true",
        help=(
            "After resolving, write a self-contained HTML motion QC report with a frame "
            "slider and FD/drift plot. Needs --image-dir or --input-4d, but not --apply or FSL."
        ),
    )
    apply_source = parser.add_mutually_exclusive_group()
    apply_source.add_argument(
        "--image-dir",
        default=None,
        metavar="DIR",
        help=(
            "Directory of pre-extracted per-frame NIfTI images to resample, for --apply "
            "and/or --qc-report. Defaults to FOLDER."
        ),
    )
    apply_source.add_argument(
        "--input-4d",
        default=None,
        metavar="NIFTI",
        help=(
            "The original 4D NIfTI passed to mat_resolve_pairwise, for --apply and/or "
            "--qc-report; frames are re-extracted on the fly (--skip-before must match). "
            "With --apply, resampled frames are restacked into <OUTPUT>_resolved.nii.gz."
        ),
    )
    parser.add_argument(
        "--image-ext",
        default=".nii.gz",
        metavar="EXT",
        help="Image file extension, for --apply/--qc-report with --image-dir.",
    )
    parser.add_argument(
        "--fwhm",
        type=float,
        default=0.0,
        metavar="MM",
        help=(
            "Gaussian-smooth each frame by this FWHM (mm) before --apply/--qc-report use "
            "it. Default 0 (no smoothing)."
        ),
    )
    parser.add_argument(
        "--skip-before",
        type=int,
        default=0,
        metavar="IDX",
        help=(
            "Ignore frames with index < IDX when re-extracting from --input-4d; must "
            "match the value passed to mat_resolve_pairwise. Skipped frames still get a "
            "resolved <frame>_to_<OUTPUT>.mat (and, with --apply, get resampled) from "
            "their nearest surviving frame."
        ),
    )
    parser.add_argument(
        "--reference",
        type=_reference_value,
        default=None,
        metavar="NAME_OR_IDX",
        help=(
            "Reference image: its exact discovered name, or a numeric suffix matched "
            "against images' trailing digits (e.g. 51 matches '...51', wherever it sits "
            "in the list). Defaults to the first surviving image; use -1 for the last."
        ),
    )
    parser.add_argument(
        "--exclude",
        type=int,
        nargs="+",
        default=None,
        metavar="IDX",
        help=(
            "Numeric suffixes of images to drop from the resolve, matched against each "
            "name's trailing digits (e.g. --exclude 51 drops '...51'). Excluded frames "
            "still get a resolved <frame>_to_<OUTPUT>.mat (and, with --apply, get "
            "resampled) from their nearest surviving frame."
        ),
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print per-pair residual norms at each optimiser iteration.",
    )
    parser.add_argument(
        "--symmetry-quadruples",
        action="store_true",
        help=(
            "Also report the pre-optimisation symmetry error over ordered quadruples "
            "of images. O(N^4), so slow for large N; off by default."
        ),
    )
    return parser.parse_args()


def main():
    """
    Entry point: discover transforms, run symmetry diagnostics, resolve,
    and write output.
    """
    args = parse_args()

    # Validate pattern
    if "{moving}" not in args.pattern or "{fixed}" not in args.pattern:
        print(
            "ERROR: --pattern must contain both {moving} and {fixed}.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Discover pairwise transforms
    try:
        transforms, all_image_names = discover_transforms(args.folder, args.pattern)
    except (NotADirectoryError, FileNotFoundError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)

    n_total = len(all_image_names)
    if n_total < 2:
        print("ERROR: Need at least 2 images.", file=sys.stderr)
        sys.exit(1)

    # Apply --exclude: values match each image's trailing numeric suffix
    # (e.g. "bold_51" matches --exclude 51), not its position in the
    # discovered list -- this stays correct even when frames were skipped
    # upstream (e.g. mat_resolve_pairwise --skip-before).
    excluded_names = set()
    if args.exclude:
        for val in args.exclude:
            try:
                excluded_names.add(_match_by_index(all_image_names, val))
            except LookupError as exc:
                print(f"ERROR: --exclude {val}: {exc}", file=sys.stderr)
                sys.exit(1)
        print(f"Excluding {len(excluded_names)} image(s): {', '.join(sorted(excluded_names))}")

    # Frames skipped upstream via mat_resolve_pairwise --skip-before never
    # appear in all_image_names (no pairwise .mat files reference them), so
    # reconstruct their names from the naming convention shared by the
    # discovered images. Names that turn out to already be discovered are
    # dropped (--skip-before not matching what was actually used upstream).
    skip_before_names = set(_skip_before_names(all_image_names, args.skip_before)) - set(
        all_image_names
    )
    # Frames that will get a <frame>_to_<OUTPUT>.mat symlinked to their
    # nearest surviving frame's resolved matrix, instead of being resolved.
    linked_names = excluded_names | skip_before_names

    image_names = [name for name in all_image_names if name not in excluded_names]
    n = len(image_names)
    if n < 2:
        print("ERROR: Need at least 2 images after --exclude.", file=sys.stderr)
        sys.exit(1)

    # Resolve output directory
    output_dir = Path(args.output_dir) if args.output_dir is not None else Path(args.folder)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Record the arguments this run was invoked with
    with open(output_dir / f"{args.output}_args.json", "w", encoding="utf-8") as f:
        json.dump({"script": _PROG, **vars(args)}, f, indent=2)

    # Select reference image. An explicit --reference value is either an
    # exact discovered image name or an int, matched against an image's
    # trailing numeric suffix (not its list position). Special cases
    # (resolved against the post-exclusion list, so neither can ever land
    # on an excluded image): no --reference given -> first surviving image;
    # --reference -1 -> last surviving image.
    if args.reference is None:
        ref_name = image_names[0]
    elif args.reference == -1:
        ref_name = image_names[-1]
    elif isinstance(args.reference, str):
        if args.reference not in all_image_names:
            print(
                f"ERROR: --reference {args.reference!r}: no discovered image has that name.",
                file=sys.stderr,
            )
            sys.exit(1)
        ref_name = args.reference
    else:
        try:
            ref_name = _match_by_index(all_image_names, args.reference)
        except LookupError as exc:
            print(f"ERROR: --reference {args.reference}: {exc}", file=sys.stderr)
            sys.exit(1)

    if ref_name in excluded_names:
        print(
            f"ERROR: --reference {args.reference!r} ({ref_name}) was excluded "
            "via --exclude; choose a different reference.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Rotate image_names so the chosen reference is first; matches what
    # resolve() will do internally (passing reference=0 below is then a
    # no-op reorder on its end).
    image_names = [ref_name] + [name for name in image_names if name != ref_name]
    print(f"Reference image : {ref_name}")

    # Pre-optimisation symmetry diagnostics
    print("\n--- Pre-optimisation symmetry error ---")
    compute_symmetry_error(transforms, image_names, quadruples=args.symmetry_quadruples)

    # Resolve
    print(f"\n--- Gauss-Newton optimisation (VOI radius = {args.radius:.1f} mm) ---")
    print(f"Free parameters: {6 * (n - 1)}  ({n - 1} transforms x 6 DOF)")
    print(f"Observations   : {6 * n * (n - 1)}  ({n * (n - 1)} pairs x 6 residuals)")
    result = resolve(
        transforms,
        image_names,
        radius=args.radius,
        reference=0,
        verbose=args.verbose,
    )
    
    # Show user optimization results
    print(
        f"Initial RMS residual: {result.initial_rms:.6f} mm-equivalent  "
        "(direct k->0 seed, unoptimised)"
    )
    opt_result = result.opt_result
    if not opt_result.success and opt_result.cost > 1e-3:
        print(
            f"WARNING: optimiser did not fully converge "
            f"(status={opt_result.status}: {opt_result.message})",
            file=sys.stderr,
        )
    else:
        print(f"Converged: {opt_result.message}")
    print(f"Final RMS residual: {result.final_rms:.6f} mm-equivalent")


    # Save results
    write_output(result, args.output, output_dir)
    if linked_names:
        _write_nearest_valid_links(linked_names, image_names, args.output, output_dir)
    # --qc-report shows every original frame, including ones dropped via
    # --exclude or upstream --skip-before -- each borrows its nearest
    # surviving frame's resolved transform (same one already symlinked to
    # its own <frame>_to_<OUTPUT>.mat by _write_nearest_valid_links above).
    qc_image_names, qc_resolved = (
        _expand_resolved_for_qc(result, linked_names) if args.qc_report else (None, None)
    )
    # --apply resamples every original frame, not just the ones actually
    # resolved -- linked frames (--exclude'd or upstream --skip-before'd)
    # are resampled too, using the nearest-valid-frame .mat already
    # symlinked to their own <frame>_to_<OUTPUT>.mat by
    # _write_nearest_valid_links above, so the restacked 4D output keeps
    # the original frame count.
    apply_image_names = result.image_names + sorted(linked_names, key=_natural_sort_key)

    if args.apply or args.qc_report:
        # None (not 0.0) so extract_frames/load_images take their fast,
        # no-smoothing path -- default --fwhm 0 must be a true no-op.
        fwhm = args.fwhm if args.fwhm > 0 else None
        try:
            if args.input_4d is not None:
                # Always extract the full frame range, not just >=
                # --skip-before: --apply now resamples linked frames too
                # (see apply_image_names above), and --qc-report always
                # wanted the full range to display them.
                with tempfile.TemporaryDirectory() as tmpdir:
                    frame_paths = extract_frames(args.input_4d, tmpdir, 0, fwhm=fwhm)
                    missing = [name for name in result.image_names if name not in frame_paths]
                    if missing:
                        print(
                            "ERROR: --input-4d did not produce frames matching the "
                            "discovered image names (check --skip-before matches "
                            "the value used with mat_resolve_pairwise): "
                            + ", ".join(missing),
                            file=sys.stderr,
                        )
                        sys.exit(1)
                    if args.apply:
                        apply_transforms(
                            apply_image_names, args.output, tmpdir, ".nii.gz", output_dir
                        )
                    if args.qc_report:
                        # Rendered from `frame_paths` (still valid inside this
                        # `with` block) before the tempdir is cleaned up; the
                        # QC PNGs/HTML it writes go to the permanent
                        # output_dir, so nothing is lost once it's removed.
                        generate_qc_report(
                            qc_image_names, qc_resolved, frame_paths,
                            output_dir, args.output, radius=args.radius, linked_names=linked_names,
                        )
                    frame_order = sorted(frame_paths)
                if args.apply:
                    write_resolved_4d(frame_order, args.output, ".nii.gz", output_dir)
            else:
                image_dir = args.image_dir if args.image_dir is not None else args.folder
                if fwhm is None:
                    # Unchanged from before --fwhm existed: read straight out
                    # of image_dir, no smoothed copies, no tmpdir.
                    if args.apply:
                        apply_transforms(
                            apply_image_names, args.output, image_dir, args.image_ext, output_dir
                        )
                    if args.qc_report:
                        before_paths = {
                            name: Path(image_dir) / f"{name}{args.image_ext}"
                            for name in qc_image_names
                        }
                        generate_qc_report(
                            qc_image_names, qc_resolved, before_paths,
                            output_dir, args.output, radius=args.radius, linked_names=linked_names,
                        )
                else:
                    with tempfile.TemporaryDirectory() as tmpdir:
                        paths = [
                            Path(image_dir) / f"{name}{args.image_ext}"
                            for name in result.image_names
                        ]
                        # Smoothed copies (named "{name}.nii.gz") in tmpdir;
                        # apply_transforms and generate_qc_report both draw
                        # from this same smoothed source, so the resampled
                        # --apply output and the --qc-report panels agree.
                        before_paths = load_images(paths, tmpdir, fwhm=fwhm)
                        if args.apply:
                            # Smooth+resample linked (--exclude'd/--skip-
                            # before'd) frames too, but skip any whose image
                            # is missing from image_dir instead of failing
                            # the whole run -- load_images fails hard on any
                            # missing file, and these are optional restack
                            # extras, unlike the core registered frames.
                            linked_paths = [
                                Path(image_dir) / f"{name}{args.image_ext}"
                                for name in sorted(linked_names, key=_natural_sort_key)
                                if (Path(image_dir) / f"{name}{args.image_ext}").exists()
                            ]
                            if linked_paths:
                                before_paths.update(load_images(linked_paths, tmpdir, fwhm=fwhm))
                            apply_transforms(
                                apply_image_names, args.output, tmpdir, ".nii.gz", output_dir
                            )
                        if args.qc_report:
                            # Any linked frame whose image is missing from
                            # image_dir (or wasn't smoothed above because
                            # --apply wasn't requested) falls back to its
                            # raw, unsmoothed file for display only.
                            for name in qc_image_names:
                                before_paths.setdefault(
                                    name, Path(image_dir) / f"{name}{args.image_ext}"
                                )
                            generate_qc_report(
                                qc_image_names, qc_resolved, before_paths,
                                output_dir, args.output, radius=args.radius, linked_names=linked_names,
                            )
        except FileNotFoundError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
