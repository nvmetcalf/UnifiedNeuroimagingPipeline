"""
qc_report.py
============
Diagnostic-only (not used in optimization, like ``symmetry.py``): builds a
single self-contained, browser-viewable HTML motion-QC report with a frame
slider -- six orthogonal-view panels (before/after motion correction x
sagittal/coronal/axial) plus a framewise-displacement / displacement-from-
reference plot.

Does not depend on ``--apply`` or on FSL's ``flirt`` binary. The "after"
panels are produced by analytically resampling only the handful of 2D plane
points actually needed for display, using each frame's resolved transform
directly, instead of resampling a whole 3D volume through an external tool.

FSL "scaled voxel" coordinate convention
-----------------------------------------
Each frame's resolved transform is an FSL-convention matrix satisfying
``x_ref_fsl = resolved[name] @ x_name_fsl`` (see
``rigid_math.compose_rigid_with_jacobians`` and ``transforms_io.write_output``),
where ``x_fsl`` is FSL's own "scaled voxel" coordinate space -- not raw
voxel indices, not world/mm coordinates. For an image with voxel sizes
``(dx, dy, dz)`` and 0-indexed voxel ``(i, j, k)``::

    x_fsl = i*dx   (or (Nx-1-i)*dx if det(affine[:3,:3]) > 0)
    y_fsl = j*dy
    z_fsl = k*dz

i.e. plain voxel-size scaling, with an x-axis flip exactly when the image's
sform/qform has a positive determinant. ``voxel_to_fsl``/``fsl_to_voxel``
implement this; see ``tests/test_qc_report.py::test_analytic_resample_matches_flirt``
for an empirical cross-check against real ``flirt -applyxfm`` output.

IMPORTANT: this formula's "flip if det>0" check must be evaluated against
each image's own **native, on-disk** affine -- never a reoriented/canonical
one. Earlier code reoriented every volume to RAS+ (``nib.as_closest_canonical``)
before this step, for display convenience; that silently broke this formula
whenever canonicalization flipped an axis *other* than X (e.g. a header with
a negative Z-scale, which flips the overall determinant sign exactly like an
X-flip would, incorrectly triggering an X-flip on data that never needed
one). Confirmed empirically: analytic output diverged from real ``flirt``
output by up to ~220/255 on such data, vs. ~1e-3 when using the native
affine. Display reorientation is now handled separately, after the FSL math,
by :func:`_axis_orientation` + :func:`_orient_display` -- see those for the
fix.
"""

import json
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
from PIL import Image
from scipy.ndimage import center_of_mass, map_coordinates
from scipy.ndimage import zoom as ndi_zoom

from .rigid_math import decompose_rigid, rigid_inv
from .transforms_io import _natural_sort_key

_VIEWS = ("sag", "cor", "axi")

# Desired FSLeyes-style radiological display flip for each view's COLUMN axis
# (index 0=sag/R-fixed, 1=cor/A-fixed, 2=axi/S-fixed): superior/anterior
# always go to the top (row), independent of view; anterior goes to the
# right for sagittal (no extra column flip) while right(R) goes to the left
# for coronal/axial (radiological convention, extra column flip). See
# _orient_display's docstring for the full derivation. This is XORed against
# each axis's *native* direction (from _axis_orientation) so it's correct
# regardless of how the file happens to be stored on disk -- see the
# "IMPORTANT" note on _axis_orientation for why that native-direction step
# is not optional.
_COL_DESIRED_FLIP = (False, True, True)


def voxel_to_fsl(ijk, shape, zooms, affine):
    """
    Convert voxel index coordinates to FSL "scaled voxel" coordinates.

    Parameters
    ----------
    ijk : array_like, shape (3, ...)
        Voxel indices (i, j, k), any trailing shape (scalar or array).
    shape : tuple of int
        Image shape (Nx, Ny, Nz).
    zooms : tuple of float
        Voxel sizes (dx, dy, dz), mm.
    affine : array_like, shape (4, 4)
        Image affine (used only for the sign of its 3x3 determinant).

    Returns
    -------
    xyz : ndarray, shape (3, ...)
        FSL scaled-voxel coordinates.
    """
    ijk = np.asarray(ijk, dtype=float)
    i, j, k = ijk[0], ijk[1], ijk[2]
    dx, dy, dz = zooms
    if np.linalg.det(np.asarray(affine)[:3, :3]) > 0:
        i = (shape[0] - 1) - i
    return np.stack([i * dx, j * dy, k * dz], axis=0)


def fsl_to_voxel(xyz, shape, zooms, affine):
    """
    Inverse of :func:`voxel_to_fsl`: FSL "scaled voxel" coordinates back to
    voxel index coordinates.

    Parameters
    ----------
    xyz : array_like, shape (3, ...)
        FSL scaled-voxel coordinates.
    shape : tuple of int
        Image shape (Nx, Ny, Nz).
    zooms : tuple of float
        Voxel sizes (dx, dy, dz), mm.
    affine : array_like, shape (4, 4)
        Image affine (used only for the sign of its 3x3 determinant).

    Returns
    -------
    ijk : ndarray, shape (3, ...)
        Voxel index coordinates (not rounded; suitable for interpolation).
    """
    xyz = np.asarray(xyz, dtype=float)
    x, y, z = xyz[0], xyz[1], xyz[2]
    dx, dy, dz = zooms
    i, j, k = x / dx, y / dy, z / dz
    if np.linalg.det(np.asarray(affine)[:3, :3]) > 0:
        i = (shape[0] - 1) - i
    return np.stack([i, j, k], axis=0)


def load_image(path):
    """
    Load a NIfTI image's native, on-disk array/shape/zooms/affine -- no
    reorientation. See the module docstring's "IMPORTANT" note: the FSL
    scaled-voxel math in :func:`voxel_to_fsl`/:func:`fsl_to_voxel` is only
    correct against each image's own native affine, never a
    canonicalized/reoriented one.

    Parameters
    ----------
    path : str or Path

    Returns
    -------
    vol : ndarray, shape (Nx, Ny, Nz)
    shape : tuple of int
    zooms : tuple of float, mm
    affine : ndarray, shape (4, 4)
    """
    img = nib.load(str(path))
    vol = np.asarray(img.dataobj, dtype=float)
    return vol, img.shape, img.header.get_zooms()[:3], img.affine


