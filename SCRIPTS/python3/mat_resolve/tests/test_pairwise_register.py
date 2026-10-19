"""
Tests for mat_resolve.pairwise_register
=========================================
Covers filename-stem extraction, 3D volume extraction from 4D NIfTI, the
single-pair flirt wrapper, argument parsing, and end-to-end main() behaviour
with a mocked flirt subprocess.
"""

# pylint: disable=invalid-name

import json
import sys
from pathlib import Path
from unittest.mock import call, patch

import nibabel as nib
import numpy as np
import pytest

from mat_resolve.pairwise_register import (
    _extract_frames,
    _load_images,
    _run_flirt,
    _stem,
    main,
    parse_args,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_4d_nifti(tmp_path, stem="bold", n_frames=3, shape=(4, 4, 4), dtype=np.float32):
    """Save a tiny synthetic 4D NIfTI and return its path."""
    data = np.arange(np.prod(shape) * n_frames, dtype=dtype).reshape((*shape, n_frames))
    img = nib.Nifti1Image(data, np.eye(4))
    img.set_data_dtype(dtype)
    path = tmp_path / f"{stem}.nii.gz"
    nib.save(img, path)
    return path


def make_3d_nifti(tmp_path, stem="sess1", shape=(4, 4, 4), dtype=np.float32, affine=None):
    """Save a tiny synthetic 3D NIfTI and return its path."""
    data = np.arange(np.prod(shape), dtype=dtype).reshape(shape)
    img = nib.Nifti1Image(data, affine if affine is not None else np.eye(4))
    img.set_data_dtype(dtype)
    path = tmp_path / f"{stem}.nii.gz"
    nib.save(img, path)
    return path


# ---------------------------------------------------------------------------
# _stem
# ---------------------------------------------------------------------------


def test_stem_nii_gz():
    assert _stem("bold.nii.gz") == "bold"


def test_stem_nii():
    assert _stem("sub01_T1.nii") == "sub01_T1"


def test_stem_no_nifti_ext():
    """Falls back to pathlib stem for non-NIfTI extensions."""
    assert _stem("scan.mat") == "scan"


def test_stem_full_path():
    assert _stem("/data/study/bold.nii.gz") == "bold"


# ---------------------------------------------------------------------------
# _extract_frames
# ---------------------------------------------------------------------------


def test_extract_frames_creates_files(tmp_path):
    """Each kept frame should produce a .nii.gz in tmpdir."""
    nii_path = make_4d_nifti(tmp_path, stem="bold", n_frames=3)
    out = {}
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(nii_path, tmpdir, skip_before=0)
        assert len(out) == 3
        for name, path in out.items():
            assert path.exists(), f"{path} was not written"


def test_extract_frames_names(tmp_path):
    """Frame names should be <stem>_<zero-padded-index>."""
    nii_path = make_4d_nifti(tmp_path, stem="bold", n_frames=3)
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(nii_path, tmpdir, skip_before=0)
    assert set(out.keys()) == {"bold_0", "bold_1", "bold_2"}


def test_extract_frames_skip_before(tmp_path):
    """skip_before=2 on a 5-frame file should yield frames 2, 3, 4."""
    nii_path = make_4d_nifti(tmp_path, n_frames=5)
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(nii_path, tmpdir, skip_before=2)
    assert len(out) == 3
    assert all(int(k.split("_")[-1]) >= 2 for k in out)


def test_extract_frames_zero_padded_for_large_n(tmp_path):
    """For 11 frames pad width should be 2 (e.g. bold_00 … bold_10)."""
    nii_path = make_4d_nifti(tmp_path, stem="bold", n_frames=11)
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(nii_path, tmpdir, skip_before=0)
    assert "bold_00" in out
    assert "bold_10" in out


def test_extract_frames_3d_input_exits(tmp_path, capsys):
    """A 3D NIfTI (not 4D) should cause a sys.exit(1)."""
    data = np.zeros((4, 4, 4), dtype=np.float32)
    img = nib.Nifti1Image(data, np.eye(4))
    path = tmp_path / "vol.nii.gz"
    nib.save(img, path)

    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        with pytest.raises(SystemExit) as exc:
            _extract_frames(path, tmpdir, skip_before=0)
    assert exc.value.code != 0


def test_extract_frames_skip_before_out_of_range_exits(tmp_path):
    """skip_before >= n_total should cause sys.exit(1)."""
    nii_path = make_4d_nifti(tmp_path, n_frames=3)
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        with pytest.raises(SystemExit) as exc:
            _extract_frames(nii_path, tmpdir, skip_before=3)
    assert exc.value.code != 0


def test_extract_frames_data_values(tmp_path):
    """Extracted volume data should match the corresponding slice of the 4D array."""
    data = np.random.default_rng(0).random((4, 4, 4, 3)).astype(np.float32)
    img = nib.Nifti1Image(data, np.eye(4))
    path = tmp_path / "bold.nii.gz"
    nib.save(img, path)

    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(path, tmpdir, skip_before=0)
        for idx, name in enumerate(sorted(out)):
            extracted = nib.load(str(out[name])).get_fdata()
            np.testing.assert_allclose(extracted, data[..., idx], atol=1e-5)


def test_extract_frames_preserves_dtype(tmp_path):
    """Extracted volumes must keep the on-disk dtype (e.g. int16, not float64)."""
    import tempfile  # pylint: disable=import-outside-toplevel

    nii_path = make_4d_nifti(tmp_path, n_frames=2, dtype=np.int16)

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(nii_path, tmpdir, skip_before=0)
        for path in out.values():
            saved_dtype = nib.load(str(path)).get_data_dtype()
            assert np.dtype(saved_dtype) == np.dtype(np.int16)


def test_extract_frames_fwhm_none_leaves_data_unchanged(tmp_path):
    """fwhm=None (the default) must not alter the extracted data at all."""
    import tempfile  # pylint: disable=import-outside-toplevel

    data = np.random.default_rng(1).random((6, 6, 6, 2)).astype(np.float32)
    img = nib.Nifti1Image(data, np.eye(4))
    path = tmp_path / "bold.nii.gz"
    nib.save(img, path)

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(path, tmpdir, skip_before=0, fwhm=None)
        for idx, name in enumerate(sorted(out)):
            extracted = nib.load(str(out[name])).get_fdata()
            np.testing.assert_allclose(extracted, data[..., idx], atol=1e-5)


def test_extract_frames_fwhm_smooths_data(tmp_path):
    """
    fwhm set should Gaussian-smooth each frame using sigma = fwhm / (2.355 * voxel_size)
    per axis, matching scipy.ndimage.gaussian_filter applied directly to the raw slice.
    """
    import tempfile  # pylint: disable=import-outside-toplevel
    from scipy.ndimage import gaussian_filter

    data = np.random.default_rng(2).random((6, 6, 6, 2)).astype(np.float32)
    img = nib.Nifti1Image(data, np.eye(4))  # 1mm isotropic voxels
    path = tmp_path / "bold.nii.gz"
    nib.save(img, path)

    fwhm = 6.0
    sigma = fwhm / 2.355  # voxel size is 1mm, so sigma is the same on every axis

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(path, tmpdir, skip_before=0, fwhm=fwhm)
        for idx, name in enumerate(sorted(out)):
            extracted = nib.load(str(out[name])).get_fdata()
            raw = data[..., idx]
            assert not np.allclose(extracted, raw)
            expected = gaussian_filter(raw, sigma=sigma)
            np.testing.assert_allclose(extracted, expected, atol=1e-5)


def test_extract_frames_fwhm_accounts_for_anisotropic_voxels(tmp_path):
    """Per-axis sigma must use each axis's own voxel size, not a single scalar."""
    import tempfile  # pylint: disable=import-outside-toplevel
    from scipy.ndimage import gaussian_filter

    data = np.random.default_rng(3).random((6, 6, 6, 1)).astype(np.float32)
    affine = np.diag([2.0, 1.0, 4.0, 1.0])  # anisotropic voxel sizes
    img = nib.Nifti1Image(data, affine)
    path = tmp_path / "bold.nii.gz"
    nib.save(img, path)

    fwhm = 8.0
    expected_sigma = [fwhm / (2.355 * v) for v in (2.0, 1.0, 4.0)]

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(path, tmpdir, skip_before=0, fwhm=fwhm)
        extracted = nib.load(str(next(iter(out.values())))).get_fdata()
        expected = gaussian_filter(data[..., 0], sigma=expected_sigma)
        np.testing.assert_allclose(extracted, expected, atol=1e-5)


def test_extract_frames_fwhm_preserves_dtype(tmp_path):
    """Smoothed volumes must keep the on-disk dtype, not be upcast to float64."""
    import tempfile  # pylint: disable=import-outside-toplevel

    nii_path = make_4d_nifti(tmp_path, n_frames=2, dtype=np.int16)

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _extract_frames(nii_path, tmpdir, skip_before=0, fwhm=4.0)
        for path in out.values():
            saved_dtype = nib.load(str(path)).get_data_dtype()
            assert np.dtype(saved_dtype) == np.dtype(np.int16)


# ---------------------------------------------------------------------------
# _load_images
# ---------------------------------------------------------------------------


def test_load_images_names_by_stem(tmp_path):
    """Each standalone image should be keyed by its filename stem."""
    p1 = make_3d_nifti(tmp_path, stem="sess1")
    p2 = make_3d_nifti(tmp_path, stem="sess2")
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _load_images([p1, p2], tmpdir)
    assert set(out.keys()) == {"sess1", "sess2"}


def test_load_images_no_fwhm_uses_original_path(tmp_path):
    """Without smoothing, the returned path should be the original file, not a copy."""
    p1 = make_3d_nifti(tmp_path, stem="sess1")
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _load_images([p1], tmpdir)
    assert out["sess1"] == p1


def test_load_images_4d_input_exits(tmp_path):
    """A 4D NIfTI passed to _load_images should cause a sys.exit(1)."""
    p1 = make_4d_nifti(tmp_path, stem="bold", n_frames=3)
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        with pytest.raises(SystemExit) as exc:
            _load_images([p1], tmpdir)
    assert exc.value.code != 0


def test_load_images_duplicate_stem_exits(tmp_path):
    """Two input paths that share a filename stem should cause a sys.exit(1)."""
    sub1 = tmp_path / "a"
    sub2 = tmp_path / "b"
    sub1.mkdir()
    sub2.mkdir()
    p1 = make_3d_nifti(sub1, stem="sess1")
    p2 = make_3d_nifti(sub2, stem="sess1")
    import tempfile  # pylint: disable=import-outside-toplevel

    with tempfile.TemporaryDirectory() as tmpdir:
        with pytest.raises(SystemExit) as exc:
            _load_images([p1, p2], tmpdir)
    assert exc.value.code != 0


def test_load_images_fwhm_smooths_data(tmp_path):
    """fwhm set should Gaussian-smooth the image, matching _extract_frames' formula."""
    import tempfile  # pylint: disable=import-outside-toplevel
    from scipy.ndimage import gaussian_filter

    data = np.random.default_rng(4).random((6, 6, 6)).astype(np.float32)
    img = nib.Nifti1Image(data, np.eye(4))
    path = tmp_path / "sess1.nii.gz"
    nib.save(img, path)

    fwhm = 6.0
    sigma = fwhm / 2.355  # 1mm isotropic voxels

    with tempfile.TemporaryDirectory() as tmpdir:
        out = _load_images([path], tmpdir, fwhm=fwhm)
        extracted = nib.load(str(out["sess1"])).get_fdata()
        assert not np.allclose(extracted, data)
        expected = gaussian_filter(data, sigma=sigma)
        np.testing.assert_allclose(extracted, expected, atol=1e-5)


# ---------------------------------------------------------------------------
# _run_flirt
# ---------------------------------------------------------------------------


def test_run_flirt_success(tmp_path):
    """A zero returncode should yield success=True and no error."""
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        label, success, err = _run_flirt(
            "bold_0", Path("bold_0.nii.gz"),
            "bold_1", Path("bold_1.nii.gz"),
            tmp_path, "{moving}_to_{fixed}.mat",
        )
    assert success is True
    assert err is None
    assert "bold_0" in label and "bold_1" in label


def test_run_flirt_failure(tmp_path):
    """A non-zero returncode should yield success=False and the stderr message."""
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 1
        mock_run.return_value.stderr = "flirt: error"
        _, success, err = _run_flirt(
            "bold_0", Path("bold_0.nii.gz"),
            "bold_1", Path("bold_1.nii.gz"),
            tmp_path, "{moving}_to_{fixed}.mat",
        )
    assert success is False
    assert "flirt: error" in err


def test_run_flirt_uses_dof_6(tmp_path):
    """The flirt command must include -dof 6."""
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        _run_flirt(
            "bold_0", Path("bold_0.nii.gz"),
            "bold_1", Path("bold_1.nii.gz"),
            tmp_path, "{moving}_to_{fixed}.mat",
        )
    cmd = mock_run.call_args[0][0]
    assert "-dof" in cmd
    assert cmd[cmd.index("-dof") + 1] == "6"


def test_run_flirt_output_path(tmp_path):
    """The -omat path must follow the given pattern inside output_dir."""
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        _run_flirt(
            "fr0", Path("fr0.nii.gz"),
            "fr1", Path("fr1.nii.gz"),
            tmp_path, "{moving}_to_{fixed}.mat",
        )
    cmd = mock_run.call_args[0][0]
    omat_idx = cmd.index("-omat")
    omat_path = Path(cmd[omat_idx + 1])
    assert omat_path == tmp_path / "fr0_to_fr1.mat"


def test_run_flirt_apply_adds_separate_o_args(tmp_path):
    """-o and its path must be two separate list elements, not one string."""
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        _run_flirt(
            "fr0", Path("fr0.nii.gz"),
            "fr1", Path("fr1.nii.gz"),
            tmp_path, "{moving}_to_{fixed}.mat",
            apply=True,
        )
    cmd = mock_run.call_args[0][0]
    assert "-o" in cmd
    o_idx = cmd.index("-o")
    # The path must be the next element, not crammed into the same string
    assert cmd[o_idx] == "-o"
    assert cmd[o_idx + 1] == str(tmp_path / "fr0_on_fr1.nii.gz")


def test_run_flirt_no_apply_omits_o_flag(tmp_path):
    """Without apply=True the -o flag must not appear in the command."""
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        _run_flirt(
            "fr0", Path("fr0.nii.gz"),
            "fr1", Path("fr1.nii.gz"),
            tmp_path, "{moving}_to_{fixed}.mat",
            apply=False,
        )
    cmd = mock_run.call_args[0][0]
    assert "-o" not in cmd


def test_run_flirt_default_keeps_nosearch_usesqform(tmp_path):
    """Default (full_search=False) must keep both -nosearch and -usesqform."""
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        _run_flirt(
            "fr0", Path("fr0.nii.gz"),
            "fr1", Path("fr1.nii.gz"),
            tmp_path, "{moving}_to_{fixed}.mat",
        )
    cmd = mock_run.call_args[0][0]
    assert "-nosearch" in cmd
    assert "-usesqform" in cmd


def test_run_flirt_full_search_drops_nosearch_usesqform(tmp_path):
    """full_search=True must omit both -nosearch and -usesqform."""
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        _run_flirt(
            "fr0", Path("fr0.nii.gz"),
            "fr1", Path("fr1.nii.gz"),
            tmp_path, "{moving}_to_{fixed}.mat",
            full_search=True,
        )
    cmd = mock_run.call_args[0][0]
    assert "-nosearch" not in cmd
    assert "-usesqform" not in cmd


# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------


def test_parse_args_defaults(tmp_path):
    """Default values for optional arguments."""
    with patch("sys.argv", ["mat_resolve_pairwise", "bold.nii.gz", str(tmp_path)]):
        args = parse_args()
    assert args.inputs == ["bold.nii.gz"]
    assert args.output_dir == str(tmp_path)
    assert args.skip_before == 0
    assert args.workers is None
    assert args.pattern == "{moving}_to_{fixed}.mat"
    assert args.verbose is False
    assert args.full_search is False


def test_parse_args_multiple_inputs():
    """More than one positional path should collect into args.inputs."""
    with patch(
        "sys.argv",
        ["mat_resolve_pairwise", "sess1.nii.gz", "sess2.nii.gz", "sess3.nii.gz", "/out"],
    ):
        args = parse_args()
    assert args.inputs == ["sess1.nii.gz", "sess2.nii.gz", "sess3.nii.gz"]


def test_parse_args_full_search():
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out", "--full-search"]):
        args = parse_args()
    assert args.full_search is True


def test_parse_args_skip_before():
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out", "--skip-before", "5"]):
        args = parse_args()
    assert args.skip_before == 5


def test_parse_args_workers():
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out", "--workers", "4"]):
        args = parse_args()
    assert args.workers == 4


def test_parse_args_verbose():
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out", "--verbose"]):
        args = parse_args()
    assert args.verbose is True


def test_parse_args_custom_pattern():
    with patch(
        "sys.argv",
        ["mat_resolve_pairwise", "f.nii.gz", "/out", "--pattern", "{moving}_{fixed}.mat"],
    ):
        args = parse_args()
    assert args.pattern == "{moving}_{fixed}.mat"


def test_parse_args_skip_before_auto():
    with patch(
        "sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out", "--skip-before", "auto"]
    ):
        args = parse_args()
    assert args.skip_before == "auto"


