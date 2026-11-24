"""
QC helpers: collect the small text metrics P2's -QC module writes, list the
QC images (movement-plot PDFs etc.), and (when numpy is importable) render
axial montages of NIfTI volumes as PNG without any other dependency.
"""
import gzip
import io
import os
import re
import struct
import zlib

try:
    import numpy as np
except Exception:      # pragma: no cover
    np = None

IMAGE_EXT = (".pdf", ".png", ".jpg", ".jpeg", ".gif", ".svg")

# Human-readable names for the summary metrics (used by the QC tab, the drawer and CSV exports).
# {fd} is replaced by the study's FD threshold when known.
LABELS = [
    ("sid", "Subject_Session", "InProcess folder name"),
    ("runs", "BOLD runs", "number of BOLD runs with FD thresholding output"),
    ("good_frames", "Frames kept (FD < {fd} mm)", "frames surviving motion censoring, all runs"),
    ("bad_frames", "Frames censored (FD >= {fd} mm)", "frames removed by motion censoring, all runs"),
    ("pct_good", "% frames kept", "100 * kept / (kept + censored)"),
    ("minutes_good", "Minutes of data kept", "sum of SecondsRemaining over runs / 60"),
    ("mean_rms", "Mean RMS head motion (mm/frame)", "mean over runs of total rms velocity at radius 50 mm (RMS_movements.txt)"),
    ("max_rms", "Max run RMS head motion (mm/frame)", "worst run"),
    ("sd_pre", "Within-brain SD, atlas-aligned BOLD before denoising", "fMRI_denoising.txt: 'Atlas Aligned resting state fMRI within brain sd'"),
    ("sd_post", "Within-brain SD, denoised BOLD", "fMRI_denoising.txt: 'Denoised resting state fMRI within brain sd'"),
]


def labels(fd_threshold=None, extra_thresholds=()):
    fd = str(fd_threshold) if fd_threshold not in (None, "") else "thr"
    out = [(k, lab.replace("{fd}", fd), hlp) for k, lab, hlp in LABELS]
    for t in extra_thresholds or ():
        tag = _thr_tag(t)
        out += [(f"kept_fd{tag}", f"Frames kept (FD < {t} mm)", f"recomputed from per-frame FD traces at {t} mm (first `skip` frames excluded)"),
                (f"pct_fd{tag}", f"% frames kept (FD < {t} mm)", f"recomputed at {t} mm"),
                (f"min_fd{tag}", f"Minutes kept (FD < {t} mm)", f"frames kept at {t} mm x TR / 60")]
    return out


def _thr_tag(t):
    return str(t).replace(".", "p")


def _params_ints(sdir, sid):
    """skip (pre-steady-state frames) and BOLD_TR from the params file."""
    skip, tr = 0, None
    try:
        with open(os.path.join(sdir, f"{sid}.params"), errors="replace") as fh:
            for line in fh:
                m = re.match(r"^\s*@?\s*set\s+BOLD_TR\s*=\s*([0-9.]+)|^\s*@\s*skip\s*=\s*(\d+)", line)
                if m:
                    if m.group(1):
                        tr = float(m.group(1))
                    if m.group(2):
                        skip = int(m.group(2))
    except OSError:
        pass
    return skip, tr


def fd_traces(sdir):
    """{run_number: [fd per frame]} from Functional/Movement/bold<N>_upck_faln_dbnd_xr3d.ddat.fd"""
    out = {}
    d = os.path.join(sdir, "Functional", "Movement")
    try:
        names = os.listdir(d)
    except OSError:
        return out
    for n in names:
        m = re.match(r"^bold(\d+)_upck_faln_dbnd_xr3d\.ddat\.fd$", n)
        if not m:
            continue
        vals = []
        with open(os.path.join(d, n), errors="replace") as fh:
            for line in fh:
                try:
                    vals.append(float(line.strip()))
                except ValueError:
                    pass
        out[int(m.group(1))] = vals
    return out


def frames_kept_at(sdir, sid, thresholds):
    """{thr: {'runs': [{run, kept, total, pct}], 'kept', 'total', 'pct', 'minutes'}} using the
    same rule as the pipeline's .sfbin: frame kept if index >= skip and FD < thr."""
    traces = fd_traces(sdir)
    if not traces:
        return {}
    skip, tr = _params_ints(sdir, sid)
    out = {}
    for thr in thresholds:
        runs, kept_all, tot_all = [], 0, 0
        for run in sorted(traces):
            fd = traces[run]
            kept = sum(1 for i, v in enumerate(fd) if i >= skip and v < thr)
            runs.append({"run": run, "kept": kept, "total": len(fd), "pct": round(100.0 * kept / max(1, len(fd)), 1)})
            kept_all += kept
            tot_all += len(fd)
        out[thr] = {"runs": runs, "kept": kept_all, "total": tot_all, "pct": round(100.0 * kept_all / max(1, tot_all), 1),
                    "minutes": round(kept_all * tr / 60.0, 1) if tr else None, "tr": tr, "skip": skip}
    return out