def _axis_orientation(affine):
    """
    For an image's own native affine, determine which array axis is closest
    to each of Right/Anterior/Superior, and whether that axis's native
    direction needs reversing to point toward positive R/A/S.

    This is purely a *display* concern (which array axis to fix for each of
    sag/cor/axi, and which way is "up"/"right" on screen) -- kept entirely
    separate from the FSL scaled-voxel coordinate math, which must never be
    evaluated against a reoriented affine (see the module docstring).

    Returns
    -------
    array_axis_for_ras : tuple of int, length 3
        array_axis_for_ras[0] is the array axis closest to R (i.e. the axis
        to fix for a sagittal slice); [1] for A (coronal); [2] for S (axial).
    ras_of_array_axis : list of (int, bool), length 3
        Inverse mapping, indexed by array axis: (ras_index, native_flip) --
        native_flip is True if that array axis's index increases in the
        *negative* R/A/S direction (so needs reversing to read as positive).
    """
    ornt = nib.io_orientation(np.asarray(affine))
    array_axis_for_ras = tuple(int(ornt[k, 0]) for k in range(3))
    ras_of_array_axis = [None, None, None]
    for ras_idx in range(3):
        array_axis = array_axis_for_ras[ras_idx]
        ras_of_array_axis[array_axis] = (ras_idx, bool(ornt[ras_idx, 1] < 0))
    return array_axis_for_ras, ras_of_array_axis


def _view_axes(fixed_axis):
    """The two non-fixed axes for a view, in the order the raw 2D plane is built."""
    return [ax for ax in range(3) if ax != fixed_axis]


def _orient_display(plane_2d, row_array_axis, col_array_axis, ras_of_array_axis, view):
    """
    Reorient a raw 2D plane (row=`row_array_axis`, col=`col_array_axis`,
    both voxel-index-increasing, i.e. not yet transposed) into FSLeyes'
    default screen convention: superior-at-top for sag/cor, anterior-at-top
    for axi, anterior-at-right for sag, and right-at-left (radiological) for
    cor/axi -- regardless of how the source file's axes/directions are
    actually stored on disk.

    Derivation: transpose always swaps row/col so the plane's slower-varying
    screen axis is S (sag/cor) or A (axi). Two flips then compose: (1) each
    axis's own native direction (`ras_of_array_axis`, from
    :func:`_axis_orientation`) is normalized to positive R/A/S first; (2)
    the FSLeyes display convention is applied on top of that -- row always
    flips (positive S/A end goes to the top), column flips only for
    cor/axi's R axis (see ``_COL_DESIRED_FLIP``). The two flips are XORed
    (via ``!=``) since flipping twice cancels.
    """
    row_native_flip = ras_of_array_axis[row_array_axis][1]
    col_native_flip = ras_of_array_axis[col_array_axis][1]
    oriented = plane_2d.T
    if not row_native_flip:  # native_flip XOR desired(=True)
        oriented = np.flipud(oriented)
    if col_native_flip != _COL_DESIRED_FLIP[view]:
        oriented = np.fliplr(oriented)
    return oriented


def _isotropic_zoom(oriented_2d, row_spacing, col_spacing):
    """
    Resample `oriented_2d` so its pixels represent equal physical mm in both
    directions (upsampling the coarser axis to the finer axis' spacing) --
    without this, a plane built from anisotropic voxels (e.g. thicker
    through-plane slices) renders squashed/stretched relative to its true
    proportions, since a PNG has no notion of physical pixel size on its own
    (unlike e.g. matplotlib's ``extent``).
    """
    target = min(row_spacing, col_spacing)
    zoom_row, zoom_col = row_spacing / target, col_spacing / target
    if np.isclose(zoom_row, 1.0) and np.isclose(zoom_col, 1.0):
        return oriented_2d
    return ndi_zoom(oriented_2d, (zoom_row, zoom_col), order=1)


def voxel_to_display_pixel(ijk, shape, zooms, affine, view):
    """
    Map voxel-index point(s) to the same 2D display-pixel coordinates that
    :func:`native_orthoslices`/:func:`resampled_orthoslices` place image
    content at, for a given view -- so external point data (e.g. a surface
    mesh's vertices, already converted from world mm to this image's
    voxel-index space) can be overlaid in exact pixel alignment with those
    functions' PNGs.

    Applies the identical axis-selection / transpose / flip / isotropic-zoom
    steps as :func:`_orient_display` + :func:`_isotropic_zoom`, just for
    point coordinates instead of a dense array -- see those functions' (and
    the module's "IMPORTANT" docstring note) for why this orientation math
    is not optional to get exactly right.

    Parameters
    ----------
    ijk : array_like, shape (3, ...)
        Voxel-index coordinates (not necessarily integer), any trailing
        shape (scalar or array).
    shape : tuple of int
        Image shape (Nx, Ny, Nz).
    zooms : tuple of float
        Voxel sizes (dx, dy, dz), mm.
    affine : array_like, shape (4, 4)
        The image's own native affine (determines display orientation via
        :func:`_axis_orientation`, same as :func:`native_orthoslices`).
    view : int
        0 = sag, 1 = cor, 2 = axi (matches the order native_orthoslices
        returns its three planes in).

    Returns
    -------
    rc : ndarray, shape (2, ...)
        (row, col) display-pixel coordinates, float (not rounded), aligned
        with the PNG written from `native_orthoslices`'s output for the same
        `shape`/`zooms`/`affine`/`view`.
    """
    ijk = np.asarray(ijk, dtype=float)
    array_axis_for_ras, ras_of_array_axis = _axis_orientation(affine)
    fixed_axis = array_axis_for_ras[view]
    axes = _view_axes(fixed_axis)
    row_axis, col_axis = axes[1], axes[0]

    row = ijk[row_axis]
    col = ijk[col_axis]
    if not ras_of_array_axis[row_axis][1]:
        row = (shape[row_axis] - 1) - row
    if ras_of_array_axis[col_axis][1] != _COL_DESIRED_FLIP[view]:
        col = (shape[col_axis] - 1) - col

    target = min(zooms[row_axis], zooms[col_axis])
    row = row * (zooms[row_axis] / target)
    col = col * (zooms[col_axis] / target)
    return np.stack([row, col], axis=0)