def test_parse_args_skip_before_invalid_exits():
    with patch(
        "sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out", "--skip-before", "nope"]
    ):
        with pytest.raises(SystemExit) as exc:
            parse_args()
    assert exc.value.code != 0


def test_parse_args_bids_json_default_none():
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out"]):
        args = parse_args()
    assert args.bids_json is None


def test_parse_args_bids_json_custom():
    with patch(
        "sys.argv",
        ["mat_resolve_pairwise", "f.nii.gz", "/out", "--bids-json", "sidecar.json"],
    ):
        args = parse_args()
    assert args.bids_json == "sidecar.json"


def test_parse_args_bolus_threshold_default():
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out"]):
        args = parse_args()
    assert args.bolus_threshold == 25.0


def test_parse_args_bolus_window_default():
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out"]):
        args = parse_args()
    assert args.bolus_window == 4


def test_parse_args_fwhm_default():
    """--fwhm should default to None (no smoothing)."""
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out"]):
        args = parse_args()
    assert args.fwhm is None


def test_parse_args_fwhm_custom():
    with patch("sys.argv", ["mat_resolve_pairwise", "f.nii.gz", "/out", "--fwhm", "6.0"]):
        args = parse_args()
    assert args.fwhm == 6.0


# ---------------------------------------------------------------------------
# main()
# ---------------------------------------------------------------------------


