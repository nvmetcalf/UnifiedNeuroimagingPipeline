"""
Tests for mat_resolve.qc_report
=================================
Covers the FSL "scaled voxel" coordinate helpers (cross-checked against
real ``flirt -applyxfm`` output where FSL is available), the FD/drift
motion-series computation, and an end-to-end smoke test of
``generate_qc_report`` -- including a full CLI run of ``--qc-report``
that does *not* pass ``--apply``.
"""

# pylint: disable=invalid-name

import shutil
import subprocess

import nibabel as nib
import numpy as np
import pytest
from PIL import Image
from scipy.spatial.transform import Rotation

from mat_resolve.qc_report import (
    _content_bbox_native_ijk,
    _content_bbox_ref_ijk,
    _content_centroid_ijk,
    _own_slice_idx,
    _robust_slice_idx,
    compute_motion_series,
    fixed_axis_for_view,
    fsl_to_voxel,
    generate_qc_report,
    load_image,
    native_orthoslices,
    normalize_pair,
    resampled_orthoslices,
    voxel_to_display_pixel,
    voxel_to_fsl,
)
from mat_resolve.nifti_frames import extract_frames as _extract_frames
from mat_resolve.nifti_frames import load_images as _load_images
from mat_resolve.transforms_io import write_fsl_matrix

FLIRT_AVAILABLE = shutil.which("flirt") is not None


def make_rigid_matrix(angle_deg, axis, translation):
    R = Rotation.from_rotvec(np.deg2rad(angle_deg) * np.asarray(axis)).as_matrix()
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = translation
    return T


def make_synthetic_dataset(n_images, rng, names=None):
    """Small synthetic pairwise-transforms dataset, mirroring test_cli.py's helper."""
    image_names = names if names is not None else [f"img{k:02d}" for k in range(n_images)]
    true_T = [np.eye(4)]
    for _ in range(n_images - 1):
        angle = rng.uniform(2, 15)
        axis = rng.standard_normal(3)
        axis /= np.linalg.norm(axis)
        trans = rng.uniform(-10, 10, 3)
        true_T.append(make_rigid_matrix(angle, axis, trans))

    transforms = {}
    for i in range(n_images):
        for j in range(n_images):
            if i == j:
                continue
            transforms[(image_names[j], image_names[i])] = np.linalg.inv(true_T[i]) @ true_T[j]
    return image_names, true_T, transforms