def fixed_axis_for_view(affine, view):
    """
    The array axis held fixed for `view` (0=sag, 1=cor, 2=axi) when slicing
    via :func:`native_orthoslices` -- i.e. which voxel-index coordinate a
    threshold/plane must be defined against to intersect external geometry
    (e.g. a surface mesh) with that same slice. Pairs with
    :func:`voxel_to_display_pixel` for placing external point data in exact
    alignment with this module's rendered slices.

    Parameters
    ----------
    affine : array_like, shape (4, 4)
        The image's own native affine.
    view : int
        0 = sag, 1 = cor, 2 = axi.

    Returns
    -------
    int
        The array axis (0, 1, or 2) held fixed for this view.
    """
    array_axis_for_ras, _ = _axis_orientation(affine)
    return array_axis_for_ras[view]


def native_orthoslices(vol, zooms, affine, slice_idx):
    """
    Extract sagittal/coronal/axial mid-slices directly from a volume's own
    native array -- no transform math, for the "before" panels.

    Parameters
    ----------
    vol : ndarray, shape (Nx, Ny, Nz)
        The volume's own native (unreoriented) array (see :func:`load_image`).
    zooms : tuple of float
        Voxel sizes (dx, dy, dz), mm.
    affine : ndarray, shape (4, 4)
        The volume's own native affine -- used only to determine display
        orientation (:func:`_axis_orientation`), never for the FSL math.
    slice_idx : tuple of int
        Voxel indices to slice at, one per array axis (not per view).

    Returns
    -------
    sag, cor, axi : ndarray
        Display-oriented 2D slices (FSLeyes-style screen convention, with
        physically isotropic pixels -- see :func:`_orient_display` and
        :func:`_isotropic_zoom`).
    """
    array_axis_for_ras, ras_of_array_axis = _axis_orientation(affine)
    planes = []
    for view in range(3):
        fixed_axis = array_axis_for_ras[view]
        index = [slice(None)] * 3
        index[fixed_axis] = slice_idx[fixed_axis]
        raw = vol[tuple(index)]
        axes = _view_axes(fixed_axis)
        row_axis, col_axis = axes[1], axes[0]
        oriented = _orient_display(raw, row_axis, col_axis, ras_of_array_axis, view)
        row_spacing, col_spacing = zooms[row_axis], zooms[col_axis]
        planes.append(_isotropic_zoom(oriented, row_spacing, col_spacing))
    return tuple(planes)


def _plane_grid(shape, fixed_axis, fixed_idx):
    """Voxel-index grid, shape (3, A, B), for the plane orthogonal to `fixed_axis`."""
    axes = _view_axes(fixed_axis)
    dim_a, dim_b = shape[axes[0]], shape[axes[1]]
    grid_a, grid_b = np.meshgrid(np.arange(dim_a), np.arange(dim_b), indexing="ij")
    ijk = np.empty((3, dim_a, dim_b))
    ijk[axes[0]] = grid_a
    ijk[axes[1]] = grid_b
    ijk[fixed_axis] = fixed_idx
    return ijk


def resampled_orthoslices(
    name_vol,
    name_shape,
    name_zooms,
    name_affine,
    resolved_T,
    ref_shape,
    ref_zooms,
    ref_affine,
    slice_idx,
):
    """
    Analytically resample the three orthogonal planes (defined in the
    reference frame's voxel grid) out of `name_vol`, for the "after" panels
    -- without ever materializing a full resampled 3D volume.

    Parameters
    ----------
    name_vol : ndarray, shape (Nx, Ny, Nz)
        The frame's own native (unreoriented) volume (see :func:`load_image`).
    name_shape, name_zooms, name_affine
        The frame's own native shape / voxel sizes / affine.
    resolved_T : ndarray, shape (4, 4)
        ``result.resolved[name]``, satisfying x_ref_fsl = resolved_T @ x_name_fsl.
    ref_shape, ref_zooms, ref_affine
        The reference frame's own native shape / voxel sizes / affine
        (defines the common display grid; `ref_affine` also determines
        display orientation via :func:`_axis_orientation`, matching
        :func:`native_orthoslices` exactly for a fair before/after comparison).
    slice_idx : tuple of int
        Voxel indices, in the *reference* grid, one per array axis (not per
        view).

    Returns
    -------
    sag, cor, axi : ndarray
        Display-oriented 2D slices, same orientation/isotropic-pixel
        convention as :func:`native_orthoslices`.
    """
    array_axis_for_ras, ras_of_array_axis = _axis_orientation(ref_affine)
    T_inv = rigid_inv(resolved_T)
    planes = []
    for view in range(3):
        fixed_axis = array_axis_for_ras[view]
        idx = slice_idx[fixed_axis]
        ijk_ref = _plane_grid(ref_shape, fixed_axis, idx)
        xyz_ref = voxel_to_fsl(ijk_ref, ref_shape, ref_zooms, ref_affine)
        xyz_ref_h = np.concatenate([xyz_ref, np.ones((1,) + xyz_ref.shape[1:])], axis=0)
        xyz_name_h = np.einsum("ij,jab->iab", T_inv, xyz_ref_h)
        ijk_name = fsl_to_voxel(xyz_name_h[:3], name_shape, name_zooms, name_affine)
        sample = map_coordinates(name_vol, ijk_name, order=1, mode="constant", cval=0.0)
        axes = _view_axes(fixed_axis)
        row_axis, col_axis = axes[1], axes[0]
        oriented = _orient_display(sample, row_axis, col_axis, ras_of_array_axis, view)
        row_spacing, col_spacing = ref_zooms[row_axis], ref_zooms[col_axis]
        planes.append(_isotropic_zoom(oriented, row_spacing, col_spacing))
    return tuple(planes)


