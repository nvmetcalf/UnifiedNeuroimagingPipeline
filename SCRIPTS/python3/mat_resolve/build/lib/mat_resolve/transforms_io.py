"""
transforms_io.py
=================
File I/O, discovery, and FSL ``flirt`` interaction for pairwise transform
files. Functions here raise ordinary exceptions on error (``NotADirectoryError``,
``FileNotFoundError``) rather than calling ``sys.exit``
"""
# pylint: disable=invalid-name
# Rationale: T is standard mathematical notation for a transform matrix.

import re
import subprocess
import sys
from pathlib import Path

import nibabel as nib
import numpy as np

from .nifti_frames import stack_frames_to_4d
from .rigid_math import decompose_rigid


def read_fsl_matrix(path):
    """
    Read a 4x4 FSL affine matrix from a plain-text ``.mat`` file.

    Parameters
    ----------
    path : str or Path
        Path to the FSL ``.mat`` file.

    Returns
    -------
    T : ndarray, shape (4, 4)
        The homogeneous transform matrix.

    Raises
    ------
    ValueError
        If the file cannot be parsed as a 4x4 matrix.
    """
    try:
        T = np.loadtxt(path)
    except Exception as exc:
        raise ValueError(f"Cannot read FSL matrix from {path}: {exc}") from exc
    if T.shape != (4, 4):
        raise ValueError(f"Expected 4x4 matrix in {path}, got shape {T.shape}")
    return T


def write_fsl_matrix(T, path):
    """
    Write a 4x4 FSL affine matrix to a plain-text ``.mat`` file.

    Parameters
    ----------
    T : ndarray, shape (4, 4)
        The homogeneous transform matrix.
    path : str or Path
        Destination file path.
    """
    np.savetxt(path, T, fmt="% .10f")


def _natural_sort_key(name):
    """
    Sort key that compares embedded digit runs numerically, so
    ``bold_2`` sorts before ``bold_10`` even though ``"2" > "1"`` as a
    raw string comparison would put them the other way for non-zero-padded
    names.
    """
    return [
        int(chunk) if chunk.isdigit() else chunk.lower()
        for chunk in re.split(r"(\d+)", name)
    ]


def pattern_to_regex(pattern):
    """
    Convert a filename pattern with ``{moving}`` and ``{fixed}`` placeholders
    to a compiled regular expression with named capture groups.

    Parameters
    ----------
    pattern : str
        Filename template, e.g. ``"{moving}_to_{fixed}.mat"``.

    Returns
    -------
    re.Pattern
        Compiled regex with named groups ``moving`` and ``fixed``.

    Notes
    -----
    The regex uses non-greedy matching for ``moving`` and greedy for ``fixed``
    so that the *first* occurrence of the separator string is used as the
    split point.  If image names contain the separator this may be ambiguous;
    the docstring of ``discover_transforms`` explains how this is handled.
    """
    # Escape everything except the placeholders, then substitute them
    escaped = re.escape(pattern)
    escaped = escaped.replace(r"\{moving\}", r"(?P<moving>.+?)")
    escaped = escaped.replace(r"\{fixed\}", r"(?P<fixed>.+)")
    return re.compile(f"^{escaped}$")


