"""
Tests for mat_resolve.transforms_io
=====================================
Covers file I/O helpers, the pattern-to-regex conversion, transform
discovery, and applying resolved transforms via FSL flirt.
"""

# pylint: disable=invalid-name

import os
from unittest.mock import patch

import nibabel as nib
import numpy as np
import pytest
from scipy.spatial.transform import Rotation

from mat_resolve.transforms_io import (
    apply_transforms,
    discover_transforms,
    pattern_to_regex,
    read_fsl_matrix,
    write_fsl_matrix,
    write_resolved_4d,
)


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


def make_dummy_transforms(n_images):
    """
    Build N dummy image names and a (moving, fixed) -> 4x4 dict of arbitrary
    (not ground-truth-tracked) rigid matrices — enough for discovery/apply
    tests that only care about filenames and file-presence behaviour, not
    numerical correctness.
    """
    image_names = [f"img{k:02d}" for k in range(n_images)]
    transforms = {}
    for i in range(n_images):
        for j in range(n_images):
            if i == j:
                continue
            transforms[(image_names[j], image_names[i])] = make_rigid_matrix(
                10.0, [0, 0, 1], [1.0, 2.0, 3.0]
            )
    return image_names, transforms


# ---------------------------------------------------------------------------
# read_fsl_matrix / write_fsl_matrix
# ---------------------------------------------------------------------------


def test_write_read_roundtrip(tmp_path):
    """Write then read a 4x4 matrix; result should be numerically identical."""
    T = make_rigid_matrix(15.0, [0, 0, 1], [3.0, -2.0, 5.0])
    fpath = tmp_path / "test.mat"
    write_fsl_matrix(T, fpath)
    T_back = read_fsl_matrix(fpath)
    np.testing.assert_allclose(T_back, T, atol=1e-8)


def test_read_wrong_shape(tmp_path):
    """Reading a file that is not 4x4 should raise ValueError."""
    fpath = tmp_path / "bad.mat"
    fpath.write_text("1 2 3\n4 5 6\n")
    with pytest.raises(ValueError, match="4x4"):
        read_fsl_matrix(fpath)


def test_read_nonexistent_file(tmp_path):
    """Reading a missing file should raise ValueError (not FileNotFoundError)."""
    with pytest.raises(ValueError):
        read_fsl_matrix(tmp_path / "missing.mat")


# ---------------------------------------------------------------------------
# pattern_to_regex
# ---------------------------------------------------------------------------


def test_pattern_default_matches():
    """Default pattern should match a standard FSL filename."""
    regex = pattern_to_regex("{moving}_to_{fixed}.mat")
    m = regex.match("img01_to_img02.mat")
    assert m is not None
    assert m.group("moving") == "img01"
    assert m.group("fixed") == "img02"


def test_pattern_custom_separator():
    """Custom separator pattern should work correctly."""
    regex = pattern_to_regex("{moving}-reg-{fixed}.mat")
    m = regex.match("subA-reg-subB.mat")
    assert m is not None
    assert m.group("moving") == "subA"
    assert m.group("fixed") == "subB"


def test_pattern_no_match():
    """Non-matching filenames should return None."""
    regex = pattern_to_regex("{moving}_to_{fixed}.mat")
    assert regex.match("something_else.txt") is None
    assert regex.match("img01_to_img02.txt") is None


def test_pattern_non_greedy_moving():
    """
    Non-greedy matching on {moving} means the first separator occurrence
    is used as the split point.
    """
    regex = pattern_to_regex("{moving}_to_{fixed}.mat")
    m = regex.match("a_to_b_to_c.mat")
    assert m is not None
    # Non-greedy: 'moving' should capture 'a', 'fixed' captures 'b_to_c'
    assert m.group("moving") == "a"
    assert m.group("fixed") == "b_to_c"


# ---------------------------------------------------------------------------
# discover_transforms
# ---------------------------------------------------------------------------