def _content_centroid_ijk(vol):
    """
    Intensity-weighted centroid (i, j, k) of `vol`, in its own native
    voxel-index space -- used by :func:`_robust_slice_idx` to pick a QC
    display slice that actually intersects each frame's content, instead of
    blindly using the reference image's geometric mid-slice (which can miss
    a frame's anatomy entirely once that frame's content isn't centered in
    its own FOV, or has drifted far via motion).

    Falls back to the geometric center if `vol` sums to <= 0 (all-zero/
    negative), since ``scipy.ndimage.center_of_mass`` is undefined there.
    """
    total = vol.sum()
    if not np.isfinite(total) or total <= 0:
        return tuple((s - 1) / 2.0 for s in vol.shape)
    return tuple(float(c) for c in center_of_mass(vol))


def _content_bbox_native_ijk(vol):
    """
    Axis-aligned bounding box (min, max voxel index per axis, inclusive) of
    `vol`'s nonzero content, in its own native voxel-index space.

    Uses the same "nonzero == content" convention as :func:`normalize_pair`.
    Computed via a per-axis ``any``-reduction (not ``np.argwhere``) so it
    stays cheap on full-resolution volumes.

    Returns
    -------
    bbox : list of (int, int), length 3, or None
        None if `vol` has no nonzero voxels at all.
    """
    mask = vol != 0
    if not mask.any():
        return None
    bbox = []
    for ax in range(3):
        other_axes = tuple(a for a in range(3) if a != ax)
        nonzero_line = np.flatnonzero(np.any(mask, axis=other_axes))
        bbox.append((int(nonzero_line[0]), int(nonzero_line[-1])))
    return bbox


_CORNER_COMBOS = [(c0, c1, c2) for c0 in (0, 1) for c1 in (0, 1) for c2 in (0, 1)]


def _content_bbox_ref_ijk(bbox_native, shape, zooms, affine, resolved_T, ref_shape, ref_zooms, ref_affine):
    """
    Map a frame's own native content bbox (from
    :func:`_content_bbox_native_ijk`) into the reference grid's voxel-index
    space, for :func:`_robust_slice_idx`'s "every frame has data" bound.

    Transforms all 8 corners of the native bbox (not just its two extreme
    corners) and takes their axis-aligned min/max in ref space, since a
    rotation can make any of the 8 corners the extreme point along a given
    ref axis. The result is a conservative (possibly loose, never tight)
    superset of the frame's true content extent in ref space -- exact only
    up to that corner-based approximation, same convention as
    :func:`_own_slice_idx`/:func:`resampled_orthoslices` (``resolved_T``
    satisfies x_ref_fsl = resolved_T @ x_name_fsl).
    """
    corners_own = np.asarray(
        [[bbox_native[ax][c] for ax, c in zip(range(3), combo)] for combo in _CORNER_COMBOS],
        dtype=float,
    ).T  # shape (3, 8)
    xyz_own = voxel_to_fsl(corners_own, shape, zooms, affine)
    xyz_own_h = np.concatenate([xyz_own, np.ones((1, 8))], axis=0)
    xyz_ref_h = resolved_T @ xyz_own_h
    ijk_ref = fsl_to_voxel(xyz_ref_h[:3], ref_shape, ref_zooms, ref_affine)
    return [(float(ijk_ref[ax].min()), float(ijk_ref[ax].max())) for ax in range(3)]


def _robust_slice_idx(centroids_ref_ijk, ref_shape, shared_bounds=None):
    """
    Combine every frame's content centroid (each already expressed in the
    reference's voxel grid -- see caller) into a single shared slice_idx,
    per array axis, for the QC display grid.

    Uses the per-axis MEDIAN across frames, not the mean or just the
    reference's own centroid: a plain geometric mid-slice of the reference
    (the previous behavior) can land on a slice showing real anatomy for the
    reference but falling outside a moving frame's actual FOV -- especially
    once a reference/frame pair barely overlaps in field of view, which is
    exactly when a robust shared slice matters most. The median tracks
    where most frames actually have content while staying insensitive to
    one or two outlier frames dragging the shared slice away from the rest.

    Parameters
    ----------
    shared_bounds : list of (int, int) or None, length 3, optional
        Per-axis (min, max) index range, in the reference grid, within
        which *every* frame has nonzero content (see caller, built from
        :func:`_content_bbox_ref_ijk`) -- the median is clipped into this
        range, per axis, instead of just ``[0, ref_shape[ax] - 1]``, so the
        chosen slice isn't just typical of most frames but guaranteed (up
        to the bbox approximation) to intersect every frame's content. Pass
        None, or leave any individual axis' entry as None, to fall back to
        the unrestricted ``[0, ref_shape[ax] - 1]`` bound for that axis --
        used when no shared range exists (frames don't all overlap along
        that axis) so a slice can still be picked instead of raising.
    """
    med = np.median(np.asarray(centroids_ref_ijk), axis=0)
    slice_idx = []
    for ax in range(3):
        lo, hi = 0, ref_shape[ax] - 1
        if shared_bounds is not None and shared_bounds[ax] is not None:
            lo = max(lo, int(np.ceil(shared_bounds[ax][0])))
            hi = min(hi, int(np.floor(shared_bounds[ax][1])))
            if lo > hi:  # no shared integer index on this axis; fall back
                lo, hi = 0, ref_shape[ax] - 1
        slice_idx.append(int(np.clip(round(med[ax]), lo, hi)))
    return tuple(slice_idx)