def _read(path, limit=200000):
    try:
        with open(path, errors="replace") as fh:
            return fh.read(limit)
    except OSError:
        return ""


def subject_metrics(sdir, sid, extra_thresholds=()):
    """Return {'fd_runs': [...], 'rms': [...], 'denoise': {...}, 'pet': [...], 'summary': {...}}"""
    qc = os.path.join(sdir, "QC")
    out = {"fd_runs": [], "rms": [], "denoise": {}, "pet": [], "summary": {}, "files": [], "fd_extra": {}}
    # FD frame counts --------------------------------------------------------
    txt = _read(os.path.join(qc, f"{sid}_BOLD_FD_Thresholding_frame_count.txt"))
    for line in txt.splitlines():
        f = re.split(r"[\t,]+", line.strip())
        if len(f) >= 5 and f[0].isdigit():
            try:
                out["fd_runs"].append({"run": int(f[0]), "bad": int(f[1]), "good": int(f[2]),
                                       "pct": float(f[3]), "sec": float(f[4])})
            except ValueError:
                pass
    # RMS movement -------------------------------------------------------------
    for line in _read(os.path.join(qc, "RMS_movements.txt")).splitlines():
        m = re.search(r"([0-9.]+)\s*mm/frame", line)
        if m:
            out["rms"].append(float(m.group(1)))
    # denoising ----------------------------------------------------------------
    for line in _read(os.path.join(qc, "fMRI_denoising.txt")).splitlines():
        m = re.match(r"(.*?)\s*sd:\s*([0-9.eE+-]+)", line)
        if m:
            key = "pre" if "Atlas" in m.group(1) or "pre" in m.group(1).lower() else "post"
            out["denoise"][key] = float(m.group(2))
    # PET ------------------------------------------------------------------------
    pet = _read(os.path.join(qc, "PET_QC.csv")).splitlines()
    if len(pet) > 1:
        hdr = [h.strip() for h in pet[0].split(",")]
        for row in pet[1:]:
            vals = [v.strip() for v in row.split(",")]
            if any(vals):
                out["pet"].append(dict(zip(hdr, vals)))
    # summary numbers ------------------------------------------------------------
    if out["fd_runs"]:
        good = sum(r["good"] for r in out["fd_runs"])
        bad = sum(r["bad"] for r in out["fd_runs"])
        out["summary"] = {"runs": len(out["fd_runs"]), "good_frames": good, "bad_frames": bad,
                          "pct_good": round(100.0 * good / max(1, good + bad), 1),
                          "minutes_good": round(sum(r["sec"] for r in out["fd_runs"]) / 60.0, 1)}
    if out["rms"]:
        out["summary"]["mean_rms"] = round(sum(out["rms"]) / len(out["rms"]), 4)
        out["summary"]["max_rms"] = round(max(out["rms"]), 4)
    if out["denoise"]:
        out["summary"].update({"sd_pre": out["denoise"].get("pre"), "sd_post": out["denoise"].get("post")})
    if extra_thresholds:
        fx = frames_kept_at(sdir, sid, extra_thresholds)
        out["fd_extra"] = {str(t): v for t, v in fx.items()}
        for t, v in fx.items():
            tag = _thr_tag(t)
            out["summary"][f"kept_fd{tag}"] = v["kept"]
            out["summary"][f"pct_fd{tag}"] = v["pct"]
            out["summary"][f"min_fd{tag}"] = v["minutes"]
    # files ----------------------------------------------------------------------
    try:
        for e in sorted(os.scandir(qc), key=lambda e: e.name):
            if e.is_file():
                low = e.name.lower()
                kind = "image" if low.endswith(IMAGE_EXT) else ("nifti" if ".nii" in low else
                                                                  "text" if low.endswith((".txt", ".csv", ".dat")) else "other")
                out["files"].append({"name": e.name, "path": e.path, "kind": kind, "size": e.stat().st_size})
    except OSError:
        pass
    return out


def candidate_volumes(sdir, sid):
    """NIfTI volumes worth eyeballing, in display order."""
    cands = [
        ("tmean (BOLD mean, atlas)", os.path.join(sdir, "QC", "tmean.nii.gz")),
        ("tSNR", os.path.join(sdir, "QC", "tSNR.nii.gz")),
        ("tstd", os.path.join(sdir, "QC", "tstd.nii.gz")),
        ("pre-denoising SD", os.path.join(sdir, "QC", f"{sid}_pre-denoising_SD.nii.gz")),
        ("post-denoising SD", os.path.join(sdir, "QC", f"{sid}_post-denoising_SD.nii.gz")),
        ("used voxels (fnirt)", os.path.join(sdir, "Masks", f"{sid}_used_voxels_fnirt.nii.gz")),
    ]
    out = [{"label": l, "path": p} for l, p in cands if os.path.isfile(p)]
    # anatomical volumes
    for sub in ("T1", "T2", "FLAIR", "BOLD_ref"):
        d = os.path.join(sdir, "Anatomical", "Volume", sub)
        try:
            files = sorted(f for f in os.listdir(d) if ".nii" in f and "atl" in f)
            files = files[:3] or sorted(f for f in os.listdir(d) if ".nii" in f)[:2]
            for f in files:
                out.append({"label": f"{sub}/{f}", "path": os.path.join(d, f)})
        except OSError:
            pass
    return out


