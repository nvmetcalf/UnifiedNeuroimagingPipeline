"""
Tests for mat_resolve.bolus_onset
===================================
Covers the PET-BIDS FrameDuration sidecar reader, the onset-detection
algorithm (fixed end-of-scan baseline, time-normalized derivative), and the
diagnostics JSON / QA HTML outputs.
"""
# pylint: disable=invalid-name

import json

import nibabel as nib
import numpy as np
import pytest

from mat_resolve.bolus_onset import (
    estimate_bolus_onset,
    read_frame_durations,
    write_bolus_onset_outputs,
)


def make_4d_nifti_from_means(tmp_path, means, shape=(4, 4, 4), stem="bold"):
    """Save a 4D NIfTI whose frames are each a constant volume equal to `means[i]`."""
    vols = np.stack([np.full(shape, m, dtype=np.float32) for m in means], axis=3)
    img = nib.Nifti1Image(vols, np.eye(4))
    path = tmp_path / f"{stem}.nii.gz"
    nib.save(img, path)
    return path


def write_bids_json(tmp_path, durations, name="bold.json"):
    path = tmp_path / name
    path.write_text(json.dumps({"FrameDuration": durations}))
    return path


# ---------------------------------------------------------------------------
# read_frame_durations
# ---------------------------------------------------------------------------


def test_read_frame_durations_happy_path(tmp_path):
    path = write_bids_json(tmp_path, [1.0, 2.0, 3.0])
    assert read_frame_durations(path, 3) == [1.0, 2.0, 3.0]


def test_read_frame_durations_missing_key_exits(tmp_path):
    path = tmp_path / "bold.json"
    path.write_text(json.dumps({"SomeOtherField": 1}))
    with pytest.raises(SystemExit) as exc:
        read_frame_durations(path, 3)
    assert exc.value.code != 0


def test_read_frame_durations_length_mismatch_exits(tmp_path):
    path = write_bids_json(tmp_path, [1.0, 2.0])
    with pytest.raises(SystemExit) as exc:
        read_frame_durations(path, 3)
    assert exc.value.code != 0


def test_read_frame_durations_bad_json_exits(tmp_path):
    path = tmp_path / "bold.json"
    path.write_text("not valid json{")
    with pytest.raises(SystemExit) as exc:
        read_frame_durations(path, 3)
    assert exc.value.code != 0


def test_read_frame_durations_missing_file_exits(tmp_path):
    with pytest.raises(SystemExit) as exc:
        read_frame_durations(tmp_path / "missing.json", 3)
    assert exc.value.code != 0


# ---------------------------------------------------------------------------
# estimate_bolus_onset
# ---------------------------------------------------------------------------


# 12 frames: flat pre-bolus, a sharp spike at index 3, then a long flat
# post-bolus tail -- long enough that the fixed last-`window`-frames
# baseline lands entirely past the spike's own recovery transition (index
# 3->4), not contaminated by it.
SPIKE_MEANS = [1.0, 1.0, 1.0, 50.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]


def test_estimate_bolus_onset_detects_spike_uniform_durations(tmp_path):
    """
    A flat pre-bolus signal, a sharp spike, then a flat post-bolus tail
    (used as the baseline) should detect onset at the frame right after the
    spike.
    """
    path = make_4d_nifti_from_means(tmp_path, SPIKE_MEANS)
    durations = [1.0] * len(SPIKE_MEANS)

    skip_before, diag = estimate_bolus_onset(path, durations, threshold=5.0, window=4)

    assert skip_before == 3  # deriv[2] = 49 spikes; frame 3 carries the elevated value
    assert diag["fallback_used"] is False
    assert diag["skip_before"] == 3
    assert len(diag["derivative"]) == len(SPIKE_MEANS) - 1


def test_estimate_bolus_onset_derivative_is_time_normalized(tmp_path):
    """
    deriv[i] must be (mean[i+1]-mean[i]) / (midtime[i+1]-midtime[i]), not a
    raw frame-to-frame difference -- otherwise unequal PET frame durations
    would distort which frame looks like the onset.
    """
    means = [1.0, 1.0, 3.0, 3.0, 3.0]
    path = make_4d_nifti_from_means(tmp_path, means)
    durations = [2.0, 4.0, 2.0, 2.0, 2.0]  # non-uniform

    # starts = [0, 2, 6, 8, 10]; midtimes = [1, 4, 7, 9, 11]; dt = [3, 3, 2, 2]
    _, diag = estimate_bolus_onset(path, durations, threshold=1.0, window=2)

    expected = [0.0, 2.0 / 3.0, 0.0, 0.0]
    np.testing.assert_allclose(diag["derivative"], expected, atol=1e-6)
    np.testing.assert_allclose(diag["midtime_sec"], [1.0, 4.0, 7.0, 9.0, 11.0])


