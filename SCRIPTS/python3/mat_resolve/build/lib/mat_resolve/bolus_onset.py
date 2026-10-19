"""
bolus_onset.py
===============
Diagnostic-only (not used in optimization, like ``symmetry.py``/``qc_report.py``):
estimates the first post-bolus frame of a dynamic PET series, for use as
``mat_resolve_pairwise --skip-before auto``.

Algorithm
---------
1. Read per-frame durations (seconds) from a required PET-BIDS sidecar JSON
   (``FrameDuration`` key) and derive each frame's midtime, since PET frame
   durations are typically non-uniform (short early frames, long late
   frames) -- a naive frame-to-frame difference isn't a valid "rate of
   change" without normalizing by the actual elapsed time.
2. Compute the whole-image mean signal per frame (optionally Gaussian
   smoothed first, reusing ``--fwhm``), then its time-normalized derivative:
   ``deriv[i] = (mean[i+1] - mean[i]) / (midtime[i+1] - midtime[i])``.
3. Compute a fixed noise-floor reference (``baseline``) from the mean
   absolute derivative over the *last* ``window`` frames of the scan -- the
   quasi-steady-state tail, past the bolus transient -- not a rolling
   window and not taken from the start of the scan.
4. Scan forward from the first frame; the first ``i`` where
   ``deriv[i] > threshold * baseline`` (``threshold`` a multiplier, not a
   percentage) marks the transition into frame ``i + 1``, which becomes
   ``skip_before``. Frame ``i`` is still the "before" value; frame ``i + 1``
   is the first one whose own mean reflects the jump.
5. Fallback: if no such crossing is ever found (no bolus present), or there
   aren't even ``window + 1`` frames to compute a baseline from,
   ``skip_before = 0`` (use all frames).
"""
# pylint: disable=invalid-name

import json
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
from scipy.ndimage import gaussian_filter