def make_synthetic_volume(shape, affine, seed):
    rng = np.random.default_rng(seed)
    vol = np.zeros(shape, dtype=np.float32)
    vol[shape[0] // 2 - 2 : shape[0] // 2 + 2, shape[1] // 2 - 2 : shape[1] // 2 + 2, 2:6] = 200.0
    vol[2:4, -4:, 1:3] = 80.0
    vol += rng.normal(0, 1, shape).clip(min=0).astype(np.float32)
    return nib.Nifti1Image(vol, affine)


# ---------------------------------------------------------------------------
# voxel_to_fsl / fsl_to_voxel
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("det_sign", [-1, 1])
def test_voxel_fsl_roundtrip(det_sign):
    shape = (20, 24, 18)
    zooms = (2.0, 2.5, 3.0)
    affine = np.diag([det_sign * zooms[0], zooms[1], zooms[2], 1.0])

    rng = np.random.default_rng(0)
    ijk = rng.uniform(0, 15, size=(3, 50))

    xyz = voxel_to_fsl(ijk, shape, zooms, affine)
    ijk_back = fsl_to_voxel(xyz, shape, zooms, affine)
    np.testing.assert_allclose(ijk_back, ijk, atol=1e-8)


def test_voxel_to_fsl_flip_only_for_positive_determinant():
    shape = (10, 10, 10)
    zooms = (2.0, 2.0, 2.0)
    ijk = np.array([3.0, 4.0, 5.0]).reshape(3, 1)

    affine_neg = np.diag([-2.0, 2.0, 2.0, 1.0])  # det(3x3) < 0
    affine_pos = np.diag([2.0, 2.0, 2.0, 1.0])  # det(3x3) > 0

    xyz_neg = voxel_to_fsl(ijk, shape, zooms, affine_neg)
    xyz_pos = voxel_to_fsl(ijk, shape, zooms, affine_pos)

    np.testing.assert_allclose(xyz_neg[:, 0], [6.0, 8.0, 10.0])
    # x flipped: (Nx - 1 - i) * dx = (10 - 1 - 3) * 2 = 12
    np.testing.assert_allclose(xyz_pos[:, 0], [12.0, 8.0, 10.0])


def _flirt_cross_check(tmp_path, affine, seed):
    """
    Shared machinery for the flirt cross-check tests below: resample a
    synthetic volume (given `affine`) through a known rigid transform both
    via real ``flirt -applyxfm`` (ground truth) and via
    ``resampled_orthoslices``, and return (analytic, ground_truth) plane
    tuples for the caller to compare.
    """
    shape = (24, 28, 20)
    src_img = make_synthetic_volume(shape, affine, seed=seed)
    src_path = tmp_path / "src.nii.gz"
    nib.save(src_img, src_path)

    R = Rotation.from_euler("xyz", [5, -8, 3], degrees=True).as_matrix()
    M = np.eye(4)
    M[:3, :3] = R
    M[:3, 3] = [3.0, -1.0, 5.0]
    mat_path = tmp_path / "src_to_ref.mat"
    write_fsl_matrix(M, mat_path)

    out_path = tmp_path / "src_on_ref_flirt.nii.gz"
    cmd = [
        "flirt",
        "-in", str(src_path),
        "-ref", str(src_path),
        "-applyxfm",
        "-init", str(mat_path),
        "-out", str(out_path),
        "-interp", "trilinear",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr

    # Ground truth: flirt's own output, sliced with its own native affine.
    flirt_vol, _flirt_shape, flirt_zooms, flirt_affine = load_image(out_path)

    # Our analytic path, using each image's own NATIVE affine throughout
    # (never a reoriented one -- see the module docstring's "IMPORTANT" note).
    src_vol, src_shape, src_zooms, src_affine = load_image(src_path)
    slice_idx = tuple(s // 2 for s in src_shape)

    analytic = resampled_orthoslices(
        src_vol, src_shape, src_zooms, src_affine,
        M, src_shape, src_zooms, src_affine, slice_idx,
    )
    ground_truth = native_orthoslices(flirt_vol, flirt_zooms, flirt_affine, slice_idx)
    return analytic, ground_truth


@pytest.mark.skipif(not FLIRT_AVAILABLE, reason="requires FSL flirt on PATH")
@pytest.mark.parametrize("det_sign", [-1, 1])
def test_analytic_resample_matches_flirt(tmp_path, det_sign):
    """
    Load-bearing correctness check for the whole FSL-scaled-voxel-coordinate
    approach, for both signs of the sform determinant (the infamous FSL
    x-flip case) on a clean diagonal (no rotation) affine.
    """
    affine = np.diag([det_sign * 2.0, 2.0, 2.0, 1.0])
    analytic, ground_truth = _flirt_cross_check(tmp_path, affine, seed=(0 if det_sign < 0 else 1))
    for name, a, b in zip(("sag", "cor", "axi"), analytic, ground_truth):
        np.testing.assert_allclose(
            a, b, atol=1e-2,
            err_msg=f"{name} plane (det_sign={det_sign}) disagrees with flirt",
        )


@pytest.mark.skipif(not FLIRT_AVAILABLE, reason="requires FSL flirt on PATH")
def test_analytic_resample_matches_flirt_rotated_affine_with_nonx_flip(tmp_path):
    """
    Regression test for a real bug: deciding the FSL "x-flip" from the
    *overall* 3x3 determinant sign breaks when a *different* axis (e.g. Z,
    exactly as in a real dataset with a negative Z pixdim scale) is the one
    with reversed direction, and/or when the affine has genuine rotation
    (small gantry-tilt-style off-diagonal terms), not just clean axis-
    aligned scaling. An earlier implementation that reoriented every volume
    to RAS+ canonical before applying the FSL math got this wrong by up to
    ~220/255 on synthetic data shaped like this; the fix evaluates the FSL
    math against each image's native affine and handles display
    reorientation as a separate step (see qc_report.py's module docstring).
    """
    theta = np.deg2rad(0.3)
    c, s = np.cos(theta), np.sin(theta)
    affine = np.array([
        [0.6 * c, -0.6 * s, 0.0, -60.0],
        [0.6 * s, 0.6 * c, 0.0, -55.0],
        [0.0, 0.0, -2.2, 90.0],  # independently-reversed Z, unrelated to X
        [0.0, 0.0, 0.0, 1.0],
    ])
    analytic, ground_truth = _flirt_cross_check(tmp_path, affine, seed=7)
    for name, a, b in zip(("sag", "cor", "axi"), analytic, ground_truth):
        np.testing.assert_allclose(
            a, b, atol=1e-1,
            err_msg=f"{name} plane disagrees with flirt (rotated + non-X-flip affine)",
        )


# ---------------------------------------------------------------------------
# native_orthoslices: display orientation and physical (isotropic) aspect
# ---------------------------------------------------------------------------


def test_native_orthoslices_matches_fsleyes_radiological_convention():
    """
    For a natively RAS+ volume (axis0=R+, axis1=A+, axis2=S+, e.g. a clean
    positive-diagonal affine), a marker at the Right/Anterior/Superior
    corner should land at a specific screen position in each view, matching
    FSLeyes' default radiological layout:
      - sagittal: superior-at-top, anterior-at-right
      - coronal:  superior-at-top, right-at-left (radiological)
      - axial:    anterior-at-top, right-at-left (radiological)
    """
    shape = (8, 10, 12)
    vol = np.zeros(shape)
    vol[-1, -1, -1] = 1.0  # Right, Anterior, Superior corner
    zooms = (2.0, 2.0, 2.0)
    affine = np.diag([2.0, 2.0, 2.0, 1.0])
    slice_idx = (shape[0] - 1, shape[1] - 1, shape[2] - 1)  # slice through the marker

    sag, cor, axi = native_orthoslices(vol, zooms, affine, slice_idx)

    assert sag[0, -1] == 1.0, "sagittal: expected marker at top-right (superior, anterior)"
    assert cor[0, 0] == 1.0, "coronal: expected marker at top-left (superior, right)"
    assert axi[0, 0] == 1.0, "axial: expected marker at top-left (anterior, right)"

    # And nowhere else in each (single nonzero pixel).
    assert sag.sum() == 1.0
    assert cor.sum() == 1.0
    assert axi.sum() == 1.0


def test_native_orthoslices_correct_regardless_of_native_storage_flips():
    """
    The same R/A/S marker-position expectations as above must hold no
    matter how the volume happens to be stored on disk -- e.g. natively
    X-reversed (LAS-like) and/or Z-reversed storage -- since orientation is
    now derived from the affine directly (_axis_orientation), not from a
    prior canonicalization step. Regression coverage for the bug where
    determinant-sign-based flip logic got confused by a non-X axis flip.
    """
    shape = (8, 10, 12)
    vol = np.zeros(shape)
    vol[-1, -1, -1] = 1.0  # array corner; see world corner below

    # X reversed (LAS-like: array axis0 increases toward Left) AND Z reversed
    # (increases toward Inferior) -- so the array corner above [-1,-1,-1] is
    # actually the Left/Anterior/Inferior corner in world terms.
    affine = np.diag([-2.0, 2.0, -2.0, 1.0])
    zooms = (2.0, 2.0, 2.0)
    slice_idx = (shape[0] - 1, shape[1] - 1, shape[2] - 1)

    sag, cor, axi = native_orthoslices(vol, zooms, affine, slice_idx)

    # World position is Left/Anterior/Inferior now (not R/A/S), so expected
    # screen corners flip accordingly relative to the RAS+ case:
    # sagittal: inferior-at-bottom, anterior-at-right.
    assert sag[-1, -1] == 1.0, "sagittal: expected marker at bottom-right (inferior, anterior)"
    # coronal: inferior-at-bottom, LEFT-at-left means subject's Left is at
    # screen-right (radiological still puts R at left, so L goes right).
    assert cor[-1, -1] == 1.0, "coronal: expected marker at bottom-right (inferior, left-subject)"
    # axial: anterior-at-top, left-subject-at-right.
    assert axi[0, -1] == 1.0, "axial: expected marker at top-right (anterior, left-subject)"

    assert sag.sum() == 1.0
    assert cor.sum() == 1.0
    assert axi.sum() == 1.0


def test_native_orthoslices_isotropic_zoom_upsamples_coarse_axis():
    """
    Anisotropic voxels (coarser through-plane spacing, e.g. thicker slices)
    must not distort the displayed proportions: the coarser axis should be
    upsampled to match the finer axis' physical spacing.
    """
    shape = (8, 10, 6)  # Nz deliberately small: coarse through-plane spacing
    vol = np.zeros(shape)
    zooms = (2.0, 2.0, 4.0)  # z spacing is double x/y
    affine = np.diag([2.0, 2.0, 4.0, 1.0])
    slice_idx = (4, 5, 3)

    sag, cor, axi = native_orthoslices(vol, zooms, affine, slice_idx)

    # sag/cor rows correspond to Z (coarse: dz=4mm, target=min(dz,other)=2mm)
    # -> upsampled 2x, from Nz=6 to 12.
    assert sag.shape == (12, 10)
    assert cor.shape == (12, 8)
    # axi's two in-plane axes (dy=dx=2mm) are already isotropic -> unchanged.
    assert axi.shape == (10, 8)


def _signed_permutation_affine(perm, flips, zoom=2.0):
    """
    3x3 signed-permutation affine (voxel index -> world mm): world axis
    `row` is driven by array axis `perm[row]`, negated if `flips[row]`.
    `perm` must be a permutation of (0, 1, 2).
    """
    R = np.zeros((3, 3))
    for row, (col, flip) in enumerate(zip(perm, flips)):
        R[row, col] = -zoom if flip else zoom
    affine = np.eye(4)
    affine[:3, :3] = R
    return affine


@pytest.mark.parametrize(
    "perm,flips",
    [
        ((0, 1, 2), (False, False, False)),
        ((0, 1, 2), (True, False, False)),
        ((0, 1, 2), (False, True, False)),
        ((0, 1, 2), (False, False, True)),
        ((1, 0, 2), (False, True, False)),
        ((2, 1, 0), (True, True, False)),
    ],
)
def test_voxel_to_display_pixel_matches_native_orthoslices(perm, flips):
    """
    voxel_to_display_pixel must place a point at exactly the pixel
    native_orthoslices would render image content at for the same voxel --
    checked here via a single bright voxel's rendered position (argmax),
    across several affine orientations (axis flips + a permutation) to
    exercise the same flip/transpose logic native_orthoslices itself uses.
    Isotropic zooms are used so _isotropic_zoom is a no-op, keeping the
    comparison an exact pixel match rather than an interpolated one.
    """
    shape = (10, 12, 14)
    zooms = (2.0, 2.0, 2.0)
    affine = _signed_permutation_affine(perm, flips)
    voxel = (5, 6, 9)

    vol = np.zeros(shape)
    vol[voxel] = 1.0
    planes = native_orthoslices(vol, zooms, affine, voxel)

    for view in range(3):
        expected_row, expected_col = np.unravel_index(np.argmax(planes[view]), planes[view].shape)
        row, col = voxel_to_display_pixel(np.array(voxel, dtype=float), shape, zooms, affine, view)
        assert round(row) == expected_row
        assert round(col) == expected_col


@pytest.mark.parametrize(
    "perm,flips",
    [
        ((0, 1, 2), (False, False, False)),
        ((1, 0, 2), (False, True, False)),
        ((2, 1, 0), (True, True, False)),
    ],
)
def test_fixed_axis_for_view_matches_native_orthoslices_slicing(perm, flips):
    """
    fixed_axis_for_view must agree with the axis native_orthoslices itself
    holds fixed for each view -- checked by slicing at two different
    positions along the reported axis and confirming the rendered plane
    actually changes (proving that axis is the one being sliced) while
    other views stay put.
    """
    shape = (10, 12, 14)
    zooms = (2.0, 2.0, 2.0)
    affine = _signed_permutation_affine(perm, flips)
    rng = np.random.default_rng(0)
    vol = rng.random(shape)

    idx_a = (5, 6, 7)
    for view in range(3):
        fixed_axis = fixed_axis_for_view(affine, view)
        idx_b = list(idx_a)
        idx_b[fixed_axis] = (idx_a[fixed_axis] + 1) % shape[fixed_axis]
        idx_b = tuple(idx_b)

        plane_a = native_orthoslices(vol, zooms, affine, idx_a)[view]
        plane_b = native_orthoslices(vol, zooms, affine, idx_b)[view]
        assert not np.allclose(plane_a, plane_b)


def test_resampled_orthoslices_orientation_matches_native():
    """
    The "after" (analytically resampled) panels must use the exact same
    display convention as the "before" (native) panels -- otherwise a
    before/after comparison would be comparing different orientations.
    Verified here with an identity resolved transform (name grid == ref
    grid), so resampled_orthoslices should reproduce native_orthoslices
    exactly.
    """
    shape = (8, 10, 12)
    vol = np.zeros(shape)
    vol[-1, -1, -1] = 1.0
    zooms = (2.0, 2.0, 2.0)
    affine = np.diag([2.0, 2.0, 2.0, 1.0])
    slice_idx = (shape[0] - 1, shape[1] - 1, shape[2] - 1)

    native = native_orthoslices(vol, zooms, affine, slice_idx)
    resampled = resampled_orthoslices(
        vol, shape, zooms, affine, np.eye(4), shape, zooms, affine, slice_idx
    )
    for view, n, r in zip(("sag", "cor", "axi"), native, resampled):
        np.testing.assert_allclose(n, r, atol=1e-8, err_msg=f"{view} mismatch")


# ---------------------------------------------------------------------------
# normalize_pair
# ---------------------------------------------------------------------------


def test_normalize_pair_degenerate_all_zero_does_not_raise():
    before = np.zeros((8, 8))
    after = np.zeros((8, 8))
    before_u8, after_u8 = normalize_pair(before, after)
    assert before_u8.dtype == np.uint8
    assert after_u8.dtype == np.uint8
    np.testing.assert_array_equal(before_u8, 0)


def test_normalize_pair_shared_window():
    """Before/after should be windowed identically, not independently."""
    before = np.array([[0.0, 10.0], [10.0, 10.0]])
    after = np.array([[0.0, 5.0], [5.0, 5.0]])
    before_u8, after_u8 = normalize_pair(before, after)
    # Same nonzero value (10) would map to 255 if windowed independently for
    # `before`, but with a shared window it should map lower than 255 since
    # `after`'s max (5) is also part of the pooled percentile range.
    assert before_u8[0, 1] == 255
    assert after_u8[0, 1] < before_u8[0, 1]


# ---------------------------------------------------------------------------
# compute_motion_series
# ---------------------------------------------------------------------------


def test_compute_motion_series_known_values():
    radius = 50.0
    names = ["a", "b", "c"]
    T_a = np.eye(4)
    T_b = np.eye(4)
    T_b[:3, 3] = [1.0, 0.0, 0.0]
    T_c = np.eye(4)
    T_c[:3, 3] = [1.0, 2.0, 0.0]
    resolved = {"a": T_a, "b": T_b, "c": T_c}

    motion = compute_motion_series(resolved, names, radius)

    assert motion["fd"][0] == 0.0
    np.testing.assert_allclose(motion["drift"], [0.0, 1.0, 3.0])
    # b relative to a: +1mm in x. c relative to b: +2mm in y.
    np.testing.assert_allclose(motion["fd"][1:], [1.0, 2.0])


def test_compute_motion_series_rotation_uses_radius():
    radius = 50.0
    names = ["a", "b"]
    T_a = np.eye(4)
    T_b = np.eye(4)
    T_b[:3, :3] = Rotation.from_euler("x", 10.0, degrees=True).as_matrix()
    resolved = {"a": T_a, "b": T_b}

    motion = compute_motion_series(resolved, names, radius)
    expected = radius * np.radians(10.0)
    assert motion["drift"][1] == pytest.approx(expected, abs=1e-8)
    assert motion["fd"][1] == pytest.approx(expected, abs=1e-8)


# ---------------------------------------------------------------------------
# _build_motion_plot_svg: dashed segments/hollow points for linked frames
# ---------------------------------------------------------------------------


def test_motion_plot_svg_dashes_segments_touching_linked_frame():
    from mat_resolve.qc_report import _build_motion_plot_svg  # pylint: disable=import-outside-toplevel

    fd = [0.0, 1.0, 2.0, 1.5]
    drift = [0.0, 1.0, 1.5, 1.0]
    linked = [False, True, False, False]  # frame 1 is excluded/skipped

    svg, _x_positions, _w, _h = _build_motion_plot_svg(fd, drift, linked)

    # Both segments touching the linked point (0->1, 1->2), on both the fd
    # and drift lines, should be dashed -- 4 dashed segments, plus 1 more
    # for the legend's own dashed-line swatch (only present since something
    # is linked here) = 5.
    assert svg.count('stroke-dasharray="5,4"') == 5
    # The untouched segment (2->3) should not be dashed, on either line.
    # (Only the marker's own dash is unrelated and always present once.)
    assert svg.count("var(--panel-bg)") >= 2  # hollow point fill, fd + drift


def test_motion_plot_svg_no_dashing_when_nothing_linked():
    from mat_resolve.qc_report import _build_motion_plot_svg  # pylint: disable=import-outside-toplevel

    fd = [0.0, 1.0, 2.0]
    drift = [0.0, 1.0, 1.5]
    linked = [False, False, False]

    svg, *_ = _build_motion_plot_svg(fd, drift, linked)

    assert 'stroke-dasharray="5,4"' not in svg
    assert "Excluded/skipped" not in svg  # legend entry only appears if something is linked


# ---------------------------------------------------------------------------
# generate_qc_report: end-to-end smoke test
# ---------------------------------------------------------------------------


def test_generate_qc_report_smoke(tmp_path):
    shape = (16, 16, 16)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    names = ["f0", "f1", "f2"]
    before_paths = {}
    for i, name in enumerate(names):
        img = make_synthetic_volume(shape, affine, seed=i)
        path = tmp_path / f"{name}.nii.gz"
        nib.save(img, path)
        before_paths[name] = path

    resolved = {"f0": np.eye(4)}
    T1 = np.eye(4)
    T1[:3, 3] = [2.0, 0.0, 0.0]
    resolved["f1"] = T1
    T2 = np.eye(4)
    T2[:3, 3] = [0.0, -2.0, 4.0]
    resolved["f2"] = T2

    out_path = generate_qc_report(names, resolved, before_paths, tmp_path, "qcout", radius=50.0)

    assert out_path is not None
    assert out_path.exists()
    qc_dir = tmp_path / "qcout_qc"
    for name in names:
        for view in ("sag", "cor", "axi"):
            assert (qc_dir / f"{name}_{view}_before.png").exists()
            assert (qc_dir / f"{name}_{view}_after.png").exists()

    html = out_path.read_text()
    assert html.count('"name":') == len(names)
    for name in names:
        assert name in html
    assert 'id="play-btn"' in html
    assert "startPlaying" in html and "setInterval" in html


def test_content_centroid_ijk_matches_blob_location():
    shape = (20, 20, 20)
    vol = np.zeros(shape, dtype=np.float32)
    vol[2:6, 14:18, 8:12] = 100.0  # centroid ~ (3.5, 15.5, 9.5)

    centroid = _content_centroid_ijk(vol)

    np.testing.assert_allclose(centroid, [3.5, 15.5, 9.5], atol=0.5)


def test_content_centroid_ijk_falls_back_to_geometric_center_when_all_zero():
    shape = (10, 12, 14)
    vol = np.zeros(shape, dtype=np.float32)

    centroid = _content_centroid_ijk(vol)

    assert centroid == tuple((s - 1) / 2.0 for s in shape)


def test_robust_slice_idx_median_ignores_outlier():
    # Three frames agree near (10, 10, 10); one outlier is far away -- the
    # median-based shared slice should track the group, not the outlier.
    centroids = [
        (9.0, 9.0, 9.0),
        (10.0, 10.0, 10.0),
        (11.0, 11.0, 11.0),
        (40.0, 40.0, 40.0),
    ]

    slice_idx = _robust_slice_idx(centroids, ref_shape=(64, 64, 64))

    assert slice_idx == (10, 10, 10)


def test_robust_slice_idx_clips_to_ref_shape():
    centroids = [(-5.0, 100.0, 30.0)]

    slice_idx = _robust_slice_idx(centroids, ref_shape=(20, 20, 40))

    assert slice_idx == (0, 19, 30)


def test_content_bbox_native_ijk_matches_blob_extent():
    shape = (20, 20, 20)
    vol = np.zeros(shape, dtype=np.float32)
    vol[2:6, 14:18, 8:12] = 100.0  # indices 2-5, 14-17, 8-11

    bbox = _content_bbox_native_ijk(vol)

    assert bbox == [(2, 5), (14, 17), (8, 11)]


def test_content_bbox_native_ijk_none_when_all_zero():
    vol = np.zeros((10, 12, 14), dtype=np.float32)

    assert _content_bbox_native_ijk(vol) is None


def test_content_bbox_ref_ijk_identity_transform_matches_native():
    shape = (20, 20, 20)
    zooms = (1.0, 1.0, 1.0)
    affine = np.eye(4)
    bbox_native = [(2, 5), (14, 17), (8, 11)]

    bbox_ref = _content_bbox_ref_ijk(
        bbox_native, shape, zooms, affine, np.eye(4), shape, zooms, affine
    )

    for (lo, hi), (nlo, nhi) in zip(bbox_ref, bbox_native):
        assert lo == pytest.approx(nlo)
        assert hi == pytest.approx(nhi)


def test_robust_slice_idx_shared_bounds_overrides_median_when_outside():
    # Median would pick 10, but the shared bound (where every frame has
    # content) is [20, 25] on axis 0 -- the chosen slice must land inside it.
    centroids = [(10.0, 10.0, 10.0)]
    shared_bounds = [(20.0, 25.0), None, None]

    slice_idx = _robust_slice_idx(centroids, ref_shape=(64, 64, 64), shared_bounds=shared_bounds)

    assert 20 <= slice_idx[0] <= 25
    assert slice_idx[1:] == (10, 10)


def test_robust_slice_idx_empty_shared_bound_falls_back_to_ref_shape():
    # lo > hi -> no integer index is common to every frame on this axis;
    # falls back to the unrestricted ref_shape range instead of erroring.
    centroids = [(10.0, 10.0, 10.0)]
    shared_bounds = [(30.0, 25.0), None, None]

    slice_idx = _robust_slice_idx(centroids, ref_shape=(64, 64, 64), shared_bounds=shared_bounds)

    assert slice_idx == (10, 10, 10)


def test_own_slice_idx_clips_when_frame_is_smaller_than_ref():
    ref_shape = (100, 100, 92)
    zooms = (2.0, 2.0, 2.0)
    affine = np.eye(4)
    slice_idx = (50, 50, 91)  # valid in ref_shape, out of bounds for a smaller frame
    own_shape = (100, 100, 80)

    own_idx = _own_slice_idx(
        slice_idx, ref_shape, zooms, affine, np.eye(4), own_shape, zooms, affine
    )

    assert all(0 <= own_idx[ax] < own_shape[ax] for ax in range(3))
    assert own_idx[2] == own_shape[2] - 1


def test_generate_qc_report_finds_off_center_content(tmp_path):
    # Content is a filled cube far from the volume's geometric middle (index
    # 15-16 on every axis) -- the old blind ref_shape//2 slice would miss it
    # on every one of sag/cor/axi, since none of its fixed axes (16) falls
    # inside the blob's 24-27 range on any axis. This is exactly the
    # "picks a slice only one image has" failure mode the fix addresses.
    shape = (32, 32, 32)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    vol = np.zeros(shape, dtype=np.float32)
    # Non-uniform intensity within the blob (rather than one flat value)
    # avoids the degenerate case in normalize_pair where an all-identical
    # nonzero region gives p1 == p99 and everything collapses to black --
    # unrelated to the slice-selection behavior under test here.
    rng = np.random.default_rng(0)
    vol[24:28, 24:28, 24:28] = 500.0 + rng.normal(0, 20, size=(4, 4, 4))
    path = tmp_path / "f0.nii.gz"
    nib.save(nib.Nifti1Image(vol, affine), path)

    out_path = generate_qc_report(
        ["f0"], {"f0": np.eye(4)}, {"f0": path}, tmp_path, "qcout", radius=50.0
    )

    assert out_path is not None
    qc_dir = tmp_path / "qcout_qc"
    for view in ("sag", "cor", "axi"):
        before = np.array(Image.open(qc_dir / f"f0_{view}_before.png"))
        after = np.array(Image.open(qc_dir / f"f0_{view}_after.png"))
        assert before.max() > 0, f"{view} before-panel missed the off-center content"
        assert after.max() > 0, f"{view} after-panel missed the off-center content"


def test_generate_qc_report_missing_frame_skips_with_warning(tmp_path, capsys):
    shape = (12, 12, 12)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    names = ["f0", "f1"]
    img = make_synthetic_volume(shape, affine, seed=0)
    ref_path = tmp_path / "f0.nii.gz"
    nib.save(img, ref_path)
    before_paths = {"f0": ref_path}  # f1's image is missing on disk
    resolved = {"f0": np.eye(4), "f1": np.eye(4)}

    out_path = generate_qc_report(names, resolved, before_paths, tmp_path, "qcout", radius=50.0)

    assert out_path is not None
    captured = capsys.readouterr()
    assert "WARNING" in captured.err
    assert "f1" in captured.err


def test_generate_qc_report_returns_none_when_reference_missing(tmp_path, capsys):
    names = ["f0", "f1"]
    resolved = {"f0": np.eye(4), "f1": np.eye(4)}
    out_path = generate_qc_report(names, resolved, {}, tmp_path, "qcout", radius=50.0)
    assert out_path is None
    assert "WARNING" in capsys.readouterr().err


# ---------------------------------------------------------------------------
# CLI: --qc-report does not require --apply
# ---------------------------------------------------------------------------


def test_cli_qc_report_without_apply(tmp_path):
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"img{k:02d}" for k in range(3)]
    rng = np.random.default_rng(5)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (14, 14, 14)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    for i, name in enumerate(names):
        img = make_synthetic_volume(shape, affine, seed=i)
        nib.save(img, tmp_path / f"{name}.nii.gz")

    with patch("sys.argv", ["mat_resolve", str(tmp_path), "resolved", "--qc-report"]):
        main()

    assert (tmp_path / "resolved_qc_report.html").exists()
    assert (tmp_path / "resolved_qc").is_dir()
    # --apply was never requested: no *_on_resolved.nii.gz / _resolved.nii.gz
    # files should have been produced.
    assert not list(tmp_path.glob("*_on_resolved*"))
    assert not list(tmp_path.glob("*_resolved.nii.gz"))


def _sharp_marker_volume(shape, affine):
    """A volume with a single-voxel-sharp marker, so Gaussian smoothing is
    easy to detect."""
    vol = np.zeros(shape, dtype=np.float32)
    vol[shape[0] // 2, shape[1] // 2, shape[2] // 2] = 1000.0
    return nib.Nifti1Image(vol, affine)


def test_cli_fwhm_forwarded_to_load_images_image_dir(tmp_path):
    """--fwhm with --image-dir sourcing must reach nifti_frames.load_images
    (via a tmpdir of smoothed copies), not be dropped or hardcoded -- same
    wiring-verification pattern as test_pairwise_register.py's
    test_main_forwards_fwhm_to_extract_frames."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"img{k:02d}" for k in range(2)]
    rng = np.random.default_rng(9)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (16, 16, 16)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    for name in names:
        nib.save(_sharp_marker_volume(shape, affine), tmp_path / f"{name}.nii.gz")

    with patch("mat_resolve.cli.load_images", wraps=_load_images) as mock_load:
        with patch(
            "sys.argv",
            ["mat_resolve", str(tmp_path), "resolved", "--qc-report", "--fwhm", "6.0"],
        ):
            main()

    assert mock_load.call_args.kwargs["fwhm"] == 6.0
    assert (tmp_path / "resolved_qc_report.html").exists()
    for name in names:
        assert (tmp_path / "resolved_qc" / f"{name}_axi_before.png").exists()


def test_cli_fwhm_zero_does_not_call_load_images_image_dir(tmp_path):
    """Default --fwhm 0 must be a true no-op: the --image-dir branch should
    skip load_images/the smoothing tmpdir entirely, reading straight out of
    image_dir exactly as before --fwhm existed."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"img{k:02d}" for k in range(2)]
    rng = np.random.default_rng(10)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (12, 12, 12)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    for name in names:
        nib.save(_sharp_marker_volume(shape, affine), tmp_path / f"{name}.nii.gz")

    with patch("mat_resolve.cli.load_images", wraps=_load_images) as mock_load:
        with patch("sys.argv", ["mat_resolve", str(tmp_path), "resolved", "--qc-report"]):
            main()

    mock_load.assert_not_called()
    assert (tmp_path / "resolved_qc_report.html").exists()


def test_cli_fwhm_forwarded_to_extract_frames_input_4d(tmp_path):
    """--fwhm with --input-4d sourcing must reach extract_frames, not be dropped."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    n_frames = 2
    names = [f"pet_{k}" for k in range(n_frames)]  # matches extract_frames' pad width
    rng = np.random.default_rng(11)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (16, 16, 16)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    vol4d = np.stack(
        [np.asarray(_sharp_marker_volume(shape, affine).dataobj) for _ in names], axis=3
    )
    input_4d = tmp_path / "pet.nii.gz"
    nib.save(nib.Nifti1Image(vol4d, affine), input_4d)

    with patch("mat_resolve.cli.extract_frames", wraps=_extract_frames) as mock_extract:
        with patch(
            "sys.argv",
            [
                "mat_resolve", str(tmp_path), "resolved",
                "--qc-report", "--input-4d", str(input_4d), "--fwhm", "5.0",
            ],
        ):
            main()

    assert mock_extract.call_args.kwargs["fwhm"] == 5.0
    assert (tmp_path / "resolved_qc_report.html").exists()


def test_cli_qc_report_includes_excluded_frame(tmp_path):
    """
    --qc-report should show every discovered frame, including ones dropped
    via --exclude from the optimisation -- using its nearest surviving
    frame's resolved transform for the "after" panel.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"img{k:02d}" for k in range(4)]
    rng = np.random.default_rng(21)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (14, 14, 14)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    for i, name in enumerate(names):
        nib.save(make_synthetic_volume(shape, affine, seed=i), tmp_path / f"{name}.nii.gz")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--qc-report", "--exclude", "2"],
    ):
        main()

    html = (tmp_path / "resolved_qc_report.html").read_text()
    assert html.count('"name":') == len(names)  # all 4, including excluded img02
    assert "img02" in html
    qc_dir = tmp_path / "resolved_qc"
    for view in ("sag", "cor", "axi"):
        assert (qc_dir / f"img02_{view}_before.png").exists()
        assert (qc_dir / f"img02_{view}_after.png").exists()
    # The plot must dash the segments touching the excluded frame.
    assert 'stroke-dasharray="5,4"' in html
    assert "Excluded/skipped" in html
    assert '"linked": [false, false, true, false]' in html
    # "After motion correction" row gets a chip, toggled by JS per-frame.
    assert 'id="after-flag" class="chip">≈ nearest frame</span>' in html
    assert "afterFlag.style.display = data.linked[idx]" in html


def test_cli_qc_report_includes_skip_before_frames(tmp_path):
    """
    --qc-report should show frames dropped upstream by
    mat_resolve_pairwise --skip-before too, even though they have no
    pairwise .mat files at all -- extract_frames must be re-run over the
    full frame range (not just >= --skip-before) when --qc-report is set.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    # Simulates mat_resolve_pairwise --skip-before 2: only bold_2.. registered.
    # 5 total frames -> extract_frames pads to width 1 (len(str(5-1))), so
    # names are "bold_0".."bold_4", not zero-padded to 2 digits.
    names = [f"bold_{k}" for k in range(2, 5)]
    rng = np.random.default_rng(22)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (14, 14, 14)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    vol4d = np.stack(
        [np.asarray(make_synthetic_volume(shape, affine, seed=i).dataobj) for i in range(5)],
        axis=3,
    )
    input_4d = tmp_path / "bold.nii.gz"
    nib.save(nib.Nifti1Image(vol4d, affine), input_4d)

    with patch(
        "sys.argv",
        [
            "mat_resolve", str(tmp_path), "resolved",
            "--input-4d", str(input_4d), "--skip-before", "2", "--qc-report",
        ],
    ):
        main()

    html = (tmp_path / "resolved_qc_report.html").read_text()
    assert html.count('"name":') == 5  # bold_0..bold_4, including the 2 skipped upstream
    qc_dir = tmp_path / "resolved_qc"
    for k in range(5):
        name = f"bold_{k}"
        assert name in html
        for view in ("sag", "cor", "axi"):
            assert (qc_dir / f"{name}_{view}_before.png").exists()
            assert (qc_dir / f"{name}_{view}_after.png").exists()
    # bold_0 and bold_1 (skipped upstream) should be dashed on the plot.
    assert 'stroke-dasharray="5,4"' in html
    assert '"linked": [true, true, false, false, false]' in html


@pytest.mark.skipif(not FLIRT_AVAILABLE, reason="requires FSL flirt on PATH")
def test_cli_apply_with_skip_before_restacks_full_4d(tmp_path):
    """
    Regression test: --apply combined with --skip-before must restack the
    *full* original frame count, not just the frames that were actually
    resolved. Frames below --skip-before were never registered upstream
    (no pairwise .mat files reference them), so they aren't part of the
    optimisation -- but --apply should still resample them via flirt using
    their nearest surviving frame's resolved matrix (the same one already
    symlinked to their own <frame>_to_<OUTPUT>.mat), so the restacked
    <OUTPUT>_resolved.nii.gz keeps the original frame count/index
    alignment. An earlier version either crashed looking for resampled
    output that was never produced for the skipped frames, or (an
    intermediate fix) silently dropped them from the restacked 4D file.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    # Simulates mat_resolve_pairwise --skip-before 2: only bold_2.. registered.
    names = [f"bold_{k}" for k in range(2, 5)]
    rng = np.random.default_rng(23)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (14, 14, 14)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    vol4d = np.stack(
        [np.asarray(make_synthetic_volume(shape, affine, seed=i).dataobj) for i in range(5)],
        axis=3,
    )
    input_4d = tmp_path / "bold.nii.gz"
    nib.save(nib.Nifti1Image(vol4d, affine), input_4d)

    # No --qc-report: --apply alone must pull the full frame range now.
    with patch(
        "sys.argv",
        [
            "mat_resolve", str(tmp_path), "resolved",
            "--input-4d", str(input_4d), "--skip-before", "2", "--apply",
        ],
    ):
        main()

    resolved_4d = tmp_path / "resolved_resolved.nii.gz"
    assert resolved_4d.exists()
    # All 5 original frames get restacked -- bold_0/bold_1 (skipped
    # upstream) are resampled with bold_2's resolved matrix (its nearest
    # surviving frame).
    assert nib.load(str(resolved_4d)).shape[3] == 5
    # The intermediate per-frame resampled files are deleted once stacked
    # (--input-4d's deliverable is the combined 4D, not the per-frame files).
    for k in range(5):
        assert not (tmp_path / f"bold_{k}_on_resolved.nii.gz").exists()
    # bold_0/bold_1 (skipped upstream) were resampled using bold_2's
    # symlinked matrix -- confirm the symlink apply_transforms actually
    # used is the one _write_nearest_valid_links created.
    for k in (0, 1):
        mat_path = tmp_path / f"bold_{k}_to_resolved.mat"
        assert mat_path.is_symlink()
        assert mat_path.readlink().name == "bold_2_to_resolved.mat"


@pytest.mark.skipif(not FLIRT_AVAILABLE, reason="requires FSL flirt on PATH")
def test_cli_apply_with_exclude_resamples_excluded_frame(tmp_path):
    """
    --apply + --exclude via --image-dir (no --input-4d, no smoothing): the
    excluded frame's own image should still get resampled, using its
    nearest surviving frame's symlinked matrix -- same "linked frames are
    resampled too" behavior as --skip-before, exercised through the
    --image-dir/fwhm=None code path instead of --input-4d.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"img{k:02d}" for k in range(4)]
    rng = np.random.default_rng(24)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (14, 14, 14)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    for i, name in enumerate(names):
        nib.save(make_synthetic_volume(shape, affine, seed=i), tmp_path / f"{name}.nii.gz")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--exclude", "2", "--apply"],
    ):
        main()

    for name in names:
        assert (tmp_path / f"{name}_on_resolved.nii.gz").exists()
    mat_path = tmp_path / "img02_to_resolved.mat"
    assert mat_path.is_symlink()


@pytest.mark.skipif(not FLIRT_AVAILABLE, reason="requires FSL flirt on PATH")
def test_cli_apply_with_fwhm_skips_missing_linked_frame_image(tmp_path):
    """
    --apply + --fwhm (smoothing path) + --exclude, where the excluded
    frame's image file is missing from --image-dir entirely: this must not
    crash the whole run (load_images fails hard on any missing file) --
    the missing linked frame should just be skipped, same as
    apply_transforms already does for any other missing image.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel

    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"img{k:02d}" for k in range(4)]
    rng = np.random.default_rng(25)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    shape = (14, 14, 14)
    affine = np.diag([-2.0, 2.0, 2.0, 1.0])
    for i, name in enumerate(names):
        if name == "img02":
            continue  # excluded frame's image never existed on disk
        nib.save(make_synthetic_volume(shape, affine, seed=i), tmp_path / f"{name}.nii.gz")

    with patch(
        "sys.argv",
        [
            "mat_resolve", str(tmp_path), "resolved",
            "--exclude", "2", "--apply", "--fwhm", "4",
        ],
    ):
        main()  # must not raise / sys.exit

    for name in names:
        if name == "img02":
            assert not (tmp_path / f"{name}_on_resolved.nii.gz").exists()
        else:
            assert (tmp_path / f"{name}_on_resolved.nii.gz").exists()
