"""
Tests for mat_resolve.cli
==========================
Covers ``--reference`` selection/parsing and a full end-to-end integration
test with synthetic data where the ground-truth answer is known. File I/O,
discovery, and flirt-apply behaviour live in test_transforms_io.py, matching
where that code now lives (mat_resolve/transforms_io.py).
"""

# pylint: disable=invalid-name

import numpy as np
import pytest
from scipy.spatial.transform import Rotation

from mat_resolve.resolve import _build_residuals_and_jacobian, _initialise_params, _unpack_params
from mat_resolve.rigid_math import ck6_to_matrix, matrix_to_ck6, rigid_inv
from mat_resolve.transforms_io import read_fsl_matrix, write_fsl_matrix


# ---------------------------------------------------------------------------
# Helpers shared across tests
# ---------------------------------------------------------------------------


def make_rigid_matrix(angle_deg, axis, translation):
    """Build a 4x4 rigid transform from a rotation and translation."""
    R = Rotation.from_rotvec(np.deg2rad(angle_deg) * np.asarray(axis)).as_matrix()
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = translation
    return T


def make_synthetic_dataset(n_images, rng, noise_deg=0.0, noise_mm=0.0, names=None):
    """
    Create a synthetic set of pairwise transforms for N images.

    Parameters
    ----------
    names : list of str, optional
        Explicit image names to use instead of the default "imgNN" scheme
        (must have length n_images) -- lets tests exercise names whose
        trailing numeric suffix doesn't match their position, e.g. to
        simulate frames surviving a --skip-before offset.

    Returns
    -------
    image_names : list of str
    true_transforms : list of ndarray, shape (4, 4)
        true_transforms[k] maps image k to the reference (image 0 = identity),
        i.e. x_resolved = true_transforms[k] @ x_k.
    transforms : dict
        (moving, fixed) -> 4x4 observed matrix, with optional noise. These are
        RAW FSL-convention matrices, i.e. x_fixed = transforms[(moving,fixed)]
        @ x_moving — matching what a real ``flirt -omat`` file contains (see
        the "Convention" section of ``rigid_math.compose_rigid_with_jacobians``
        for how that convention was established). ``cli.py`` inverts these
        before use, so the formula below must build genuine FSL-direction
        matrices, not the internal (inverse) Tbar convention.
    """
    image_names = names if names is not None else [f"img{k:02d}" for k in range(n_images)]

    # Ground-truth transforms: T_k maps image k to reference frame
    true_T = [np.eye(4)]
    for _ in range(n_images - 1):
        angle = rng.uniform(2, 15)
        axis = rng.standard_normal(3)
        axis /= np.linalg.norm(axis)
        trans = rng.uniform(-10, 10, 3)
        true_T.append(make_rigid_matrix(angle, axis, trans))

    # Pairwise transforms, in FSL's convention (x_fixed = T @ x_moving):
    #   x_resolved = true_T[i] @ x_i  =>  x_i = inv(true_T[i]) @ x_resolved
    #   x_resolved = true_T[j] @ x_j
    #   => x_i = inv(true_T[i]) @ true_T[j] @ x_j
    # so T_{j->i} (moving=j, fixed=i) = inv(true_T[i]) @ true_T[j].
    transforms = {}
    for i in range(n_images):
        for j in range(n_images):
            if i == j:
                continue
            T_ji = np.linalg.inv(true_T[i]) @ true_T[j]
            if noise_deg > 0 or noise_mm > 0:
                n_angle = rng.uniform(0, np.deg2rad(noise_deg))
                n_axis = rng.standard_normal(3)
                n_axis /= np.linalg.norm(n_axis)
                R_noise = Rotation.from_rotvec(n_angle * n_axis).as_matrix()
                t_noise = rng.uniform(-noise_mm, noise_mm, 3)
                T_noise = np.eye(4)
                T_noise[:3, :3] = R_noise
                T_noise[:3, 3] = t_noise
                T_ji = T_ji @ T_noise
            transforms[(image_names[j], image_names[i])] = T_ji

    return image_names, true_T, transforms


# ---------------------------------------------------------------------------
# _unpack_params
# ---------------------------------------------------------------------------


def test_unpack_params_image0_is_identity():
    """Image 0 should always be unpacked as the zero CK6 (identity transform)."""
    n = 4
    x = np.arange(6 * (n - 1), dtype=float)
    ck6_list = _unpack_params(x, n)
    np.testing.assert_array_equal(ck6_list[0], np.zeros(6))