def read_frame_durations(bids_json_path, n_total):
    """
    Load per-frame durations (seconds) from a PET-BIDS sidecar JSON.

    Parameters
    ----------
    bids_json_path : str or Path
        Path to a PET-BIDS JSON sidecar containing a ``FrameDuration`` array.
    n_total : int
        Expected number of frames (the 4D input's frame count); the
        ``FrameDuration`` array must have exactly this many entries.

    Returns
    -------
    frame_durations : list of float
    """
    path = Path(bids_json_path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            meta = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: cannot read BIDS JSON '{path}': {exc}", file=sys.stderr)
        sys.exit(1)

    if "FrameDuration" not in meta:
        print(
            f"ERROR: '{path}' has no 'FrameDuration' field (required PET-BIDS key).",
            file=sys.stderr,
        )
        sys.exit(1)

    durations = meta["FrameDuration"]
    if len(durations) != n_total:
        print(
            f"ERROR: '{path}' FrameDuration has {len(durations)} entries, "
            f"expected {n_total} (one per frame in the 4D input).",
            file=sys.stderr,
        )
        sys.exit(1)

    return [float(d) for d in durations]


def _frame_midtimes(frame_durations):
    """Frame midtimes (seconds), assuming contiguous frames starting at t=0."""
    durations = np.asarray(frame_durations, dtype=float)
    starts = np.concatenate(([0.0], np.cumsum(durations)[:-1]))
    return starts + durations / 2.0


def estimate_bolus_onset(
    input_4d, frame_durations, fwhm=None, threshold=25.0, window=4
):
    """
    Estimate the first post-bolus frame of a dynamic 4D NIfTI.

    Parameters
    ----------
    input_4d : str or Path
        Path to the 4D NIfTI file.
    frame_durations : list of float
        Per-frame durations (seconds), as returned by `read_frame_durations`;
        must have one entry per frame in `input_4d`.
    fwhm : float, optional
        Smooth each frame by this FWHM (mm) before computing its mean, same
        convention as `nifti_frames.extract_frames`.
    threshold : float
        Onset is flagged where the derivative exceeds `threshold` times the
        fixed end-of-scan baseline (a multiplier, not a percentage).
    window : int
        Number of frames, taken from the *end* of the scan, used to compute
        the fixed baseline.

    Returns
    -------
    skip_before : int
        The estimated `--skip-before` value (0 if no onset was detected).
    diagnostics : dict
        Full record of the computation, suitable for `write_bolus_onset_outputs`.
    """
    img = nib.load(str(input_4d))
    if img.ndim != 4:
        print(
            f"ERROR: {input_4d} is not a 4D NIfTI (shape {img.shape}).",
            file=sys.stderr,
        )
        sys.exit(1)

    n_total = img.shape[3]
    if len(frame_durations) != n_total:
        print(
            f"ERROR: frame_durations has {len(frame_durations)} entries, "
            f"expected {n_total} (one per frame in {input_4d}).",
            file=sys.stderr,
        )
        sys.exit(1)

    sigma = None
    if fwhm is not None:
        vox_sizes = img.header.get_zooms()[:3]
        sigma = [fwhm / (2.355 * v) for v in vox_sizes]

    mean_signal = np.empty(n_total, dtype=float)
    for idx in range(n_total):
        vol = np.asarray(img.dataobj[..., idx], dtype=float)
        if sigma is not None:
            vol = gaussian_filter(vol, sigma=sigma)
        mean_signal[idx] = float(np.mean(vol))

    midtimes = _frame_midtimes(frame_durations)
    dt = np.diff(midtimes)
    deriv = np.diff(mean_signal) / dt  # length n_total - 1; deriv[i] is frame i -> i+1

    skip_before = 0
    fallback_used = True
    baseline = None
    if n_total >= window + 1:
        baseline = float(np.mean(np.abs(deriv[-window:])))
        cutoff = threshold * baseline
        for i, d in enumerate(deriv):
            if d > cutoff:
                skip_before = i + 1
                fallback_used = False
                break

    return skip_before, {
        "frame_index": list(range(n_total)),
        "midtime_sec": midtimes.tolist(),
        "mean_signal": mean_signal.tolist(),
        "derivative": deriv.tolist(),
        "threshold": threshold,
        "window": window,
        "baseline": baseline,
        "skip_before": skip_before,
        "fallback_used": fallback_used,
    }


def _build_bolus_onset_svg(diagnostics):
    """Build the inline SVG markup for the derivative/threshold QA plot."""
    deriv = diagnostics["derivative"]
    n = len(deriv)
    threshold = diagnostics["threshold"]
    window = diagnostics["window"]
    baseline = diagnostics["baseline"]
    skip_before = diagnostics["skip_before"]
    fallback_used = diagnostics["fallback_used"]

    width, height = 880, 260
    margin_left, margin_right, margin_top, margin_bottom = 56, 16, 16, 32
    plot_w = width - margin_left - margin_right
    plot_h = height - margin_top - margin_bottom

    if n > 1:
        x_positions = [margin_left + k * (plot_w / (n - 1)) for k in range(n)]
    else:
        x_positions = [margin_left + plot_w / 2.0]

    cutoff = threshold * baseline if baseline is not None else None
    y_values = list(deriv) + ([cutoff] if cutoff is not None else []) + [0.0]
    y_max = max(y_values) * 1.1 if max(y_values) > 0 else max(y_values) * 0.9 or 1.0
    y_min = min(y_values) * 1.1 if min(y_values) < 0 else 0.0
    y_range = (y_max - y_min) or 1.0

    def y_of(v):
        return margin_top + plot_h - (v - y_min) / y_range * plot_h

    shade = ""
    if n >= window >= 1:
        x0 = x_positions[n - window]
        x1 = x_positions[-1]
        shade = (
            f'<rect x="{x0:.2f}" y="{margin_top}" width="{(x1 - x0):.2f}" '
            f'height="{plot_h}" fill="var(--axis)" opacity="0.12"/>'
        )

    cutoff_line = ""
    if cutoff is not None:
        y_cut = y_of(cutoff)
        cutoff_line = (
            f'<line x1="{margin_left}" y1="{y_cut:.2f}" x2="{margin_left + plot_w}" '
            f'y2="{y_cut:.2f}" stroke="#c0392b" stroke-width="1.25" stroke-dasharray="4,3"/>'
            f'<text x="{margin_left + plot_w - 4}" y="{y_cut - 4:.2f}" text-anchor="end" '
            f'font-size="11" fill="#c0392b">threshold ({threshold:g}x baseline)</text>'
        )

    parts = []
    for k in range(n - 1):
        x1, y1v = x_positions[k], y_of(deriv[k])
        x2, y2v = x_positions[k + 1], y_of(deriv[k + 1])
        parts.append(
            f'<line x1="{x1:.2f}" y1="{y1v:.2f}" x2="{x2:.2f}" y2="{y2v:.2f}" '
            f'stroke="var(--fg)" stroke-width="1.5"/>'
        )
    for k in range(n):
        x, y = x_positions[k], y_of(deriv[k])
        parts.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="2.5" fill="var(--fg)"/>')
    line_layer = "\n  ".join(parts)

    marker = ""
    if not fallback_used and n > 0:
        onset_idx = skip_before - 1  # the crossing transition index
        x_m = x_positions[onset_idx]
        marker = (
            f'<line x1="{x_m:.2f}" y1="{margin_top}" x2="{x_m:.2f}" y2="{margin_top + plot_h}" '
            f'stroke="#2e7d32" stroke-width="1.5"/>'
            f'<text x="{x_m:.2f}" y="{margin_top - 4}" text-anchor="middle" font-size="11" '
            f'fill="#2e7d32">skip_before={skip_before}</text>'
        )

    y0_line = y_of(0.0)
    window_label = ""
    if n >= window >= 1:
        window_label = (
            f'<text x="{(x_positions[n - window] + x_positions[-1]) / 2:.2f}" '
            f'y="{margin_top + plot_h + 22}" text-anchor="middle" font-size="10" '
            f'fill="var(--axis)">baseline window ({window} frames)</text>'
        )

    return f"""
<svg viewBox="0 0 {width} {height}" preserveAspectRatio="none"
     style="width:100%;height:auto;background:var(--panel-bg);">
  {shade}
  <line x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{margin_top + plot_h}"
        stroke="var(--axis)" stroke-width="1"/>
  <line x1="{margin_left}" y1="{margin_top + plot_h}" x2="{margin_left + plot_w}" y2="{margin_top + plot_h}"
        stroke="var(--axis)" stroke-width="1"/>
  <line x1="{margin_left}" y1="{y0_line:.2f}" x2="{margin_left + plot_w}" y2="{y0_line:.2f}"
        stroke="var(--axis)" stroke-width="0.75" stroke-dasharray="2,2"/>
  <text x="{margin_left - 6}" y="{y0_line + 4:.2f}" text-anchor="end" font-size="11" fill="var(--fg)">0</text>
  <text x="{margin_left - 6}" y="{margin_top + 4}" text-anchor="end" font-size="11" fill="var(--fg)">{y_max:.2f}</text>
  <text x="{margin_left - 6}" y="{margin_top + plot_h}" text-anchor="end" font-size="11" fill="var(--fg)">{y_min:.2f}</text>
  <text x="{margin_left}" y="{margin_top + plot_h + 22}" font-size="11" fill="var(--fg)">frame 0</text>
  <text x="{margin_left + plot_w}" y="{margin_top + plot_h + 22}" text-anchor="end" font-size="11" fill="var(--fg)">frame {n}</text>
  {window_label}
  {cutoff_line}
  {line_layer}
  {marker}
</svg>
"""


def _render_bolus_onset_html(diagnostics):
    """Build the self-contained HTML page wrapping the derivative QA plot."""
    svg = _build_bolus_onset_svg(diagnostics)
    baseline = diagnostics["baseline"]
    baseline_str = f"{baseline:.4g}" if baseline is not None else "n/a (too few frames)"
    fallback_note = (
        "No frame crossed the threshold; using all frames (skip_before = 0)."
        if diagnostics["fallback_used"]
        else f"Detected skip_before = {diagnostics['skip_before']}."
    )

    return f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Bolus onset QA</title>
<style>
  :root {{ --bg: #ffffff; --fg: #1a1a1a; --panel-bg: #f4f4f5; --axis: #888; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg: #1a1a1a; --fg: #e5e5e5; --panel-bg: #26262a; --axis: #999; }}
  }}
  html, body {{ background: var(--bg); color: var(--fg); font-family: system-ui, sans-serif; margin: 0; }}
  main {{ max-width: 960px; margin: 0 auto; padding: 16px; }}
  h1 {{ font-size: 1.1rem; font-weight: 600; }}
  p {{ font-size: 0.85rem; }}
  .plot-wrap {{ margin-top: 8px; }}
</style>
</head>
<body>
<main>
  <h1>Bolus onset detection</h1>
  <p>threshold = {diagnostics['threshold']:g}x, baseline window = last {diagnostics['window']} frames,
     baseline = {baseline_str}. {fallback_note}</p>
  <div class="plot-wrap">{svg}</div>
</main>
</body>
</html>
"""


def write_bolus_onset_outputs(diagnostics, output_dir):
    """
    Write the bolus-onset diagnostics JSON and QA HTML plot into `output_dir`.

    Parameters
    ----------
    diagnostics : dict
        As returned by `estimate_bolus_onset`.
    output_dir : str or Path
    """
    output_dir = Path(output_dir)

    json_path = output_dir / "bolus_onset.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(diagnostics, f, indent=2)
    print(f"Bolus onset diagnostics written to: {json_path}")

    html_path = output_dir / "bolus_onset_qa.html"
    html_path.write_text(_render_bolus_onset_html(diagnostics), encoding="utf-8")
    print(f"Bolus onset QA plot written to: {html_path}")
