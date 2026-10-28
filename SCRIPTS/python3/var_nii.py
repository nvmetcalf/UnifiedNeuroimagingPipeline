#!/usr/bin/env python3

import argparse
import getpass
import json
import os
import re
import socket
import tempfile
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import nibabel as nib
import numpy as np


UNDEFINED_EPS = 1.0e-37
SIDECAR_VERSION = "1.0"


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def get_username() -> str:
    try:
        return getpass.getuser()
    except Exception:
        return "unknown"


def get_hostname() -> str:
    try:
        return socket.gethostname()
    except Exception:
        return "unknown"


def atomic_write_json(path: str, data: Dict[str, Any]) -> None:
    """
    Best-practice JSON write:
    write to a temp file in the same directory, then replace atomically.
    """
    out_dir = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp_path = tempfile.mkstemp(prefix=".tmp_sidecar_", suffix=".json", dir=out_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, sort_keys=False)
            f.write("\n")
        os.replace(tmp_path, path)
    except Exception:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except Exception:
            pass
        raise


def strip_grouping_chars(text: str) -> str:
    """
    Replace harmless grouping punctuation with spaces.
    Used only for tokenized 0/1 or x/+ formats.
    """
    return re.sub(r"[\[\]\{\},]", " ", text)


def parse_zero_one_format(text: str) -> Optional[str]:
    """
    Parse whitespace-delimited 0/1 tokens:
      0 -> x
      1 -> +
    Parentheses are not handled here because they may indicate grouped repetition.
    """
    stripped = text.strip()
    if not stripped:
        return None

    cleaned = strip_grouping_chars(stripped)
    tokens = re.split(r"\s+", cleaned.strip())
    tokens = [tok for tok in tokens if tok]

    if not tokens:
        return None

    if all(tok in ("0", "1") for tok in tokens):
        return "".join("+" if tok == "1" else "x" for tok in tokens)

    return None


def parse_whitespace_xplus_format(text: str) -> Optional[str]:
    """
    Parse whitespace-delimited x/+ tokens.
    Parentheses are not handled here because they may indicate grouped repetition.
    """
    stripped = text.strip()
    if not stripped:
        return None

    cleaned = strip_grouping_chars(stripped)
    tokens = re.split(r"\s+", cleaned.strip())
    tokens = [tok for tok in tokens if tok]

    if not tokens:
        return None

    if all(tok in ("x", "+") for tok in tokens):
        return "".join(tokens)

    return None


class CompactFormatParser:
    """
    Recursive parser for compact format strings supporting:
    - x
    - +
    - Nx
    - N+
    - N(...)
    - nested groups

    Example:
      5(4x371+)
    """

    def __init__(self, text: str):
        self.text = text
        self.n = len(text)
        self.i = 0

    def skip_ignorable(self):
        while self.i < self.n and (self.text[self.i].isspace() or self.text[self.i] in "[]{} ,"):
            self.i += 1

    def parse(self) -> str:
        result = self.parse_sequence(stop_at=None)
        self.skip_ignorable()
        if self.i != self.n:
            raise ValueError(f"Unexpected trailing text near: {self.text[self.i:]}")
        return result

    def parse_sequence(self, stop_at: Optional[str]) -> str:
        out = []

        while True:
            self.skip_ignorable()
            if self.i >= self.n:
                if stop_at is not None:
                    raise ValueError(f"Missing closing '{stop_at}'")
                break

            ch = self.text[self.i]

            if stop_at is not None and ch == stop_at:
                self.i += 1
                break

            if ch in ("x", "+"):
                out.append(ch)
                self.i += 1
                continue

            if ch.isdigit():
                count = self.parse_number()
                self.skip_ignorable()

                if self.i >= self.n:
                    raise ValueError("Count at end of format without target")

                ch2 = self.text[self.i]

                if ch2 in ("x", "+"):
                    out.append(ch2 * count)
                    self.i += 1
                    continue

                if ch2 == "(":
                    self.i += 1
                    group = self.parse_sequence(stop_at=")")
                    out.append(group * count)
                    continue

                raise ValueError(f"Invalid format character '{ch2}' after count")

            if ch == "(":
                self.i += 1
                group = self.parse_sequence(stop_at=")")
                out.append(group)
                continue

            raise ValueError(f"Invalid format character '{ch}' in compact format")

        return "".join(out)

    def parse_number(self) -> int:
        j = self.i
        while self.i < self.n and self.text[self.i].isdigit():
            self.i += 1
        return int(self.text[j:self.i])