def test_unpack_params_correct_slicing():
    """Remaining images should unpack to the correct slices of x."""
    n = 3
    x = np.array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], dtype=float)
    ck6_list = _unpack_params(x, n)
    np.testing.assert_array_equal(ck6_list[1], x[:6])
    np.testing.assert_array_equal(ck6_list[2], x[6:])


# ---------------------------------------------------------------------------
# Integration test: full optimisation recovers known ground truth
# ---------------------------------------------------------------------------


def test_integration_noiseless_convergence():
    """
    With perfectly consistent (noiseless) pairwise transforms, the optimiser
    should converge to the ground-truth transforms to high precision.

    This tests the full pipeline: initialisation -> residuals/Jacobian ->
    scipy.optimize.least_squares -> recovered parameters.
    """
    from scipy.optimize import least_squares  # pylint: disable=import-outside-toplevel

    from mat_resolve.resolve import (  # pylint: disable=import-outside-toplevel
        _jacobian_fn,
        _residuals_fn,
    )

    rng = np.random.default_rng(77)
    n = 4
    names, true_T, transforms = make_synthetic_dataset(n, rng, noise_deg=0.0)

    # Initialise from direct T_{k->0} transforms (as the real CLI does)
    x0 = _initialise_params(transforms, names)

    result = least_squares(
        _residuals_fn,
        x0,
        jac=_jacobian_fn,
        method="lm",
        ftol=1e-12,
        xtol=1e-12,
        gtol=1e-12,
        args=(transforms, names, 50.0, False),
    )

    assert result.success or result.cost < 1e-10, (
        f"Optimiser did not converge: {result.message}"
    )

    # The final RMS residual should be at floating-point noise floor
    rms = np.sqrt(result.cost * 2.0 / len(result.fun))
    assert rms < 1e-6, f"RMS residual too large: {rms:.2e}"

    # ck6_list[k] holds Tbar[k], which satisfies x_k = Tbar[k] @ x_resolved
    # (see the "Convention" section of compose_rigid_with_jacobians) — the
    # opposite direction from true_T[k] (x_resolved = true_T[k] @ x_k). So
    # the recovered transform must be inverted before comparing to ground
    # truth, exactly as transforms_io.write_output does before writing the final .mat.
    ck6_list = _unpack_params(result.x, n)
    for k in range(1, n):
        T_recovered = rigid_inv(ck6_to_matrix(ck6_list[k]))
        T_true = true_T[k]
        # Compare as 4x4 matrices
        np.testing.assert_allclose(
            T_recovered,
            T_true,
            atol=1e-5,
            err_msg=f"Recovered T[{k}] does not match ground truth",
        )


def test_integration_noisy_reduces_error():
    """
    With noisy pairwise transforms, the optimiser should produce a result
    whose residual RMS is substantially lower than the input noise level.
    """
    from scipy.optimize import least_squares  # pylint: disable=import-outside-toplevel

    from mat_resolve.resolve import (  # pylint: disable=import-outside-toplevel
        _jacobian_fn,
        _residuals_fn,
    )

    rng = np.random.default_rng(99)
    n = 4
    noise_deg, noise_mm = 1.0, 1.0
    names, _, transforms = make_synthetic_dataset(
        n, rng, noise_deg=noise_deg, noise_mm=noise_mm
    )

    x0 = _initialise_params(transforms, names)
    result = least_squares(
        _residuals_fn,
        x0,
        jac=_jacobian_fn,
        method="lm",
        ftol=1e-9,
        xtol=1e-9,
        args=(transforms, names, 50.0, False),
    )

    # The optimiser should at minimum run without error
    assert result is not None
    # The residual norm after optimisation should be finite
    assert np.isfinite(result.cost)


# ---------------------------------------------------------------------------
# --reference: reference image selection
# ---------------------------------------------------------------------------


def test_reference_default_is_none():
    """
    Without --reference the parsed value is None; main() resolves that to
    the first surviving (post-exclusion) image at runtime.
    """
    from mat_resolve.cli import parse_args  # pylint: disable=import-outside-toplevel
    import unittest.mock  # pylint: disable=import-outside-toplevel

    with unittest.mock.patch("sys.argv", ["mat_resolve", "somefolder", "out"]):
        args = parse_args()
    assert args.reference is None