def test_main_missing_input_exits(tmp_path, capsys):
    """Non-existent input file should cause sys.exit."""
    with patch("sys.argv", ["mat_resolve_pairwise", str(tmp_path / "missing.nii.gz"), str(tmp_path)]):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_main_bad_pattern_exits(tmp_path):
    """Pattern without {moving} or {fixed} should cause sys.exit."""
    nii_path = make_4d_nifti(tmp_path, n_frames=2)
    with patch("sys.argv", ["mat_resolve_pairwise", str(nii_path), str(tmp_path),
                             "--pattern", "output.mat"]):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_main_creates_output_dir(tmp_path):
    """main() should create output_dir if it does not exist."""
    nii_path = make_4d_nifti(tmp_path, n_frames=2)
    out_dir = tmp_path / "new_subdir"
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch("sys.argv", ["mat_resolve_pairwise", str(nii_path), str(out_dir)]):
            main()
    assert out_dir.is_dir()


def test_main_calls_flirt_for_all_pairs(tmp_path):
    """For N frames, main() should call flirt N*(N-1) times."""
    n = 3
    nii_path = make_4d_nifti(tmp_path, n_frames=n)
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch("sys.argv", ["mat_resolve_pairwise", str(nii_path), str(tmp_path)]):
            main()
    assert mock_run.call_count == n * (n - 1)