def expand_compact_format(fmt: str) -> str:
    """
    Expand compact format syntax with support for grouped repetition.

    Examples:
      4x120+4x76+
      5(4x371+)
      2(3x10+2(1x2+))
    """
    parser = CompactFormatParser(fmt)
    return parser.parse()


def parse_format_text(text: str) -> str:
    """
    Accept format text in any of these forms:
    1. whitespace-delimited 0/1 tokens
    2. whitespace-delimited x/+ tokens
    3. compact syntax like 4x120+4x76+
    4. grouped compact syntax like 5(4x371+)
    5. literal x/+ string like xxxx++++
    """
    stripped = text.strip()
    if not stripped:
        raise ValueError("Empty format input")

    zero_one = parse_zero_one_format(stripped)
    if zero_one is not None:
        return zero_one

    xplus = parse_whitespace_xplus_format(stripped)
    if xplus is not None:
        return xplus

    return expand_compact_format(stripped)


def load_format(format_str: Optional[str], format_file: Optional[str], npts: int) -> Tuple[str, Optional[str], Optional[str]]:
    if format_file:
        with open(format_file, "r", encoding="utf-8") as f:
            raw = f.read()
        fmt = parse_format_text(raw)
        source = "file"
        source_value = format_file
    elif format_str:
        fmt = parse_format_text(format_str)
        source = "string"
        source_value = format_str
    else:
        return "", None, None

    if len(fmt) != npts:
        raise ValueError(
            f"Format frame count {len(fmt)} does not equal data length {npts}"
        )

    return fmt, source, source_value


def build_default_format(run_lengths: List[int], nf_anat: int) -> str:
    parts = []
    for nvol in run_lengths:
        nf_func = nvol - nf_anat
        if nf_func < 0:
            raise ValueError(
                f"Run with {nvol} frames has fewer frames than nf_anat={nf_anat}"
            )
        parts.append("x" * nf_anat + "+" * nf_func)
    return "".join(parts)


def mark_undefined(img: np.ndarray, defined_mask: np.ndarray, mode: str) -> np.ndarray:
    out = img.copy()
    bad = ~defined_mask
    if mode == "Z":
        out[bad] = 0.0
    elif mode == "E":
        out[bad] = UNDEFINED_EPS
    elif mode == "N":
        out[bad] = np.nan
    else:
        raise ValueError(f"Unknown undefined mode: {mode}")
    return out


def load_runs(paths: List[str]) -> Tuple[List[np.ndarray], List[nib.Nifti1Image], nib.Nifti1Image]:
    runs = []
    imgs = []
    ref_img = None
    ref_shape_3d = None

    for p in paths:
        img = nib.load(p)
        data = img.get_fdata(dtype=np.float32)

        if data.ndim == 3:
            data = data[..., np.newaxis]
        elif data.ndim != 4:
            raise ValueError(f"Input must be 3D or 4D NIfTI: {p}")

        if ref_img is None:
            ref_img = img
            ref_shape_3d = data.shape[:3]
        else:
            if data.shape[:3] != ref_shape_3d:
                raise ValueError(
                    f"Spatial shape mismatch: {p} has {data.shape[:3]}, expected {ref_shape_3d}"
                )

        runs.append(data)
        imgs.append(img)

    if ref_img is None:
        raise ValueError("No input runs provided")

    return runs, imgs, ref_img