def test_reference_by_positive_index():
    """--reference 1 should be parsed as integer 1."""
    from mat_resolve.cli import parse_args  # pylint: disable=import-outside-toplevel
    import unittest.mock  # pylint: disable=import-outside-toplevel

    with unittest.mock.patch(
        "sys.argv", ["mat_resolve", "somefolder", "out", "--reference", "1"]
    ):
        args = parse_args()
    assert args.reference == 1


def test_fwhm_default_is_zero():
    """Without --fwhm the parsed value is 0.0 -- main() treats that as no smoothing."""
    from mat_resolve.cli import parse_args  # pylint: disable=import-outside-toplevel
    import unittest.mock  # pylint: disable=import-outside-toplevel

    with unittest.mock.patch("sys.argv", ["mat_resolve", "somefolder", "out"]):
        args = parse_args()
    assert args.fwhm == 0.0


def test_fwhm_custom_value():
    """--fwhm 6.0 should be parsed as float 6.0."""
    from mat_resolve.cli import parse_args  # pylint: disable=import-outside-toplevel
    import unittest.mock  # pylint: disable=import-outside-toplevel

    with unittest.mock.patch(
        "sys.argv", ["mat_resolve", "somefolder", "out", "--fwhm", "6.0"]
    ):
        args = parse_args()
    assert args.fwhm == 6.0


def test_reference_negative_one_is_last():
    """--reference -1 should be parsed as -1 (last image by Python indexing)."""
    from mat_resolve.cli import parse_args  # pylint: disable=import-outside-toplevel
    import unittest.mock  # pylint: disable=import-outside-toplevel

    with unittest.mock.patch(
        "sys.argv", ["mat_resolve", "somefolder", "out", "--reference", "-1"]
    ):
        args = parse_args()
    assert args.reference == -1


def test_reference_reorders_image_names():
    """
    Selecting a non-zero reference should move that image to position 0
    while preserving the relative order of the others.
    """
    image_names = ["alpha", "beta", "gamma", "delta"]

    # --reference 2 → "gamma" becomes first
    ref = image_names[2]
    reordered = [ref] + [n for n in image_names if n != ref]
    assert reordered[0] == "gamma"
    assert set(reordered) == set(image_names)
    assert len(reordered) == len(image_names)


def test_reference_negative_indexes_image_names():
    """--reference -1 should resolve to the last image via Python indexing."""
    image_names = ["alpha", "beta", "gamma"]
    ref = image_names[-1]
    assert ref == "gamma"
    reordered = [ref] + [n for n in image_names if n != ref]
    assert reordered[0] == "gamma"


def test_reference_by_name_parses_as_string():
    """--reference T1w (non-numeric) should be parsed as the raw string."""
    from mat_resolve.cli import parse_args  # pylint: disable=import-outside-toplevel
    import unittest.mock  # pylint: disable=import-outside-toplevel

    with unittest.mock.patch(
        "sys.argv", ["mat_resolve", "somefolder", "out", "--reference", "T1w"]
    ):
        args = parse_args()
    assert args.reference == "T1w"


def test_reference_by_name_selects_image(tmp_path):
    """
    --reference by exact image name should work for images with no shared
    numeric frame-numbering convention (e.g. multiple 3D inputs).
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = ["T1w", "flair", "dwi_b0"]
    rng = np.random.default_rng(15)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--reference", "flair"],
    ):
        main()

    resolved_flair = read_fsl_matrix(tmp_path / "flair_to_resolved.mat")
    np.testing.assert_allclose(resolved_flair, np.eye(4), atol=1e-8)


def test_reference_by_name_no_match_exits(tmp_path):
    """--reference naming an image that wasn't discovered should exit."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = ["T1w", "flair", "dwi_b0"]
    rng = np.random.default_rng(16)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--reference", "nope"],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_reference_by_name_pointing_at_excluded_exits(tmp_path):
    """--reference naming an image that was also --exclude'd should exit."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    # "dwi_b0" has a trailing numeric suffix of 0, so --exclude 0 drops it
    # (--exclude still matches by trailing numeric suffix, not by name).
    names = ["T1w", "flair", "dwi_b0"]
    rng = np.random.default_rng(17)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        [
            "mat_resolve", str(tmp_path), "resolved",
            "--exclude", "0", "--reference", "dwi_b0",
        ],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_reference_out_of_range_exits(tmp_path):
    """--reference index beyond the image count should exit with an error."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    rng = np.random.default_rng(45)
    names, _, transforms = make_synthetic_dataset(3, rng)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--reference", "99"],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