def discover_transforms(folder, pattern):
    """
    Scan a folder for pairwise FSL transform files and return all discovered
    transforms together with the inferred set of image names.

    Parameters
    ----------
    folder : str or Path
        Directory to scan.
    pattern : str
        Filename template containing ``{moving}`` and ``{fixed}``, e.g.
        ``"{moving}_to_{fixed}.mat"``.

    Returns
    -------
    transforms : dict
        Mapping ``(moving_name, fixed_name)`` -> ndarray shape (4, 4).
    image_names : list of str
        Sorted list of all unique image names found across all matched files.

    Raises
    ------
    NotADirectoryError
        If ``folder`` is not a directory.
    FileNotFoundError
        If no files match ``pattern``, or if any ordered pair is missing.

    Notes
    -----
    The pattern is converted to a regex with non-greedy ``{moving}`` matching,
    so the first occurrence of the literal separator text between the two
    placeholders is used as the boundary.  Image names that themselves contain
    the separator string may be ambiguous; rename them or choose a different
    ``pattern`` separator in that case.

    After discovery, a completeness check verifies that every ordered
    (moving, fixed) pair has a corresponding file; if not, all missing pairs
    are listed in the raised exception's message.
    """ 
    # pylint: disable=too-many-locals
    
    folder = Path(folder)
    if not folder.is_dir():
        raise NotADirectoryError(f"folder '{folder}' is not a directory.")

    regex = pattern_to_regex(pattern)
    transforms = {}
    all_names = set()

    for fpath in sorted(folder.iterdir()):
        m = regex.match(fpath.name)
        if m is None:
            continue
        moving = m.group("moving")
        fixed = m.group("fixed")
        T = read_fsl_matrix(fpath)
        transforms[(moving, fixed)] = T
        all_names.add(moving)
        all_names.add(fixed)

    if not transforms:
        raise FileNotFoundError(f"No files in '{folder}' match pattern '{pattern}'.")

    image_names = sorted(all_names, key=_natural_sort_key)
    n = len(image_names)

    # Verify completeness: every ordered pair must be present
    missing = []
    for moving_idx in range(n):
        for fixed_idx in range(n):
            if moving_idx == fixed_idx:
                continue
            key = (image_names[moving_idx], image_names[fixed_idx])
            if key not in transforms:
                missing.append(key)

    if missing:
        missing_names = [pattern.format(moving=m, fixed=f) for m, f in missing]
        raise FileNotFoundError(
            "Missing transform files for the following pairs: "
            + ", ".join(missing_names)
        )

    print(f"Discovered {n} images and {len(transforms)} pairwise transforms.")
    for name in image_names:
        print(f"  {name}")

    return transforms, image_names


def write_output(result, outroot, output_dir):
    """
    Write the resolved FSL matrices and a human-readable summary table.

    Parameters
    ----------
    result : resolve.ResolveResult
        The result of ``resolve.resolve()``. ``result.resolved`` is already
        in FSL's own convention so no conversion is needed
    outroot : str
        File root for output.  Matrices are written as
        ``<image>_to_<outroot>.mat``; summary as ``<outroot>_summary.txt``.
    output_dir : Path object
        Directory to write the matrices and summary table into.
    """
    # Write one FSL .mat file per image
    print(f"\nWriting resolved FSL matrices (reference frame: {result.image_names[0]}):")
    for name in result.image_names:
        out_path = output_dir / f"{name}_to_{outroot}.mat"
        write_fsl_matrix(result.resolved[name], out_path)
        print(f"  {out_path}")

    # Write summary table 
    summary_path = output_dir / f"{outroot}_summary.txt"
    lines = []
    lines.append(f"# mat_resolve summary  (VOI radius = {result.radius:.1f} mm)")
    lines.append(f"# Reference image: {result.image_names[0]}")
    lines.append(
        f"# {'Image':<30}  {'tx(mm)':>8}  {'ty(mm)':>8}  {'tz(mm)':>8}"
        f"  {'rx(deg)':>8}  {'ry(deg)':>8}  {'rz(deg)':>8}  {'rms(mm)':>8}"
    )

    for name in result.image_names:
        T = result.resolved[name]
        tx, ty, tz, rx, ry, rz = decompose_rigid(T)
        lines.append(
            f"  {name:<30}  {tx:>8.4f}  {ty:>8.4f}  {tz:>8.4f}"
            f"  {rx:>8.4f}  {ry:>8.4f}  {rz:>8.4f}  {result.per_frame_rms[name]:>8.4f}"
        )

    summary_text = "\n".join(lines) + "\n"
    summary_path.write_text(summary_text, encoding="utf-8")
    print(f"\nSummary table written to: {summary_path}")
    print(summary_text)