def test_main_skip_before_reduces_pairs(tmp_path):
    """skip_before=2 on a 4-frame file leaves 2 frames -> 2 pairs."""
    nii_path = make_4d_nifti(tmp_path, n_frames=4)
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch(
            "sys.argv",
            ["mat_resolve_pairwise", str(nii_path), str(tmp_path), "--skip-before", "2"],
        ):
            main()
    assert mock_run.call_count == 2 * (2 - 1)  # 2 frames -> 2 ordered pairs


def test_main_all_flirt_commands_have_dof_6(tmp_path):
    """Every flirt invocation from main() must include -dof 6."""
    nii_path = make_4d_nifti(tmp_path, n_frames=2)
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch("sys.argv", ["mat_resolve_pairwise", str(nii_path), str(tmp_path)]):
            main()
    for c in mock_run.call_args_list:
        cmd = c[0][0]
        assert "-dof" in cmd
        assert cmd[cmd.index("-dof") + 1] == "6"


def test_main_partial_failure_exits_nonzero(tmp_path, capsys):
    """If any flirt call fails, main() should exit with a non-zero code."""
    nii_path = make_4d_nifti(tmp_path, n_frames=2)
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 1
        mock_run.return_value.stderr = "flirt: failed"
        with patch("sys.argv", ["mat_resolve_pairwise", str(nii_path), str(tmp_path)]):
            with pytest.raises(SystemExit) as exc:
                main()
    assert exc.value.code != 0