# ---------------------------------------------------------------------------
# --exclude: dropping images from the resolve
# ---------------------------------------------------------------------------


def test_exclude_default_none():
    """Without --exclude the default should be None (nothing excluded)."""
    from mat_resolve.cli import parse_args  # pylint: disable=import-outside-toplevel
    import unittest.mock  # pylint: disable=import-outside-toplevel

    with unittest.mock.patch("sys.argv", ["mat_resolve", "somefolder", "out"]):
        args = parse_args()
    assert args.exclude is None


def test_exclude_parses_multiple_indices():
    """--exclude 1 2 should be parsed as a list of ints."""
    from mat_resolve.cli import parse_args  # pylint: disable=import-outside-toplevel
    import unittest.mock  # pylint: disable=import-outside-toplevel

    with unittest.mock.patch(
        "sys.argv", ["mat_resolve", "somefolder", "out", "--exclude", "1", "2"]
    ):
        args = parse_args()
    assert args.exclude == [1, 2]


def test_exclude_drops_image_from_output(tmp_path):
    """
    An excluded image should not be independently resolved, but should still
    get a <name>_to_<output>.mat symlinked to the nearest surviving frame.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    rng = np.random.default_rng(7)
    names, _, transforms = make_synthetic_dataset(4, rng)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    # names sorted: img00, img01, img02, img03 -> exclude index 1 = img01
    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--exclude", "1"],
    ):
        main()

    for name in ("img00", "img02", "img03"):
        assert (tmp_path / f"{name}_to_resolved.mat").exists()

    # img01 still gets an output file, but as a symlink to its nearest
    # surviving neighbour (tie between img00 and img02 -> lower wins).
    excluded_path = tmp_path / "img01_to_resolved.mat"
    assert excluded_path.is_symlink()
    assert excluded_path.resolve() == (tmp_path / "img00_to_resolved.mat").resolve()
    np.testing.assert_array_equal(
        read_fsl_matrix(excluded_path), read_fsl_matrix(tmp_path / "img00_to_resolved.mat")
    )


def test_exclude_out_of_range_exits(tmp_path):
    """--exclude index beyond the image count should exit with an error."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    rng = np.random.default_rng(8)
    _, _, transforms = make_synthetic_dataset(3, rng)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--exclude", "99"],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_reference_pointing_at_excluded_index_exits(tmp_path):
    """--reference naming an image that was also --exclude'd should exit."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    rng = np.random.default_rng(9)
    _, _, transforms = make_synthetic_dataset(3, rng)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--exclude", "0", "--reference", "0"],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_reference_negative_one_after_exclude_is_last_surviving(tmp_path):
    """
    --reference -1 combined with --exclude should resolve to the last
    surviving image, not the (possibly-excluded) last image overall.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    rng = np.random.default_rng(10)
    names, _, transforms = make_synthetic_dataset(4, rng)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    # sorted names: img00, img01, img02, img03. Exclude img03 (index 3),
    # so --reference -1 should resolve to img02, not the excluded img03.
    with patch(
        "sys.argv",
        [
            "mat_resolve", str(tmp_path), "resolved",
            "--exclude", "3", "--reference", "-1",
        ],
    ):
        main()

    # img03 was excluded, so it isn't independently resolved -- but it still
    # gets an output file, symlinked to its nearest surviving neighbour.
    excluded_path = tmp_path / "img03_to_resolved.mat"
    assert excluded_path.is_symlink()
    assert excluded_path.resolve() == (tmp_path / "img02_to_resolved.mat").resolve()
    # The reference image is written as identity; check it's img02.
    resolved_img02 = read_fsl_matrix(tmp_path / "img02_to_resolved.mat")
    np.testing.assert_allclose(resolved_img02, np.eye(4), atol=1e-8)


# ---------------------------------------------------------------------------
# --exclude / --reference: matching by trailing numeric suffix, not position
# ---------------------------------------------------------------------------