# ---------------------------------------------------------------------------
# minimal NIfTI-1/2 reader (3D or first frame of 4D) and PNG writer
# ---------------------------------------------------------------------------
_DTYPES = {2: "u1", 4: "i2", 8: "i4", 16: "f4", 64: "f8", 256: "i1", 512: "u2", 768: "u4", 1024: "i8", 1280: "u8"}


def read_nifti(path):
    if np is None:
        raise RuntimeError("numpy not available")
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as fh:
        hdr = fh.read(540)
        if len(hdr) < 348:
            raise ValueError("short header")
        sizeof = struct.unpack("<i", hdr[:4])[0]
        endian = "<"
        if sizeof not in (348, 540):
            endian = ">"
            sizeof = struct.unpack(">i", hdr[:4])[0]
        if sizeof == 348:      # NIfTI-1
            dim = struct.unpack(endian + "8h", hdr[40:56])
            datatype = struct.unpack(endian + "h", hdr[70:72])[0]
            pixdim = struct.unpack(endian + "8f", hdr[76:108])
            vox_offset = int(struct.unpack(endian + "f", hdr[108:112])[0])
            scl_slope, scl_inter = struct.unpack(endian + "2f", hdr[112:120])
        elif sizeof == 540:    # NIfTI-2
            datatype = struct.unpack(endian + "h", hdr[12:14])[0]
            dim = struct.unpack(endian + "8q", hdr[16:80])
            pixdim = struct.unpack(endian + "8d", hdr[104:168])
            vox_offset = struct.unpack(endian + "q", hdr[168:176])[0]
            scl_slope, scl_inter = struct.unpack(endian + "2d", hdr[176:192])
        else:
            raise ValueError("not a NIfTI file")
        ndim = dim[0]
        shape = [max(1, int(x)) for x in dim[1:1 + max(3, ndim)]][:4]
        dt = np.dtype(endian + _DTYPES.get(datatype, "f4"))
        nvox3 = shape[0] * shape[1] * shape[2]
        fh.seek(vox_offset)
        buf = fh.read(nvox3 * dt.itemsize)   # first frame only
        data = np.frombuffer(buf, dtype=dt, count=nvox3).reshape(shape[2], shape[1], shape[0]).T.astype("f4")
        if scl_slope not in (0, 1) or scl_inter != 0:
            data = data * (scl_slope or 1) + scl_inter
        return data, pixdim[1:4], shape


def _png(gray_u8):
    """Encode a 2-D uint8 array as grayscale PNG bytes (pure Python)."""
    h, w = gray_u8.shape
    raw = b"".join(b"\x00" + gray_u8[y].tobytes() for y in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def montage_png(path, n_slices=20, axis=2, max_size=1400):
    """Axial montage as PNG bytes.  Percentile-scaled, background black."""
    data, pix, shape = read_nifti(path)
    if data.ndim != 3:
        raise ValueError("need 3D")
    nz = data.shape[axis]
    n = min(n_slices, nz)
    # skip empty edges
    idx = np.linspace(int(nz * 0.08), int(nz * 0.92) - 1, n).astype(int)
    finite = data[np.isfinite(data)]
    nz_vals = finite[finite != 0]
    lo, hi = (np.percentile(nz_vals, [1, 99]) if nz_vals.size > 100 else (0.0, 1.0))
    if hi <= lo:
        hi = lo + 1
    cols = int(np.ceil(np.sqrt(n * 1.6)))
    rows = int(np.ceil(n / cols))
    sl = [np.take(data, i, axis=axis) for i in idx]
    # orient: rows = y (anterior up), cols = x
    sl = [np.flipud(s.T) if axis == 2 else np.flipud(s.T) for s in sl]
    sh, sw = sl[0].shape
    # aspect from pixdim
    scale = 1.0
    canvas = np.zeros((rows * sh, cols * sw), dtype="f4")
    for k, s in enumerate(sl):
        r, c = divmod(k, cols)
        canvas[r * sh:(r + 1) * sh, c * sw:(c + 1) * sw] = s
    img = np.clip((canvas - lo) / (hi - lo), 0, 1)
    img = np.nan_to_num(img)
    # upscale small images by integer factor
    f = max(1, int(min(max_size / max(img.shape), 4)))
    if f > 1:
        img = np.repeat(np.repeat(img, f, axis=0), f, axis=1)
    return _png((img * 255).astype("u1"))