def test_main_forwards_fwhm_to_extract_frames(tmp_path):
    """--fwhm on the CLI must be forwarded to extract_frames, not dropped or hardcoded."""
    nii_path = make_4d_nifti(tmp_path, n_frames=2)
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run, patch(
        "mat_resolve.pairwise_register._extract_frames", wraps=_extract_frames
    ) as mock_extract:
        mock_run.return_value.returncode = 0
        with patch(
            "sys.argv",
            ["mat_resolve_pairwise", str(nii_path), str(tmp_path), "--fwhm", "5"],
        ):
            main()
    assert mock_extract.call_args.kwargs["fwhm"] == 5.0


def test_main_multiple_standalone_images(tmp_path):
    """Passing >1 3D image should register every ordered pair among them."""
    p1 = make_3d_nifti(tmp_path, stem="sess1")
    p2 = make_3d_nifti(tmp_path, stem="sess2")
    p3 = make_3d_nifti(tmp_path, stem="sess3")
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch(
            "sys.argv",
            ["mat_resolve_pairwise", str(p1), str(p2), str(p3), str(tmp_path)],
        ):
            main()
    assert mock_run.call_count == 3 * 2  # N*(N-1)
    omat_values = {
        Path(c[0][0][c[0][0].index("-omat") + 1]).name for c in mock_run.call_args_list
    }
    assert "sess1_to_sess2.mat" in omat_values
    assert "sess2_to_sess1.mat" in omat_values