def _own_slice_idx(slice_idx, ref_shape, ref_zooms, ref_affine, resolved_T, shape, zooms, affine):
    """
    Map the shared `slice_idx` (defined in the *reference* frame's voxel
    grid, from :func:`_robust_slice_idx`) into a frame's own native voxel
    grid, for :func:`native_orthoslices`'s "before" panels.

    `slice_idx` is only guaranteed to be in-bounds for `ref_shape` -- a
    frame's own native volume can have different dimensions (e.g. a
    differently-cropped/resampled modality), so reusing it directly as an
    index into that frame's own array can be out of bounds (see the
    resampled_orthoslices docstring for the resolved_T convention this
    mirrors, just inverted and rounded/clipped for discrete array indexing
    instead of interpolation).
    """
    xyz_ref = voxel_to_fsl(np.asarray(slice_idx, dtype=float), ref_shape, ref_zooms, ref_affine)
    xyz_ref_h = np.concatenate([xyz_ref, [1.0]])
    xyz_name_h = rigid_inv(resolved_T) @ xyz_ref_h
    ijk_name = fsl_to_voxel(xyz_name_h[:3], shape, zooms, affine)
    return tuple(int(np.clip(round(ijk_name[ax]), 0, shape[ax] - 1)) for ax in range(3))


def normalize_pair(before_2d, after_2d, eps=1e-6):
    """
    Normalize a before/after slice pair to uint8 using a SHARED percentile
    window (1st/99th percentile of their pooled nonzero pixels).

    Sharing the window between before and after -- rather than normalizing
    each independently -- matters: a *correctly* resampled frame would
    otherwise look artificially different in brightness after interpolation
    purely from independent windowing, defeating the before/after visual
    comparison.

    Parameters
    ----------
    before_2d, after_2d : ndarray
        2D slices, same shape.
    eps : float
        Minimum window width, guards the degenerate near-empty-slice case.

    Returns
    -------
    before_u8, after_u8 : ndarray, dtype uint8
    """
    pooled = np.concatenate([before_2d.ravel(), after_2d.ravel()])
    nonzero = pooled[pooled != 0]
    sample = nonzero if nonzero.size > 0 else pooled
    p1, p99 = np.percentile(sample, [1, 99])
    denom = max(p99 - p1, eps)

    def _to_uint8(arr):
        scaled = np.clip((arr - p1) / denom, 0.0, 1.0)
        return (scaled * 255).astype(np.uint8)

    return _to_uint8(before_2d), _to_uint8(after_2d)


def write_slice_png(arr_uint8, path):
    """Write a 2D uint8 array as a grayscale PNG."""
    Image.fromarray(arr_uint8, mode="L").save(path)


def compute_motion_series(resolved, frame_order, radius):
    """
    Compute per-frame framewise displacement (FD) and displacement-from-
    reference (drift), in chronological order.

    Both convert rotation (radians) to an arc-length in mm via the plain
    geometric ``radius * angle_rad`` model -- NOT the optimizer's internal
    ``2*radius`` quaternion-tangent-space scaling in ``resolve.py``, which
    is an unrelated use of the same constant.

    Parameters
    ----------
    resolved : dict
        Mapping image name -> 4x4 resolved transform (``result.resolved``,
        or an expansion of it -- e.g. linked --exclude'd/--skip-before'd
        frames borrowing their nearest surviving frame's transform, see
        ``cli._expand_resolved_for_qc``).
    frame_order : list of str
        Chronological (natural-sorted) order of image names to compute the
        series over; must all be keys of `resolved`.
    radius : float
        VOI radius, mm.

    Returns
    -------
    dict with keys "fd" and "drift", each a list of float, aligned to
    `frame_order`. ``fd[0] == 0.0`` (no previous frame to difference against).
    """

    def _mm_equivalent(tx, ty, tz, rx, ry, rz):
        return (
            abs(tx)
            + abs(ty)
            + abs(tz)
            + radius * (abs(np.radians(rx)) + abs(np.radians(ry)) + abs(np.radians(rz)))
        )

    drift = [_mm_equivalent(*decompose_rigid(resolved[name])) for name in frame_order]

    fd = [0.0]
    for k in range(1, len(frame_order)):
        rel = resolved[frame_order[k]] @ rigid_inv(resolved[frame_order[k - 1]])
        fd.append(_mm_equivalent(*decompose_rigid(rel)))

    return {"fd": fd, "drift": drift}


