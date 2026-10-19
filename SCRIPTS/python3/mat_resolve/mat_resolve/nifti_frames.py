"""
nifti_frames.py
================
Shared helpers for splitting a 4D NIfTI into individual 3D frames and for
reassembling frames back into a 4D NIfTI.

The frame-naming convention here (``{stem}_{index:0pad}``) is shared by
``pairwise_register.py`` (which extracts frames in order to register every
pair) and ``cli.py`` (which re-extracts frames in order to resample them with
the resolved transforms via ``--apply --input-4d``).  Keeping both call sites
on one implementation means the names line up automatically.
"""

import sys
from pathlib import Path
import nibabel as nib
import numpy as np
from scipy.ndimage import gaussian_filter


def stem(path):
    """Return the filename stem, stripping .nii.gz or .nii."""
    name = Path(path).name
    if name.endswith(".nii.gz"):
        return name[:-7]
    if name.endswith(".nii"):
        return name[:-4]
    return Path(path).stem


def extract_frames(input_4d, tmpdir, skip_before, fwhm=None):
    """
    Extract 3D volumes from a 4D NIfTI into *tmpdir* as individual .nii.gz files.

    Parameters
    ----------
    input_4d : str or Path
        Path to the 4D NIfTI file.
    tmpdir : str or Path
        Temporary directory to write extracted volumes into.
    skip_before : int
        Ignore frames with index < skip_before.
    fwhm : float
        Smooth frames by `fwhm` mm before splitting

    Returns
    -------
    frame_paths : dict
        Mapping from frame name (e.g. ``"bold_0003"``) to the extracted Path.
    """
    img = nib.load(str(input_4d))

    if img.ndim != 4:
        print(
            f"ERROR: {input_4d} is not a 4D NIfTI (shape {img.shape}).",
            file=sys.stderr,
        )
        sys.exit(1)

    n_total = img.shape[3]
    if skip_before < 0 or skip_before >= n_total:
        print(
            f"ERROR: --skip-before {skip_before} is out of range "
            f"for {n_total} frames (valid: 0 to {n_total - 1}).",
            file=sys.stderr,
        )
        sys.exit(1)

    indices = range(skip_before, n_total)
    frame_stem = stem(input_4d)
    pad = len(str(n_total - 1))

    print(
        f"Extracting {len(indices)} of {n_total} frames "
        f"(skipping first {skip_before})..."
    )

    sigma = None
    if fwhm is not None:
        vox_sizes = img.header.get_zooms()[:3]
        sigma = [fwhm / (2.355 * v) for v in vox_sizes]

    frame_paths = {}
    for idx in indices:
        vol = np.asarray(img.dataobj[..., idx])
        if sigma is not None:
            vol = gaussian_filter(vol, sigma=sigma).astype(vol.dtype)
        frame_img = nib.Nifti1Image(vol, img.affine)
        name = f"{frame_stem}_{idx:0{pad}d}"
        path = Path(tmpdir) / f"{name}.nii.gz"
        nib.save(frame_img, path)
        frame_paths[name] = path

    return frame_paths


def load_images(paths, tmpdir, fwhm=None):
    """
    Load one or more standalone 3D NIfTI images by path.

    Used for the "standalone images" input mode of ``pairwise_register``,
    where each path is already an independent volume (e.g. one
    representative image per scan session) rather than a frame extracted
    from a shared 4D series.

    Parameters
    ----------
    paths : sequence of str or Path
        Paths to 3D NIfTI files.
    tmpdir : str or Path
        Used only when ``fwhm`` smoothing is requested (smoothed copies are
        written there); unsmoothed images are referenced in place.
    fwhm : float, optional
        Smooth each image by `fwhm` mm before returning.

    Returns
    -------
    frame_paths : dict
        Mapping from name (filename stem) to Path.
    """
    frame_paths = {}
    for p in paths:
        p = Path(p)
        img = nib.load(str(p))

        if img.ndim != 3:
            print(
                f"ERROR: {p} is not a 3D NIfTI (shape {img.shape}).",
                file=sys.stderr,
            )
            sys.exit(1)

        name = stem(p)
        if name in frame_paths:
            print(
                f"ERROR: duplicate image name '{name}' from {p} and "
                f"{frame_paths[name]}; rename one of the files.",
                file=sys.stderr,
            )
            sys.exit(1)

        if fwhm is not None:
            vox_sizes = img.header.get_zooms()[:3]
            sigma = [fwhm / (2.355 * v) for v in vox_sizes]
            vol = np.asarray(img.dataobj)
            vol = gaussian_filter(vol, sigma=sigma).astype(vol.dtype)
            out_path = Path(tmpdir) / f"{name}.nii.gz"
            nib.save(nib.Nifti1Image(vol, img.affine), out_path)
            frame_paths[name] = out_path
        else:
            frame_paths[name] = p

    return frame_paths


def stack_frames_to_4d(frame_paths_in_order):
    """
    Stack a sequence of 3D NIfTI files into a single 4D NIfTI image.

    Parameters
    ----------
    frame_paths_in_order : sequence of str or Path
        Paths to 3D NIfTI files, in the desired 4th-dimension order (e.g.
        chronological frame order).

    Returns
    -------
    img4d : nibabel.Nifti1Image
        4D image built by stacking the 3D volumes along a new last axis,
        using the affine of the first frame.
    """
    volumes = []
    affine = None
    for p in frame_paths_in_order:
        img = nib.load(str(p))
        if affine is None:
            affine = img.affine
        volumes.append(np.asarray(img.dataobj))
    data4d = np.stack(volumes, axis=3)
    return nib.Nifti1Image(data4d, affine)