def test_discover_finds_all_pairs(tmp_path):
    """Discovery should find all N*(N-1) files and return correct image names."""
    names, transforms = make_dummy_transforms(3)

    for (moving, fixed), T in transforms.items():
        fpath = tmp_path / f"{moving}_to_{fixed}.mat"
        write_fsl_matrix(T, fpath)

    found, found_names = discover_transforms(tmp_path, "{moving}_to_{fixed}.mat")

    assert set(found_names) == set(names)
    assert len(found) == 3 * 2  # N*(N-1)


def test_discover_natural_sorts_non_padded_names(tmp_path):
    """
    Non-zero-padded numeric names must sort numerically (bold_0, bold_1,
    bold_2, ..., bold_10), not lexicographically (which would put bold_10
    right after bold_1).
    """
    names = [f"bold_{k}" for k in range(11)]
    T = make_rigid_matrix(10.0, [0, 0, 1], [1.0, 2.0, 3.0])
    for moving in names:
        for fixed in names:
            if moving == fixed:
                continue
            write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    _, found_names = discover_transforms(tmp_path, "{moving}_to_{fixed}.mat")

    assert found_names == [f"bold_{k}" for k in range(11)]


def test_discover_missing_pair_raises(tmp_path):
    """If any pair is missing, discover_transforms should raise FileNotFoundError."""
    _, transforms = make_dummy_transforms(3)

    # Write all but one pair
    pairs = list(transforms.items())
    for (moving, fixed), T in pairs[:-1]:
        write_fsl_matrix(T, tmp_path / f"{moving}_to_{fixed}.mat")

    with pytest.raises(FileNotFoundError):
        discover_transforms(tmp_path, "{moving}_to_{fixed}.mat")


def test_discover_empty_folder_raises(tmp_path):
    """Empty folder with no matching files should raise FileNotFoundError."""
    with pytest.raises(FileNotFoundError):
        discover_transforms(tmp_path, "{moving}_to_{fixed}.mat")


def test_discover_non_directory_raises(tmp_path):
    """Passing a non-directory path should raise NotADirectoryError."""
    fpath = tmp_path / "not_a_dir.txt"
    fpath.write_text("hello")
    with pytest.raises(NotADirectoryError):
        discover_transforms(fpath, "{moving}_to_{fixed}.mat")


# ---------------------------------------------------------------------------
# apply_transforms
# ---------------------------------------------------------------------------