def _build_motion_plot_svg(fd, drift, linked):
    """
    Build the inline SVG markup for the FD/drift dual-line plot, plus the
    list of x pixel positions (one per frame, aligned to `fd`/`drift`) that
    the report's JS uses to move the frame marker and to hit-test clicks.

    Parameters
    ----------
    fd, drift : list of float
    linked : list of bool
        Aligned to `fd`/`drift`: True for a frame that wasn't independently
        resolved (--exclude'd or upstream --skip-before'd) and is instead
        showing its nearest surviving frame's borrowed transform -- not a
        real motion estimate for that frame. Rendered as dashed line
        segments (any segment touching a linked point) and hollow point
        markers, so it reads as "approximated," not real data.

    Returns
    -------
    svg : str
    x_positions : list of float
    width, height : int
    """
    width, height = 880, 220
    margin_left, margin_right, margin_top, margin_bottom = 48, 16, 16, 32
    plot_w = width - margin_left - margin_right
    plot_h = height - margin_top - margin_bottom

    n = len(fd)
    if n > 1:
        x_positions = [margin_left + k * (plot_w / (n - 1)) for k in range(n)]
    else:
        x_positions = [margin_left + plot_w / 2.0]

    y_max = max(max(fd, default=0.0), max(drift, default=0.0))
    y_max = y_max * 1.1 if y_max > 0 else 1.0

    def y_of(v):
        return margin_top + plot_h - (v / y_max) * plot_h

    def line_layer(series, color):
        parts = []
        for k in range(n - 1):
            x1, y1v = x_positions[k], y_of(series[k])
            x2, y2v = x_positions[k + 1], y_of(series[k + 1])
            dash = ' stroke-dasharray="5,4"' if (linked[k] or linked[k + 1]) else ""
            parts.append(
                f'<line x1="{x1:.2f}" y1="{y1v:.2f}" x2="{x2:.2f}" y2="{y2v:.2f}" '
                f'stroke="{color}" stroke-width="1.75"{dash}/>'
            )
        for k in range(n):
            x, y = x_positions[k], y_of(series[k])
            fill = "var(--panel-bg)" if linked[k] else color
            parts.append(
                f'<circle cx="{x:.2f}" cy="{y:.2f}" r="3" fill="{fill}" '
                f'stroke="{color}" stroke-width="1.5"/>'
            )
        return "\n  ".join(parts)

    y0, ymid, y1 = y_of(0.0), y_of(y_max / 2.0), y_of(y_max)
    any_linked = any(linked)
    legend_extra = (
        f"""
    <line x1="{width - 190}" y1="{margin_top + 37}" x2="{width - 180}" y2="{margin_top + 37}"
          stroke="var(--fg)" stroke-width="1.75" stroke-dasharray="5,4"/>
    <text x="{width - 176}" y="{margin_top + 41}">Excluded/skipped (nearest frame's transform)</text>
"""
        if any_linked
        else ""
    )
    svg = f"""
<svg id="motion-plot" viewBox="0 0 {width} {height}" preserveAspectRatio="none"
     style="width:100%;height:auto;background:var(--panel-bg);cursor:pointer;">
  <line x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{margin_top + plot_h}"
        stroke="var(--axis)" stroke-width="1"/>
  <line x1="{margin_left}" y1="{margin_top + plot_h}" x2="{margin_left + plot_w}" y2="{margin_top + plot_h}"
        stroke="var(--axis)" stroke-width="1"/>
  <text x="{margin_left - 6}" y="{y0 + 4}" text-anchor="end" font-size="11" fill="var(--fg)">0</text>
  <text x="{margin_left - 6}" y="{ymid + 4}" text-anchor="end" font-size="11" fill="var(--fg)">{y_max / 2.0:.1f}</text>
  <text x="{margin_left - 6}" y="{y1 + 4}" text-anchor="end" font-size="11" fill="var(--fg)">{y_max:.1f}</text>
  <text x="{margin_left}" y="{margin_top + plot_h + 22}" font-size="11" fill="var(--fg)">frame 0</text>
  <text x="{margin_left + plot_w}" y="{margin_top + plot_h + 22}" text-anchor="end" font-size="11" fill="var(--fg)">frame {n - 1}</text>
  {line_layer(drift, "#2b6cb0")}
  {line_layer(fd, "#dd6b20")}
  <line id="marker" x1="{x_positions[0]:.2f}" y1="{margin_top}" x2="{x_positions[0]:.2f}" y2="{margin_top + plot_h}"
        stroke="var(--fg)" stroke-width="1.5" stroke-dasharray="3,3"/>
  <g font-size="11" fill="var(--fg)">
    <rect x="{width - 190}" y="{margin_top}" width="10" height="10" fill="#dd6b20"/>
    <text x="{width - 176}" y="{margin_top + 9}">FD (frame-to-frame, mm)</text>
    <rect x="{width - 190}" y="{margin_top + 16}" width="10" height="10" fill="#2b6cb0"/>
    <text x="{width - 176}" y="{margin_top + 25}">Drift (from reference, mm)</text>
    {legend_extra}
  </g>
</svg>
""".strip()
    return svg, x_positions, width, height


def render_html(frame_order, frames_json, motion, radius, out_path, linked=None):
    """
    Write the self-contained HTML QC report: no CDN, no external JS/CSS --
    everything (including the motion plot, as inline SVG) is inlined into
    one file, alongside a folder of PNGs referenced by relative path.

    Parameters
    ----------
    frame_order : list of str
        Chronological frame names, aligned to `frames_json`/`motion`.
    frames_json : list of dict
        One entry per frame: {"name": str, "before": {view: rel_path, ...},
        "after": {view: rel_path, ...}}.
    motion : dict
        {"fd": [...], "drift": [...]}, aligned to `frame_order`.
    radius : float
        VOI radius (mm) used for the rotation->mm conversion, echoed in the
        page for reference.
    out_path : Path
        Destination HTML file path.
    linked : list of bool, optional
        Aligned to `frame_order`: True for a frame that wasn't
        independently resolved (--exclude'd or upstream --skip-before'd),
        shown with dashed line segments/hollow points on the plot. Defaults
        to all-False.
    """
    linked = list(linked) if linked is not None else [False] * len(frame_order)
    svg, x_positions, svg_w, _svg_h = _build_motion_plot_svg(motion["fd"], motion["drift"], linked)
    data = {
        "frames": frames_json,
        "fd": motion["fd"],
        "drift": motion["drift"],
        "x_positions": x_positions,
        "svg_width": svg_w,
        "linked": linked,
    }
    # Guard against a frame/image name that happens to contain "</script>".
    data_json = json.dumps(data).replace("</", "<\\/")

    html = f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Motion QC report</title>
<style>
  :root {{
    --bg: #ffffff; --fg: #1a1a1a; --panel-bg: #f4f4f5; --axis: #888;
    --flag: #8a6300; --flag-bg: #fbf0d3; --flag-border: #d9b64f;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #1a1a1a; --fg: #e5e5e5; --panel-bg: #26262a; --axis: #999;
      --flag: #e3b341; --flag-bg: rgba(227, 179, 65, 0.14); --flag-border: rgba(227, 179, 65, 0.45);
    }}
  }}
  html, body {{ background: var(--bg); color: var(--fg); font-family: system-ui, sans-serif; margin: 0; }}
  main {{ max-width: 960px; margin: 0 auto; padding: 16px; }}
  h1 {{ font-size: 1.1rem; font-weight: 600; }}
  .grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }}
  figure {{ margin: 0; background: var(--panel-bg); border-radius: 6px; padding: 6px; text-align: center; }}
  figure img {{ width: 100%; height: auto; image-rendering: pixelated; background: #000; border-radius: 3px; }}
  figcaption {{ font-size: 0.8rem; opacity: 0.8; margin-top: 4px; }}
  .row-label {{
    display: flex; align-items: center; gap: 8px;
    font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.7; margin: 14px 0 6px;
  }}
  .chip {{
    display: none; font-size: 0.68rem; font-weight: 600; text-transform: none; letter-spacing: 0.01em;
    color: var(--flag); background: var(--flag-bg); border: 1px solid var(--flag-border);
    border-radius: 999px; padding: 1px 8px;
  }}
  #frame-label {{ font-size: 0.9rem; margin: 6px 0; min-height: 1.2em; }}
  .controls {{ display: flex; align-items: center; gap: 10px; margin-top: 10px; }}
  .controls input[type=range] {{ flex: 1; }}
  #play-btn {{
    font: inherit; padding: 4px 12px; border-radius: 5px; border: 1px solid var(--axis);
    background: var(--panel-bg); color: var(--fg); cursor: pointer;
  }}
  .plot-wrap {{ margin-top: 8px; }}