def compute_defined_mask(frames_2d: np.ndarray) -> np.ndarray:
    has_nan = np.any(np.isnan(frames_2d), axis=1)
    has_eps = np.any(frames_2d == np.float32(UNDEFINED_EPS), axis=1)
    return ~(has_nan | has_eps)


def save_nifti(data: np.ndarray, ref_img: nib.Nifti1Image, out_path: str) -> None:
    hdr = ref_img.header.copy()
    out = nib.Nifti1Image(data.astype(np.float32), ref_img.affine, hdr)
    nib.save(out, out_path)


def strip_nifti_ext(path: str) -> str:
    if path.endswith(".nii.gz"):
        return path[:-7]
    if path.endswith(".nii"):
        return path[:-4]
    return path


def make_default_output_path(input_path: str, suffix: str) -> str:
    base = strip_nifti_ext(input_path)
    return base + suffix + ".nii.gz"


def make_user_output_path(output_arg: str, run_idx: Optional[int], nruns: int) -> str:
    """
    If multiple runs are being written, append _runN before extension.
    """
    if run_idx is None or nruns == 1:
        if output_arg.endswith(".nii") or output_arg.endswith(".nii.gz"):
            return output_arg
        return output_arg + ".nii.gz"

    base = strip_nifti_ext(output_arg)
    return f"{base}_run{run_idx + 1}.nii.gz"


def make_sidecar_path(nifti_path: str) -> str:
    return strip_nifti_ext(nifti_path) + ".json"


def safe_json_load(path: str) -> Dict[str, Any]:
    if not os.path.exists(path):
        return {}

    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, dict):
        raise ValueError(f"Sidecar JSON is not an object: {path}")

    return data


def append_sidecar_history(
    nifti_path: str,
    script_name: str,
    username: str,
    hostname: str,
    action: str,
    operation: str,
    input_files: List[str],
    parameters: Dict[str, Any],
    outputs: Dict[str, Any],
    format_info: Dict[str, Any],
    run_info: Dict[str, Any],
    notes: Optional[List[str]] = None,
) -> None:
    sidecar_path = make_sidecar_path(nifti_path)
    now = utc_now_iso()

    data = safe_json_load(sidecar_path)

    if not data:
        data = {
            "sidecar_version": SIDECAR_VERSION,
            "output_file": nifti_path,
            "created_utc": now,
            "history": [],
        }

    if "history" not in data or not isinstance(data["history"], list):
        data["history"] = []

    entry = {
        "timestamp_utc": now,
        "username": username,
        "hostname": hostname,
        "script": script_name,
        "action": action,
        "operation": operation,
        "inputs": input_files,
        "parameters": parameters,
        "format": format_info,
        "run_info": run_info,
        "outputs": outputs,
        "notes": notes or [],
    }

    data["output_file"] = nifti_path
    data["last_updated_utc"] = now
    data["history"].append(entry)

    atomic_write_json(sidecar_path, data)


def op_name_from_code(opr: str) -> str:
    return {
        "v": "variance",
        "s": "standard_deviation",
        "m": "demean_stack",
        "z": "defined_voxel_mask",
    }[opr]


def undefined_mode_name(mode: str) -> str:
    return {
        "Z": "zero",
        "E": "epsilon",
        "N": "nan",
    }[mode]