def test_estimate_bolus_onset_no_spike_falls_back_to_zero(tmp_path):
    """An all-flat series (no bolus) should fall back to skip_before=0."""
    means = [1.0, 1.01, 0.99, 1.0, 1.02, 0.98, 1.0, 1.0]
    path = make_4d_nifti_from_means(tmp_path, means)
    durations = [1.0] * len(means)

    skip_before, diag = estimate_bolus_onset(path, durations, threshold=25.0, window=4)

    assert skip_before == 0
    assert diag["fallback_used"] is True


def test_estimate_bolus_onset_too_few_frames_falls_back_to_zero(tmp_path):
    """Fewer than window+1 frames means no baseline can be computed -> fallback."""
    means = [1.0, 5.0, 1.0]  # only 3 frames, window=4 needs at least 5
    path = make_4d_nifti_from_means(tmp_path, means)
    durations = [1.0] * len(means)

    skip_before, diag = estimate_bolus_onset(path, durations, threshold=1.0, window=4)

    assert skip_before == 0
    assert diag["fallback_used"] is True
    assert diag["baseline"] is None


def test_estimate_bolus_onset_3d_input_exits(tmp_path):
    """A 3D (non-4D) NIfTI should cause a sys.exit(1)."""
    data = np.zeros((4, 4, 4), dtype=np.float32)
    img = nib.Nifti1Image(data, np.eye(4))
    path = tmp_path / "vol.nii.gz"
    nib.save(img, path)

    with pytest.raises(SystemExit) as exc:
        estimate_bolus_onset(path, [1.0])
    assert exc.value.code != 0


def test_estimate_bolus_onset_duration_length_mismatch_exits(tmp_path):
    means = [1.0, 1.0, 1.0, 1.0]
    path = make_4d_nifti_from_means(tmp_path, means)
    with pytest.raises(SystemExit) as exc:
        estimate_bolus_onset(path, [1.0, 1.0])  # wrong length
    assert exc.value.code != 0


def test_estimate_bolus_onset_fwhm_forwarded(tmp_path):
    """Passing fwhm should not error and should still run the full pipeline."""
    path = make_4d_nifti_from_means(tmp_path, SPIKE_MEANS, shape=(6, 6, 6))
    durations = [1.0] * len(SPIKE_MEANS)

    skip_before, diag = estimate_bolus_onset(
        path, durations, fwhm=4.0, threshold=5.0, window=4
    )
    assert isinstance(skip_before, int)
    assert len(diag["mean_signal"]) == len(SPIKE_MEANS)


# ---------------------------------------------------------------------------
# write_bolus_onset_outputs
# ---------------------------------------------------------------------------


def test_write_bolus_onset_outputs_json_roundtrips(tmp_path):
    path = make_4d_nifti_from_means(tmp_path, SPIKE_MEANS)
    durations = [1.0] * len(SPIKE_MEANS)
    _, diag = estimate_bolus_onset(path, durations, threshold=5.0, window=4)

    write_bolus_onset_outputs(diag, tmp_path)

    saved = json.loads((tmp_path / "bolus_onset.json").read_text())
    assert saved["skip_before"] == diag["skip_before"]
    assert saved["derivative"] == diag["derivative"]


def test_write_bolus_onset_outputs_html_contains_svg_and_marker(tmp_path):
    path = make_4d_nifti_from_means(tmp_path, SPIKE_MEANS)
    durations = [1.0] * len(SPIKE_MEANS)
    skip_before, diag = estimate_bolus_onset(path, durations, threshold=5.0, window=4)
    assert not diag["fallback_used"]  # sanity: this dataset must actually detect an onset

    write_bolus_onset_outputs(diag, tmp_path)

    html = (tmp_path / "bolus_onset_qa.html").read_text()
    assert "<svg" in html
    assert f"skip_before={skip_before}" in html


def test_write_bolus_onset_outputs_html_notes_fallback(tmp_path):
    means = [1.0, 1.01, 0.99, 1.0, 1.02, 0.98, 1.0, 1.0]
    path = make_4d_nifti_from_means(tmp_path, means)
    durations = [1.0] * len(means)
    _, diag = estimate_bolus_onset(path, durations, threshold=25.0, window=4)

    write_bolus_onset_outputs(diag, tmp_path)

    html = (tmp_path / "bolus_onset_qa.html").read_text()
    assert "No frame crossed the threshold" in html
