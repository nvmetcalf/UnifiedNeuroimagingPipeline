# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install in editable mode (required before running tests or the CLI)
pip install -e .

# Run all tests
pytest

# Run a single test file
pytest tests/test_rigid_math.py

# Run a single test by name
pytest tests/test_rigid_math.py::test_compose_jacobian_moving_finite_difference

# Run the resolver
mat_resolve FOLDER OUTPUT [options]
python -m mat_resolve FOLDER OUTPUT [options]

# Run the pairwise registration (produces .mat files for mat_resolve)
mat_resolve_pairwise INPUT_4D OUTPUT_DIR [--skip-before IDX] [--workers N]
```

## Architecture

The package resolves N pairwise FSL rigid-body registration matrices into a self-consistent set of transforms mapping each image to a common space. It is a Python port of `t4_resolve.c` / `ft4_resolve.f` (Avi Synder lab, Washington University); the originals live in `src/` for reference.

### Module responsibilities

- **`rigid_math.py`** — all transform math. Rigid bodies are stored as 6-vectors (`CK6 = [e1, e2, e3, tx, ty, tz]`) where `(e1,e2,e3)` is the quaternion vector part and `e0 = sqrt(1−e1²−e2²−e3²)`. Key functions:
  - `compose_rigid_with_jacobians` — computes `predicted = Tbar[moving] · Tbar[fixed]⁻¹` and the 6×6 analytical Jacobians needed by the optimizer. This is the mathematical core; every other function supports it.
  - `quaternion_to_rotation_with_jacobian` — ports `e2rd` from `CKsub.f`. **Critical convention**: scipy's `Rotation` returns the transpose of the Fortran `e2r` result, so derivatives use `Rf = R.T` and the final Jacobian is `dR_f.transpose(1,0,2)`.
  - `quaternion_multiply_with_jacobians` — ports `ckmuld` from `CKsub.f`.

- **`resolve.py`** — the core "resolve a set of pairwise FSL transforms" algorithm as a plain Python API, independent of the CLI. Builds the residuals/Jacobian for every pair, seeds the initial guess, calls `scipy.optimize.least_squares(method='lm')`, and converts the result back to FSL-convention matrices. Public entry point: `resolve(transforms, image_names, radius=50.0, reference=0, verbose=False) -> ResolveResult`, callable directly from Python with matrices already in memory (no filesystem involved).

- **`transforms_io.py`** — file I/O, discovery, and FSL `flirt` interaction, factored out of `cli.py` so it's directly usable from Python: `discover_transforms`, `write_output`, `apply_transforms`, `write_resolved_4d`, `read_fsl_matrix`/`write_fsl_matrix`, `pattern_to_regex`. Raises ordinary exceptions (`NotADirectoryError`, `FileNotFoundError`) on error rather than calling `sys.exit` — that's a library's job, not a CLI's.

- **`cli.py`** — thin wrapper: parses arguments, calls `discover_transforms`, runs pre-optimization symmetry diagnostics, calls `resolve()`, calls `write_output`/`apply_transforms`, and converts any exception raised by `transforms_io.py` into a clean CLI error message + exit code. Also records the parsed arguments as `<output>_args.json` for provenance (`pairwise_register.py` does this too, named `<input_stem(s)>_args.json` since it has no separate "output" name argument, just `OUTPUT_DIR`).

- **`symmetry.py`** — diagnostic only (not used in optimization). Reports RMS loop-closure errors over pairs, triples, and quadruples of images before optimization.

- **`pairwise_register.py`** — standalone preprocessing step. Reads a 4D NIfTI, extracts each 3D volume to a temp directory, then runs FSL `flirt -dof 6` on every ordered pair in parallel via `ThreadPoolExecutor`. Output `.mat` files are named to match the default pattern that `mat_resolve` expects, so the two tools chain together directly. Frames before `--skip-before IDX` are excluded; `--skip-before auto` estimates `IDX` instead, via `bolus_onset.py` (requires `--bids-json`). The `mat_resolve_pairwise` CLI entry point is the typical way to invoke it.

- **`bolus_onset.py`** — diagnostic/estimation module backing `mat_resolve_pairwise --skip-before auto`. Reads per-frame durations from a PET-BIDS sidecar JSON (`FrameDuration`), computes the whole-image mean signal per frame and its time-normalized derivative, then flags the first frame whose derivative exceeds a multiplier (`--bolus-threshold`, default 25) of a fixed baseline taken from the last `--bolus-window` frames of the scan (the quasi-steady-state tail, not a rolling window). Writes `bolus_onset.json` (full diagnostics) and a self-contained `bolus_onset_qa.html` (inline-SVG plot, following `qc_report.py`'s convention — no plotting library dependency).

### Optimization setup

The optimizer solves for `N−1` free transforms `Tbar[1..N−1]` (image 0 is the fixed reference, held at identity). **`Tbar[k]` maps the resolved space into image k's own space**, i.e. `x_k = Tbar[k] @ x_resolved` — see the "Convention" section of `rigid_math.compose_rigid_with_jacobians` for the full derivation of why this is the direction (it falls out of how `predicted = Tbar[moving] · Tbar[fixed]⁻¹` has to type-check), and why it's the *opposite* of the direction a raw FSL matrix uses.

For each ordered `(moving, fixed)` image pair the predicted pairwise transform is:

```
predicted = Tbar[moving] · Tbar[fixed]⁻¹
```

The residual for each pair is `predicted − T_hat`, where `T_hat` is the **inverse of the raw observed FSL matrix** for that pair (confirmed independently against `img2stdcoord` on real data and against the `trns30` subroutine in the original `t4_sub.f`: a raw FSL file `"{moving}_to_{fixed}.mat"` satisfies `x_fixed = M @ x_moving`, the opposite direction from what `T_hat` needs here). This gives `6·N·(N−1)` scalar residuals total. Rotation residuals are linearized in quaternion tangent space using the `E4hat` matrix (built from `q_hat`) and scaled by `2·radius` (mm) to be commensurate with translation residuals.

Initial guess: `Tbar[k]` seeded from the **inverse** of the directly observed `k→0` FSL matrix (again, the raw file and `Tbar[k]` run in opposite directions). The final written output `{k}_to_{outroot}.mat` is likewise the inverse of the internal `Tbar[k]`, converting back to FSL's own convention so the file is directly usable with `flirt -applyxfm`.

### Output naming

- Resolved transform matrices: `{frame}_to_{output}.mat`
- Resampled images (with `--apply`): `{frame}_on_{output}{ext}` — kept only with `--image-dir` (the deliverable there); with `--input-4d` these are deleted once restacked into `{output}_resolved.nii.gz`
- Summary table: `{output}_summary.txt`
- Parsed arguments (provenance): `{output}_args.json`

### Pylint / style

All math modules use `# pylint: disable=invalid-name` because single-letter names (`R`, `T`, `J`, `e0`, etc.) are standard mathematical notation here. Black line length is 88.

### Tests

`test_rigid_math.py` contains the most important tests: finite-difference Jacobian checks for `compose_rigid_with_jacobians` (the `test_compose_jacobian_*_finite_difference` parametrized tests). These catch sign errors or chain-rule mistakes in the ported Fortran math. The FD tests pass even with an incorrect `E4hat` because they measure internal consistency — the integration test (convergence to RMS < 1e-6) is the reliable regression check for `E4hat` sign correctness.