def apply_transforms(image_names, outroot, image_dir, image_ext, output_dir):
    """
    Resample every image into the resolved (common) space using FSL ``flirt``.

    For each image the previously written ``<name>_to_<outroot>.mat`` is passed
    to ``flirt -applyxfm``.  The reference (fixed) image is ``image_names[0]``.
    Output images are written as ``<name>_on_<outroot><ext>``.

    Parameters
    ----------
    image_names : list of str
        All N image names; ``image_names[0]`` is the reference.
    outroot : str
        Output file root, matching the root used in ``write_output``.
    image_dir : str or Path
        Directory containing the NIfTI images.
    image_ext : str
        File extension including the dot, e.g. ``".nii.gz"`` or ``".nii"``.
    output_dir : Path object
        Directory containing the resolved ``.mat`` files (written by
        ``write_output``) and where resampled images are written.

    Raises
    ------
    FileNotFoundError
        If the reference image (``image_names[0]``) is not found in
        ``image_dir``.
    """
    image_dir = Path(image_dir)
    ref_path = image_dir / f"{image_names[0]}{image_ext}"

    if not ref_path.exists():
        raise FileNotFoundError(f"Reference image not found: {ref_path}")

    print(f"\nApplying resolved transforms (reference: {image_names[0]}):")
    for name in image_names:
        in_path = image_dir / f"{name}{image_ext}"
        mat_path = output_dir / f"{name}_to_{outroot}.mat"
        out_path = output_dir / f"{name}_on_{outroot}{image_ext}"

        if not in_path.exists():
            print(f"  WARNING: image not found, skipping: {in_path}", file=sys.stderr)
            continue

        cmd = [
            "flirt",
            "-in", str(in_path),
            "-ref", str(ref_path),
            "-applyxfm",
            "-init", str(mat_path),
            "-out", str(out_path),
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(
                f"  ERROR: flirt failed for {name}:\n{result.stderr.strip()}",
                file=sys.stderr,
            )
        else:
            print(f"  {in_path} -> {out_path}")


def write_resolved_4d(frame_order, outroot, image_ext, output_dir):
    """
    Stack the per-frame resampled outputs written by ``apply_transforms``
    into a single resolved 4D NIfTI, in the original chronological frame
    order (as opposed to ``image_names``, which is reordered so the chosen
    reference comes first).

    Parameters
    ----------
    frame_order : list of str
        Frame names in chronological order (i.e. ``sorted()`` of the dict
        returned by ``extract_frames``).
    outroot : str
        Output file root, matching the root used in ``apply_transforms``.
    image_ext : str
        Extension used for the per-frame resampled outputs.
    output_dir : Path
        Directory containing the per-frame resampled outputs; destination
        for the combined 4D file.

    Returns
    -------
    out_path : Path or None
        The written 4D file's path, or None if reassembly was skipped.

    Notes
    -----
    If any per-frame output is missing (e.g. because ``flirt`` failed for
    that frame), reassembly is skipped with a warning rather than raising,
    since the individual failure was already reported by
    ``apply_transforms``. On success, the per-frame files are deleted once
    stacked -- the combined 4D file is the intended deliverable of
    ``--apply --input-4d``, and leaving both around is redundant.
    """
    frame_paths = [output_dir / f"{name}_on_{outroot}{image_ext}" for name in frame_order]
    missing = [p for p in frame_paths if not p.exists()]
    if missing:
        print(
            "WARNING: skipping 4D reassembly, missing resampled frame(s): "
            + ", ".join(str(p) for p in missing),
            file=sys.stderr,
        )
        return None

    img4d = stack_frames_to_4d(frame_paths)
    out_path = output_dir / f"{outroot}_resolved.nii.gz"
    nib.save(img4d, out_path)
    for p in frame_paths:
        p.unlink()
    print(f"\nResolved 4D image written to: {out_path}")
    return out_path