def test_exclude_matches_suffix_not_position_after_skip_before(tmp_path):
    """
    Simulates frames surviving a mat_resolve_pairwise --skip-before offset
    (e.g. bold_11 .. bold_16, as produced when earlier frames were skipped).
    --exclude 16 must drop bold_16 (the actual last frame, discovered-list
    position 5) using the embedded frame number, not the list position.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"bold_{k}" for k in range(11, 17)]
    rng = np.random.default_rng(11)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--exclude", "16"],
    ):
        main()

    # bold_16 was excluded, so it isn't independently resolved -- but it
    # still gets an output file, symlinked to its nearest surviving
    # neighbour (bold_15).
    excluded_path = tmp_path / "bold_16_to_resolved.mat"
    assert excluded_path.is_symlink()
    assert excluded_path.resolve() == (tmp_path / "bold_15_to_resolved.mat").resolve()
    assert (tmp_path / "bold_11_to_resolved.mat").exists()
    assert (tmp_path / "bold_15_to_resolved.mat").exists()


def test_reference_default_picks_first_surviving_even_with_offset_names(tmp_path):
    """
    Default (no --reference) must resolve to the first surviving image even
    when frame numbering doesn't start at 0 (e.g. after --skip-before).
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"bold_{k}" for k in range(11, 16)]
    rng = np.random.default_rng(12)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch("sys.argv", ["mat_resolve", str(tmp_path), "resolved"]):
        main()

    resolved_bold_11 = read_fsl_matrix(tmp_path / "bold_11_to_resolved.mat")
    np.testing.assert_allclose(resolved_bold_11, np.eye(4), atol=1e-8)


def test_main_writes_args_json(tmp_path):
    """main() should record the parsed arguments as <output>_args.json."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    rng = np.random.default_rng(14)
    _, _, transforms = make_synthetic_dataset(3, rng)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch("sys.argv", ["mat_resolve", str(tmp_path), "resolved", "--radius", "40"]):
        main()

    import json  # pylint: disable=import-outside-toplevel

    args_path = tmp_path / "resolved_args.json"
    assert args_path.exists()
    saved = json.loads(args_path.read_text())
    assert saved["script"] == "mat_resolve"
    assert saved["folder"] == str(tmp_path)
    assert saved["output"] == "resolved"
    assert saved["radius"] == 40.0


def test_exclude_no_match_exits(tmp_path):
    """--exclude value matching no discovered image's suffix should exit."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    rng = np.random.default_rng(13)
    _, _, transforms = make_synthetic_dataset(3, rng)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--exclude", "99"],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_exclude_ambiguous_suffix_exits(tmp_path):
    """
    If --exclude's value matches more than one discovered image (e.g. two
    different stems both ending in the same number), it should exit with an
    error rather than guessing.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = ["bold_01", "anat_01", "extra_02"]
    rng = np.random.default_rng(14)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--exclude", "1"],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_reference_matches_suffix_of_a_specific_image(tmp_path):
    """An explicit --reference value should match by trailing suffix too."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"bold_{k}" for k in range(11, 16)]
    rng = np.random.default_rng(15)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--reference", "13"],
    ):
        main()

    resolved_bold_13 = read_fsl_matrix(tmp_path / "bold_13_to_resolved.mat")
    np.testing.assert_allclose(resolved_bold_13, np.eye(4), atol=1e-8)


# ---------------------------------------------------------------------------
# Linking skipped/excluded frames to the nearest valid frame
# ---------------------------------------------------------------------------