def test_main_multiple_inputs_with_skip_before_exits(tmp_path):
    """--skip-before with multiple standalone images should exit with an error."""
    p1 = make_3d_nifti(tmp_path, stem="sess1")
    p2 = make_3d_nifti(tmp_path, stem="sess2")
    with patch(
        "sys.argv",
        ["mat_resolve_pairwise", str(p1), str(p2), str(tmp_path), "--skip-before", "1"],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_main_full_search_forwarded_to_flirt(tmp_path):
    """--full-search on the CLI must reach the built flirt command."""
    p1 = make_3d_nifti(tmp_path, stem="sess1")
    p2 = make_3d_nifti(tmp_path, stem="sess2")
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch(
            "sys.argv",
            ["mat_resolve_pairwise", str(p1), str(p2), str(tmp_path), "--full-search"],
        ):
            main()
    for c in mock_run.call_args_list:
        cmd = c[0][0]
        assert "-nosearch" not in cmd
        assert "-usesqform" not in cmd


def test_main_writes_args_json(tmp_path):
    """main() should record the parsed arguments as <stem>_args.json in output_dir."""
    nii_path = make_4d_nifti(tmp_path, stem="bold", n_frames=2)
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch(
            "sys.argv",
            ["mat_resolve_pairwise", str(nii_path), str(tmp_path), "--workers", "2"],
        ):
            main()
    saved = json.loads((tmp_path / "bold_args.json").read_text())
    assert saved["script"] == "mat_resolve_pairwise"
    assert saved["inputs"] == [str(nii_path)]
    assert saved["workers"] == 2


def test_main_writes_args_json_named_by_joined_stems_for_multi_input(tmp_path):
    """
    With standalone-images mode (multiple inputs), the args.json name should
    join every input's stem, since there's no single "output" name argument.
    """
    p1 = make_3d_nifti(tmp_path, stem="sess1")
    p2 = make_3d_nifti(tmp_path, stem="sess2")
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch("sys.argv", ["mat_resolve_pairwise", str(p1), str(p2), str(tmp_path)]):
            main()
    assert (tmp_path / "sess1_sess2_args.json").exists()


def test_main_skip_before_auto_requires_bids_json(tmp_path):
    """--skip-before auto without --bids-json should exit non-zero."""
    nii_path = make_4d_nifti(tmp_path, n_frames=4)
    with patch(
        "sys.argv",
        ["mat_resolve_pairwise", str(nii_path), str(tmp_path), "--skip-before", "auto"],
    ):
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0


def test_main_skip_before_auto_uses_estimate(tmp_path):
    """--skip-before auto should call estimate_bolus_onset and use its result."""
    n = 6
    nii_path = make_4d_nifti(tmp_path, n_frames=n)
    bids_path = tmp_path / "bold.json"
    bids_path.write_text(json.dumps({"FrameDuration": [1.0] * n}))

    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run, patch(
        "mat_resolve.pairwise_register._estimate_bolus_onset"
    ) as mock_estimate:
        mock_run.return_value.returncode = 0
        mock_estimate.return_value = (
            2,
            {
                "frame_index": list(range(n)),
                "midtime_sec": [float(i) for i in range(n)],
                "mean_signal": [0.0] * n,
                "derivative": [0.0] * (n - 1),
                "threshold": 25.0,
                "window": 4,
                "baseline": 0.0,
                "skip_before": 2,
                "fallback_used": False,
            },
        )
        with patch(
            "sys.argv",
            [
                "mat_resolve_pairwise", str(nii_path), str(tmp_path),
                "--skip-before", "auto", "--bids-json", str(bids_path),
            ],
        ):
            main()

    # n=6 frames total, skip_before=2 -> 4 frames survive -> 4*3=12 pairs
    assert mock_run.call_count == 4 * 3
    assert (tmp_path / "bolus_onset.json").exists()
    assert (tmp_path / "bolus_onset_qa.html").exists()


def test_main_output_mat_paths_follow_pattern(tmp_path):
    """Output .mat filenames must match the default {moving}_to_{fixed}.mat pattern."""
    nii_path = make_4d_nifti(tmp_path, stem="bold", n_frames=2)
    with patch("mat_resolve.pairwise_register.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        with patch("sys.argv", ["mat_resolve_pairwise", str(nii_path), str(tmp_path)]):
            main()
    omat_values = []
    for c in mock_run.call_args_list:
        cmd = c[0][0]
        omat_values.append(cmd[cmd.index("-omat") + 1])
    # For 2 frames we expect bold_0_to_bold_1.mat and bold_1_to_bold_0.mat
    names = {Path(p).name for p in omat_values}
    assert "bold_0_to_bold_1.mat" in names
    assert "bold_1_to_bold_0.mat" in names