def main():
    parser = argparse.ArgumentParser(description="NIfTI replacement for var_4dfp")

    op_group = parser.add_mutually_exclusive_group()
    op_group.add_argument("-v", action="store_true", help="compute variance about mean")
    op_group.add_argument("-s", action="store_true", help="compute standard deviation about mean")
    op_group.add_argument("-m", action="store_true", help="remove mean volume from stack")
    op_group.add_argument("-z", action="store_true", help="output logical and of all defined voxels")

    parser.add_argument("-G", action="store_true", help="compute variance using global mean across runs")
    parser.add_argument("-n", type=int, default=0, help="number of pre-functional frames per run")
    parser.add_argument(
        "-f",
        type=str,
        default=None,
        help="format string: compact syntax, grouped compact syntax, literal x/+, whitespace x/+, or whitespace 0/1",
    )
    parser.add_argument(
        "-F",
        type=str,
        default=None,
        help="read format from file: compact syntax, grouped compact syntax, literal x/+, whitespace x/+, or whitespace 0/1",
    )
    parser.add_argument("--per-run", action="store_true", help="write one output per input run")
    parser.add_argument("-c", type=float, default=1.0, help="scale output values")
    parser.add_argument("-N", action="store_true", help="output undefined voxels as NaN")
    parser.add_argument("-Z", action="store_true", help="output undefined voxels as 0")
    parser.add_argument("-E", action="store_true", help="output undefined voxels as 1.e-37")
    parser.add_argument("-o", "--output", default=None, help="output filename or prefix")
    parser.add_argument("inputs", nargs="+", help="input NIfTI file(s), one or more runs")

    args = parser.parse_args()

    username = get_username()
    hostname = get_hostname()

    opr = "v"
    if args.s:
        opr = "s"
    elif args.m:
        opr = "m"
    elif args.z:
        opr = "z"

    nan_mode = "E"
    if args.N:
        nan_mode = "N"
    elif args.Z:
        nan_mode = "Z"
    elif args.E:
        nan_mode = "E"

    runs, imgs, ref_img = load_runs(args.inputs)
    run_lengths = [r.shape[3] for r in runs]
    total_frames = sum(run_lengths)
    spatial_shape = runs[0].shape[:3]
    nvox = int(np.prod(spatial_shape))
    nruns = len(runs)

    fmt, fmt_source, fmt_source_value = load_format(args.f, args.F, total_frames)
    if not fmt:
        fmt = build_default_format(run_lengths, args.n)
        fmt_source = "default_from_n"
        fmt_source_value = args.n

    counted_total = sum(ch == "+" for ch in fmt)
    skipped_total = total_frames - counted_total

    print(fmt)
    print(f"frames total={total_frames} counted={counted_total} skipped={skipped_total}")

    if counted_total == 0:
        raise ValueError("No frames selected for counting")

    run_means = []
    run_defined_masks = []
    run_variances = []
    global_sum = np.zeros(nvox, dtype=np.float64)
    global_defined_mask = np.ones(nvox, dtype=bool)

    frame_offset = 0
    counted_global = 0

    for run_idx, run in enumerate(runs):
        nvol = run.shape[3]
        run_2d = run.reshape(-1, nvol).astype(np.float32)
        run_fmt = fmt[frame_offset:frame_offset + nvol]
        frame_offset += nvol

        count_idx = np.array([i for i, ch in enumerate(run_fmt) if ch == "+"], dtype=int)
        if len(count_idx) == 0:
            raise ValueError(f"Run {run_idx + 1} has zero counted frames")

        counted = run_2d[:, count_idx]
        run_defined = compute_defined_mask(counted)
        run_defined_masks.append(run_defined)
        global_defined_mask &= run_defined

        run_mean = counted.mean(axis=1, dtype=np.float64)
        run_means.append(run_mean)

        global_sum += counted.sum(axis=1, dtype=np.float64)
        counted_global += counted.shape[1]

    global_mean = global_sum / counted_global
    print(f"undefined voxel count all-runs={np.count_nonzero(~global_defined_mask)}")

    if opr in ("v", "s"):
        frame_offset = 0

        for run_idx, run in enumerate(runs):
            nvol = run.shape[3]
            run_2d = run.reshape(-1, nvol).astype(np.float64)
            run_fmt = fmt[frame_offset:frame_offset + nvol]
            frame_offset += nvol

            count_idx = np.array([i for i, ch in enumerate(run_fmt) if ch == "+"], dtype=int)
            counted = run_2d[:, count_idx]

            if args.per_run:
                if args.G:
                    diff = counted - global_mean[:, None]
                    denom = counted.shape[1]
                else:
                    diff = counted - run_means[run_idx][:, None]
                    denom = counted.shape[1] - 1

                if denom <= 0:
                    raise ValueError(
                        f"Run {run_idx + 1} has non-positive variance denominator: {denom}"
                    )

                run_var = np.sum(diff * diff, axis=1) / denom
                run_variances.append(run_var)
            else:
                run_variances.append(None)

        if not args.per_run:
            var_sum = np.zeros(nvox, dtype=np.float64)
            frame_offset = 0

            for run_idx, run in enumerate(runs):
                nvol = run.shape[3]
                run_2d = run.reshape(-1, nvol).astype(np.float64)
                run_fmt = fmt[frame_offset:frame_offset + nvol]
                frame_offset += nvol

                count_idx = np.array([i for i, ch in enumerate(run_fmt) if ch == "+"], dtype=int)
                counted = run_2d[:, count_idx]

                if args.G:
                    diff = counted - global_mean[:, None]
                else:
                    diff = counted - run_means[run_idx][:, None]

                var_sum += np.sum(diff * diff, axis=1)

            if args.G:
                denom = counted_global
            else:
                denom = counted_total - len(runs)

            if denom <= 0:
                raise ValueError(
                    f"Non-positive variance denominator: {denom}. Need more counted frames."
                )

            combined_variance = var_sum / denom
        else:
            combined_variance = None
    else:
        combined_variance = None

    suffix = {
        "v": "_var",
        "s": "_sd1",
        "m": "_uout",
        "z": "_sam",
    }[opr]

    common_parameters = {
        "operation_code": opr,
        "operation_name": op_name_from_code(opr),
        "global_mean_flag": bool(args.G),
        "nf_anat": args.n,
        "per_run": bool(args.per_run),
        "scale_factor": args.c,
        "undefined_output_mode": undefined_mode_name(nan_mode),
        "undefined_eps_value": UNDEFINED_EPS,
    }

    common_format_info = {
        "expanded_format": fmt,
        "format_length": len(fmt),
        "counted_frames": counted_total,
        "skipped_frames": skipped_total,
        "format_source": fmt_source,
        "format_source_value": fmt_source_value,
    }

    script_name = os.path.basename(__file__) if "__file__" in globals() else "unknown_script"

    if args.per_run:
        for run_idx, run in enumerate(runs):
            if args.output:
                out_path = make_user_output_path(args.output, run_idx, nruns)
            else:
                out_path = make_default_output_path(args.inputs[run_idx], suffix)

            if opr == "z":
                out_data = run_defined_masks[run_idx].astype(np.float32).reshape(spatial_shape)
                save_nifti(out_data, imgs[run_idx], out_path)
                print(f"Wrote {out_path}")

            elif opr == "v":
                out_data = (run_variances[run_idx] * args.c).astype(np.float32)
                out_data = mark_undefined(out_data, run_defined_masks[run_idx], nan_mode)
                out_data = out_data.reshape(spatial_shape)
                save_nifti(out_data, imgs[run_idx], out_path)
                print(f"Wrote {out_path}")

            elif opr == "s":
                out_data = (np.sqrt(run_variances[run_idx]) * args.c).astype(np.float32)
                out_data = mark_undefined(out_data, run_defined_masks[run_idx], nan_mode)
                out_data = out_data.reshape(spatial_shape)
                save_nifti(out_data, imgs[run_idx], out_path)
                print(f"Wrote {out_path}")

            elif opr == "m":
                nvol = run.shape[3]
                run_2d = run.reshape(-1, nvol).astype(np.float32)
                centered = run_2d - run_means[run_idx][:, None].astype(np.float32)
                if args.c != 1.0:
                    centered *= np.float32(args.c)
                centered = mark_undefined(centered, run_defined_masks[run_idx], nan_mode)
                out_data = centered.reshape(*spatial_shape, nvol)
                save_nifti(out_data, imgs[run_idx], out_path)
                print(f"Wrote {out_path}")

            run_start = sum(run_lengths[:run_idx])
            run_end = sum(run_lengths[:run_idx + 1])
            run_fmt = common_format_info["expanded_format"][run_start:run_end]
            run_counted = sum(ch == "+" for ch in run_fmt)
            run_skipped = len(run_fmt) - run_counted

            append_sidecar_history(
                nifti_path=out_path,
                script_name=script_name,
                username=username,
                hostname=hostname,
                action="create_output",
                operation=op_name_from_code(opr),
                input_files=[args.inputs[run_idx]],
                parameters=common_parameters,
                outputs={
                    "nifti_file": out_path,
                    "sidecar_file": make_sidecar_path(out_path),
                    "shape": list(out_data.shape),
                    "dtype": str(out_data.dtype),
                },
                format_info={
                    **common_format_info,
                    "run_index": run_idx + 1,
                    "run_format": run_fmt,
                    "run_counted_frames": run_counted,
                    "run_skipped_frames": run_skipped,
                },
                run_info={
                    "run_index": run_idx + 1,
                    "num_runs_total": nruns,
                    "input_file": args.inputs[run_idx],
                    "input_frames": run.shape[3],
                    "spatial_shape": list(spatial_shape),
                    "undefined_voxel_count": int(np.count_nonzero(~run_defined_masks[run_idx])),
                },
                notes=[],
            )

    else:
        if args.output:
            out_path = make_user_output_path(args.output, None, nruns)
        else:
            out_path = make_default_output_path(args.inputs[0], suffix)

        if opr == "z":
            out_data = global_defined_mask.astype(np.float32).reshape(spatial_shape)
            save_nifti(out_data, ref_img, out_path)
            print(f"Wrote {out_path}")

        elif opr == "v":
            out_data = (combined_variance * args.c).astype(np.float32)
            out_data = mark_undefined(out_data, global_defined_mask, nan_mode)
            out_data = out_data.reshape(spatial_shape)
            save_nifti(out_data, ref_img, out_path)
            print(f"Wrote {out_path}")

        elif opr == "s":
            out_data = (np.sqrt(combined_variance) * args.c).astype(np.float32)
            out_data = mark_undefined(out_data, global_defined_mask, nan_mode)
            out_data = out_data.reshape(spatial_shape)
            save_nifti(out_data, ref_img, out_path)
            print(f"Wrote {out_path}")

        elif opr == "m":
            out_runs = []
            for run_idx, run in enumerate(runs):
                nvol = run.shape[3]
                run_2d = run.reshape(-1, nvol).astype(np.float32)
                centered = run_2d - run_means[run_idx][:, None].astype(np.float32)
                if args.c != 1.0:
                    centered *= np.float32(args.c)
                centered = mark_undefined(centered, global_defined_mask, nan_mode)
                out_runs.append(centered.reshape(*spatial_shape, nvol))

            if len(out_runs) == 1:
                out_data = out_runs[0]
            else:
                out_data = np.concatenate(out_runs, axis=3)

            save_nifti(out_data, ref_img, out_path)
            print(f"Wrote {out_path}")

        append_sidecar_history(
            nifti_path=out_path,
            script_name=script_name,
            username=username,
            hostname=hostname,
            action="create_output",
            operation=op_name_from_code(opr),
            input_files=args.inputs,
            parameters=common_parameters,
            outputs={
                "nifti_file": out_path,
                "sidecar_file": make_sidecar_path(out_path),
                "shape": list(out_data.shape),
                "dtype": str(out_data.dtype),
            },
            format_info=common_format_info,
            run_info={
                "num_runs_total": nruns,
                "input_files": args.inputs,
                "run_lengths": run_lengths,
                "total_frames": total_frames,
                "spatial_shape": list(spatial_shape),
                "undefined_voxel_count": int(np.count_nonzero(~global_defined_mask)),
            },
            notes=[],
        )


if __name__ == "__main__":
    main()