def test_apply_calls_flirt_for_each_image(tmp_path):
    """
    apply_transforms should invoke flirt once per image with the correct
    -in, -ref, -init, and -out arguments.
    """
    image_names = ["img00", "img01", "img02"]
    outroot = "resolved"
    ext = ".nii.gz"

    # Create dummy image files so the existence check passes
    for name in image_names:
        (tmp_path / f"{name}{ext}").touch()

    # Create dummy .mat files so -init paths exist
    for name in image_names:
        (tmp_path / f"{name}_to_{outroot}.mat").touch()

    with patch("mat_resolve.transforms_io.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        # Run from tmp_path so relative mat paths resolve correctly
        orig = os.getcwd()
        os.chdir(tmp_path)
        try:
            apply_transforms(image_names, outroot, tmp_path, ext, tmp_path)
        finally:
            os.chdir(orig)

    assert mock_run.call_count == len(image_names)

    ref_path = str(tmp_path / f"{image_names[0]}{ext}")
    for i, name in enumerate(image_names):
        cmd = mock_run.call_args_list[i][0][0]
        assert cmd[0] == "flirt"
        assert "-in" in cmd
        assert str(tmp_path / f"{name}{ext}") in cmd
        assert "-ref" in cmd
        assert ref_path in cmd
        assert "-applyxfm" in cmd
        assert "-init" in cmd
        assert "-out" in cmd
        assert f"{name}_on_{outroot}{ext}" in " ".join(cmd)


def test_apply_skips_missing_image(tmp_path, capsys):
    """
    If an image file is missing, apply_transforms should warn and skip it
    rather than raising an exception or calling flirt.
    """
    image_names = ["ref", "present", "missing"]
    outroot = "res"
    ext = ".nii.gz"

    # Only create the reference and one other image (not "missing")
    for name in ["ref", "present"]:
        (tmp_path / f"{name}{ext}").touch()
    for name in image_names:
        (tmp_path / f"{name}_to_{outroot}.mat").touch()

    with patch("mat_resolve.transforms_io.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        orig = os.getcwd()
        os.chdir(tmp_path)
        try:
            apply_transforms(image_names, outroot, tmp_path, ext, tmp_path)
        finally:
            os.chdir(orig)

    # flirt should only have been called for the two images that exist
    assert mock_run.call_count == 2
    stderr = capsys.readouterr().err
    assert "missing" in stderr


def test_apply_reports_flirt_error(tmp_path, capsys):
    """
    If flirt exits with a non-zero return code, apply_transforms should
    print an error message to stderr but continue processing remaining images.
    """
    image_names = ["ref", "img01"]
    outroot = "res"
    ext = ".nii.gz"

    for name in image_names:
        (tmp_path / f"{name}{ext}").touch()
        (tmp_path / f"{name}_to_{outroot}.mat").touch()

    with patch("mat_resolve.transforms_io.subprocess.run") as mock_run:
        mock_run.return_value.returncode = 1
        mock_run.return_value.stderr = "flirt: something went wrong"
        orig = os.getcwd()
        os.chdir(tmp_path)
        try:
            apply_transforms(image_names, outroot, tmp_path, ext, tmp_path)
        finally:
            os.chdir(orig)

    # Both images were attempted despite the first failure
    assert mock_run.call_count == len(image_names)
    stderr = capsys.readouterr().err
    assert "ERROR" in stderr


def test_apply_raises_if_reference_missing(tmp_path):
    """
    If the reference image (image_names[0]) does not exist, apply_transforms
    should raise FileNotFoundError immediately.
    """
    image_names = ["ref", "img01"]
    # Deliberately do NOT create the reference image
    with pytest.raises(FileNotFoundError):
        apply_transforms(image_names, "res", tmp_path, ".nii.gz", tmp_path)


# ---------------------------------------------------------------------------
# write_resolved_4d
# ---------------------------------------------------------------------------


def _make_resampled_frame(output_dir, name, outroot, ext, shape=(3, 3, 3), value=0.0):
    img = nib.Nifti1Image(np.full(shape, value, dtype=np.float32), np.eye(4))
    path = output_dir / f"{name}_on_{outroot}{ext}"
    nib.save(img, path)
    return path


def test_write_resolved_4d_deletes_per_frame_files_on_success(tmp_path):
    """
    Once the per-frame resampled outputs are stacked, they're redundant with
    the combined 4D file and should be deleted.
    """
    frame_order = ["bold_0", "bold_1", "bold_2"]
    outroot = "resolved"
    per_frame_paths = [
        _make_resampled_frame(tmp_path, name, outroot, ".nii.gz", value=idx)
        for idx, name in enumerate(frame_order)
    ]

    out_path = write_resolved_4d(frame_order, outroot, ".nii.gz", tmp_path)

    assert out_path == tmp_path / f"{outroot}_resolved.nii.gz"
    assert out_path.exists()
    for p in per_frame_paths:
        assert not p.exists()


def test_write_resolved_4d_missing_frame_skips_and_keeps_existing(tmp_path):
    """
    If a per-frame output is missing, reassembly is skipped (returns None)
    and any existing per-frame files are left alone (nothing to clean up).
    """
    frame_order = ["bold_0", "bold_1"]
    outroot = "resolved"
    existing = _make_resampled_frame(tmp_path, "bold_0", outroot, ".nii.gz")
    # bold_1's resampled output is deliberately never created.

    out_path = write_resolved_4d(frame_order, outroot, ".nii.gz", tmp_path)

    assert out_path is None
    assert not (tmp_path / f"{outroot}_resolved.nii.gz").exists()
    assert existing.exists()