</style>
</head>
<body>
<main>
  <h1>Motion QC report</h1>
  <div class="row-label">Before motion correction</div>
  <div class="grid">
    <figure><img id="img-before-sag"><figcaption>Sagittal</figcaption></figure>
    <figure><img id="img-before-cor"><figcaption>Coronal</figcaption></figure>
    <figure><img id="img-before-axi"><figcaption>Axial</figcaption></figure>
  </div>
  <div class="row-label">After motion correction <span id="after-flag" class="chip">≈ nearest frame</span></div>
  <div class="grid">
    <figure><img id="img-after-sag"><figcaption>Sagittal</figcaption></figure>
    <figure><img id="img-after-cor"><figcaption>Coronal</figcaption></figure>
    <figure><img id="img-after-axi"><figcaption>Axial</figcaption></figure>
  </div>

  <div class="controls">
    <button id="play-btn" type="button">▶ Play</button>
    <input type="range" id="frame-slider" min="0" max="{len(frame_order) - 1}" step="1" value="0">
  </div>
  <div id="frame-label"></div>

  <div class="plot-wrap">
    {svg}
  </div>
  <p style="font-size:0.75rem;opacity:0.7;">
    VOI radius = {radius:.1f} mm (used to convert rotation to an mm-equivalent
    arc-length in FD/drift). Click the plot to jump to a frame.
  </p>