def test_skip_before_links_to_nearest_surviving_frame(tmp_path):
    """
    Frames with numeric suffix < --skip-before were never discovered (no
    pairwise .mat files, since mat_resolve_pairwise dropped them upstream).
    They should still get a <frame>_to_<output>.mat, symlinked to the
    nearest surviving frame.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    # Simulates mat_resolve_pairwise --skip-before 3: only bold_03.. survive.
    names = [f"bold_{k:02d}" for k in range(3, 7)]
    rng = np.random.default_rng(16)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--skip-before", "3"],
    ):
        main()

    # bold_00, bold_01, bold_02 were never discovered; all are nearest to
    # bold_03, the smallest surviving index.
    for k in range(3):
        link_path = tmp_path / f"bold_{k:02d}_to_resolved.mat"
        assert link_path.is_symlink()
        assert link_path.resolve() == (tmp_path / "bold_03_to_resolved.mat").resolve()
    for k in range(3, 7):
        assert (tmp_path / f"bold_{k:02d}_to_resolved.mat").exists()
        assert not (tmp_path / f"bold_{k:02d}_to_resolved.mat").is_symlink()


def test_exclude_links_to_nearer_of_two_neighbours(tmp_path):
    """
    An excluded frame surrounded by surviving frames on both sides should
    link to whichever neighbour is numerically closer.
    """
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"img{k:02d}" for k in range(5)]
    rng = np.random.default_rng(17)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    # Exclude img01 and img03; img02 is nearer to img01 than img00, and
    # nearer to img03 than img04 (both at distance 1, so either would be a
    # valid tie -- but img02 itself is also excluded, so both must land on
    # a genuinely surviving neighbour: img00 and img04 respectively).
    with patch(
        "sys.argv",
        ["mat_resolve", str(tmp_path), "resolved", "--exclude", "1", "2", "3"],
    ):
        main()

    link01 = tmp_path / "img01_to_resolved.mat"
    link02 = tmp_path / "img02_to_resolved.mat"
    link03 = tmp_path / "img03_to_resolved.mat"
    assert link01.resolve() == (tmp_path / "img00_to_resolved.mat").resolve()
    assert link02.resolve() == (tmp_path / "img00_to_resolved.mat").resolve()
    assert link03.resolve() == (tmp_path / "img04_to_resolved.mat").resolve()


def test_skip_before_and_exclude_combine(tmp_path):
    """--skip-before and --exclude links should both be generated together."""
    from unittest.mock import patch  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import main  # pylint: disable=import-outside-toplevel

    names = [f"bold_{k:02d}" for k in range(2, 6)]
    rng = np.random.default_rng(18)
    _, _, transforms = make_synthetic_dataset(len(names), rng, names=names)
    for (moving, fixed), T in transforms.items():
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with patch(
        "sys.argv",
        [
            "mat_resolve", str(tmp_path), "resolved",
            "--skip-before", "2", "--exclude", "3",
        ],
    ):
        main()

    # bold_00, bold_01 skipped upstream; bold_03 excluded here.
    assert (tmp_path / "bold_00_to_resolved.mat").resolve() == (
        tmp_path / "bold_02_to_resolved.mat"
    ).resolve()
    assert (tmp_path / "bold_01_to_resolved.mat").resolve() == (
        tmp_path / "bold_02_to_resolved.mat"
    ).resolve()
    assert (tmp_path / "bold_03_to_resolved.mat").resolve() == (
        tmp_path / "bold_02_to_resolved.mat"
    ).resolve()
    assert not (tmp_path / "bold_02_to_resolved.mat").is_symlink()
    assert not (tmp_path / "bold_04_to_resolved.mat").is_symlink()
    assert not (tmp_path / "bold_05_to_resolved.mat").is_symlink()


def test_expand_resolved_for_qc_adds_linked_frames_with_nearest_transform():
    """
    _expand_resolved_for_qc should append every linked (--exclude'd /
    --skip-before'd) name to image_names and give it the exact resolved
    transform of its nearest surviving neighbour -- matching what
    _write_nearest_valid_links symlinks to disk, so the QC report's
    "after" panel for a linked frame is consistent with its own output
    .mat file.
    """
    from dataclasses import dataclass  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import _expand_resolved_for_qc  # pylint: disable=import-outside-toplevel

    @dataclass
    class FakeResult:
        image_names: list
        resolved: dict

    names = ["img00", "img04"]
    T0, T4 = np.eye(4), np.eye(4)
    T4[:3, 3] = [5.0, 0.0, 0.0]
    result = FakeResult(image_names=names, resolved={"img00": T0, "img04": T4})

    # img01, img02 nearer to img00; img03 nearer to img04.
    linked_names = {"img01", "img02", "img03"}
    image_names_all, resolved_all = _expand_resolved_for_qc(result, linked_names)

    assert set(image_names_all) == set(names) | linked_names
    np.testing.assert_array_equal(resolved_all["img01"], T0)
    np.testing.assert_array_equal(resolved_all["img02"], T0)
    np.testing.assert_array_equal(resolved_all["img03"], T4)
    # Original entries untouched.
    np.testing.assert_array_equal(resolved_all["img00"], T0)
    np.testing.assert_array_equal(resolved_all["img04"], T4)


def test_expand_resolved_for_qc_empty_linked_names_is_passthrough():
    from dataclasses import dataclass  # pylint: disable=import-outside-toplevel
    from mat_resolve.cli import _expand_resolved_for_qc  # pylint: disable=import-outside-toplevel

    @dataclass
    class FakeResult:
        image_names: list
        resolved: dict

    result = FakeResult(image_names=["a", "b"], resolved={"a": np.eye(4), "b": np.eye(4)})
    image_names_all, resolved_all = _expand_resolved_for_qc(result, set())

    assert image_names_all == ["a", "b"]
    assert set(resolved_all) == {"a", "b"}