</main>
<script type="application/json" id="qc-data">{data_json}</script>
<script>
(function () {{
  const data = JSON.parse(document.getElementById('qc-data').textContent);
  const slider = document.getElementById('frame-slider');
  const label = document.getElementById('frame-label');
  const marker = document.getElementById('marker');
  const afterFlag = document.getElementById('after-flag');
  const playBtn = document.getElementById('play-btn');
  const PLAY_INTERVAL_MS = 200;
  let playTimer = null;
  const imgs = {{
    beforeSag: document.getElementById('img-before-sag'),
    beforeCor: document.getElementById('img-before-cor'),
    beforeAxi: document.getElementById('img-before-axi'),
    afterSag: document.getElementById('img-after-sag'),
    afterCor: document.getElementById('img-after-cor'),
    afterAxi: document.getElementById('img-after-axi'),
  }};

  function update(idx) {{
    const f = data.frames[idx];
    imgs.beforeSag.src = f.before.sag;
    imgs.beforeCor.src = f.before.cor;
    imgs.beforeAxi.src = f.before.axi;
    imgs.afterSag.src = f.after.sag;
    imgs.afterCor.src = f.after.cor;
    imgs.afterAxi.src = f.after.axi;
    afterFlag.style.display = data.linked[idx] ? 'inline-block' : 'none';
    const note = data.linked[idx] ? "  [excluded/skipped, showing nearest frame's transform]" : "";
    label.textContent = `Frame ${{idx + 1}} / ${{data.frames.length}} — ${{f.name}}` +
      `  (FD ${{data.fd[idx].toFixed(2)}} mm, drift ${{data.drift[idx].toFixed(2)}} mm)` + note;
    marker.setAttribute('x1', data.x_positions[idx]);
    marker.setAttribute('x2', data.x_positions[idx]);
    slider.value = idx;
  }}

  function stopPlaying() {{
    if (playTimer !== null) {{
      clearInterval(playTimer);
      playTimer = null;
      playBtn.textContent = '▶ Play';
    }}
  }}

  function startPlaying() {{
    if (playTimer !== null || data.frames.length < 2) return;
    playBtn.textContent = '⏸ Pause';
    playTimer = setInterval(() => {{
      update((parseInt(slider.value, 10) + 1) % data.frames.length);
    }}, PLAY_INTERVAL_MS);
  }}

  playBtn.addEventListener('click', () => {{
    if (playTimer === null) startPlaying(); else stopPlaying();
  }});

  slider.addEventListener('input', (e) => {{ stopPlaying(); update(+e.target.value); }});

  document.getElementById('motion-plot').addEventListener('click', (e) => {{
    stopPlaying();
    const rect = e.currentTarget.getBoundingClientRect();
    const scaleX = data.svg_width / rect.width;
    const clickX = (e.clientX - rect.left) * scaleX;
    let best = 0, bestDist = Infinity;
    data.x_positions.forEach((x, i) => {{
      const d = Math.abs(x - clickX);
      if (d < bestDist) {{ bestDist = d; best = i; }}
    }});
    update(best);
  }});

  update(0);
}})();
</script>
</body>
</html>
"""
    Path(out_path).write_text(html, encoding="utf-8")


def generate_qc_report(
    image_names, resolved, before_paths, output_dir, outroot, radius=50.0, linked_names=()
):
    """
    Top-level orchestrator: render before/after orthogonal-view PNGs for
    every frame plus the FD/drift motion series, and write the
    self-contained HTML report.

    Parameters
    ----------
    image_names : list of str
        Every frame to include in the report. ``image_names[0]`` is the
        reference (identity transform) that anchors the display grid --
        pass ``result.image_names`` for just the resolved frames, or
        ``cli._expand_resolved_for_qc(result, linked_names)``'s first
        return value to also include --exclude'd/--skip-before'd frames.
    resolved : dict
        Mapping image name -> 4x4 resolved transform, covering every name
        in `image_names` (``result.resolved``, or its expansion -- see
        above).
    before_paths : dict
        Mapping image name -> Path to that frame's ORIGINAL (unresampled)
        image. The only image source needed -- "after" panels are computed
        analytically from these, in memory.
    output_dir : Path
        Directory to write the QC PNG folder and HTML report into.
    outroot : str
        File root, matching the root used elsewhere (`write_output` etc.).
    radius : float, optional
        VOI radius, mm (default 50.0).
    linked_names : iterable of str, optional
        Names in `image_names` that weren't independently resolved
        (--exclude'd or upstream --skip-before'd) and are instead showing
        a borrowed transform (see ``cli._expand_resolved_for_qc``) -- drawn
        as dashed segments/hollow points on the motion plot rather than
        looking like real per-frame data.

    Returns
    -------
    Path or None
        Path to the written HTML report, or None if no frame had a usable
        before-image (nothing to report).
    """
    linked_names = set(linked_names)
    output_dir = Path(output_dir)

    frame_order = sorted(
        (name for name in image_names if name in before_paths),
        key=_natural_sort_key,
    )
    for name in image_names:
        if name not in before_paths:
            print(
                f"  WARNING: no before-image for '{name}', skipping in QC report.",
                file=sys.stderr,
            )

    ref_name = image_names[0]
    ref_path = Path(before_paths.get(ref_name, ""))
    if ref_name not in before_paths or not ref_path.exists():
        print(
            f"WARNING: reference image '{ref_name}' unavailable; cannot generate QC report.",
            file=sys.stderr,
        )
        return None

    ref_vol, ref_shape, ref_zooms, ref_affine = load_image(ref_path)

    qc_dir = output_dir / f"{outroot}_qc"
    qc_dir.mkdir(parents=True, exist_ok=True)

    # First pass: load every frame's native volume once (reused below both
    # for the robust slice-index estimate and for actually rendering the
    # panels) and, per frame, its content centroid AND content bbox, both
    # mapped into the reference's voxel grid via that frame's resolved
    # transform -- see _robust_slice_idx for why the shared display slice is
    # chosen this way instead of the reference's blind geometric mid-slice,
    # which can miss a frame's anatomy entirely once a reference/frame pair
    # barely overlaps in field of view.
    loaded = {}
    centroids_ref = []
    bboxes_ref = []
    for name in frame_order:
        if name == ref_name:
            vol, shape, zooms, affine = ref_vol, ref_shape, ref_zooms, ref_affine
        else:
            path = Path(before_paths[name])
            if not path.exists():
                print(f"  WARNING: before-image not found, skipping: {path}", file=sys.stderr)
                continue
            try:
                vol, shape, zooms, affine = load_image(path)
            except Exception as exc:  # pylint: disable=broad-except
                print(f"  WARNING: failed to load '{name}': {exc}", file=sys.stderr)
                continue
        loaded[name] = (vol, shape, zooms, affine)

        centroid_own = np.asarray(_content_centroid_ijk(vol))
        xyz_own = voxel_to_fsl(centroid_own, shape, zooms, affine)
        xyz_own_h = np.concatenate([xyz_own, [1.0]])
        xyz_ref_h = resolved[name] @ xyz_own_h
        centroids_ref.append(fsl_to_voxel(xyz_ref_h[:3], ref_shape, ref_zooms, ref_affine))

        bbox_native = _content_bbox_native_ijk(vol)
        if bbox_native is not None:
            bboxes_ref.append(
                _content_bbox_ref_ijk(
                    bbox_native, shape, zooms, affine, resolved[name], ref_shape, ref_zooms, ref_affine
                )
            )

    if not loaded:
        print("WARNING: no frames rendered successfully; skipping QC report.", file=sys.stderr)
        return None

    # Per axis, the range of ref-grid indices where EVERY frame has content
    # is the intersection of their individual bboxes: the tightest lower
    # bound and the tightest upper bound across frames.
    shared_bounds = None
    if bboxes_ref:
        shared_bounds = [
            (max(b[ax][0] for b in bboxes_ref), min(b[ax][1] for b in bboxes_ref)) for ax in range(3)
        ]
    slice_idx = _robust_slice_idx(centroids_ref, ref_shape, shared_bounds)

    frames_json = []
    included = []
    print(f"\nRendering QC report panels (reference: {ref_name}):")
    for name in frame_order:
        if name not in loaded:
            continue
        vol, shape, zooms, affine = loaded[name]
        try:
            own_slice_idx = _own_slice_idx(
                slice_idx, ref_shape, ref_zooms, ref_affine, resolved[name], shape, zooms, affine
            )
            before_slices = native_orthoslices(vol, zooms, affine, own_slice_idx)
            after_slices = resampled_orthoslices(
                vol,
                shape,
                zooms,
                affine,
                resolved[name],
                ref_shape,
                ref_zooms,
                ref_affine,
                slice_idx,
            )

            rel = {"before": {}, "after": {}}
            for view, before_2d, after_2d in zip(_VIEWS, before_slices, after_slices):
                before_u8, after_u8 = normalize_pair(before_2d, after_2d)
                before_name = f"{name}_{view}_before.png"
                after_name = f"{name}_{view}_after.png"
                write_slice_png(before_u8, qc_dir / before_name)
                write_slice_png(after_u8, qc_dir / after_name)
                rel["before"][view] = f"{outroot}_qc/{before_name}"
                rel["after"][view] = f"{outroot}_qc/{after_name}"

            frames_json.append({"name": name, **rel})
            included.append(name)
        except Exception as exc:  # pylint: disable=broad-except
            print(f"  WARNING: failed to render QC panels for '{name}': {exc}", file=sys.stderr)

    if not included:
        print("WARNING: no frames rendered successfully; skipping QC report.", file=sys.stderr)
        return None

    print(f"  {len(included)} frame(s) rendered to {qc_dir}")

    motion = compute_motion_series(resolved, included, radius)
    linked = [name in linked_names for name in included]
    out_path = output_dir / f"{outroot}_qc_report.html"
    render_html(included, frames_json, motion, radius, out_path, linked=linked)
    print(f"\nQC report written to: {out_path}")
    return out_path
