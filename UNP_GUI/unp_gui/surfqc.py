"""
Surface QC renderings and the HTML QC report.

Renders a session's surface QC metrics (SD and tSNR .func.gii written by
P2 -QC) onto its inflated 32k surfaces with Connectome Workbench, exactly the
way the lab's SurfRegQC scripts do: take templates/SurfaceSD_template.scene,
substitute subject / atlas / mesh / metric file, and run

    wb_command -show-scene <scene> 1 <png> <width> <height>

Outputs go next to the metrics: InProcess/<sid>/QC/<sid>_<metric>_surface.png
"""
import base64
import datetime as _dt
import html
import os
import re
import shutil
import subprocess
import threading
import time

from . import config as _cfg
from . import tm as _tm
from . import qc as _qc

TEMPLATE = os.path.join(_cfg.GUI_ROOT, "templates", "SurfaceSD_template.scene")

# metric key -> (label, func.gii prefix pattern ({sid} substituted), fixed palette range (min, max))
METRICS = {
    "tSNR": ("Temporal SNR of the BOLD signal (tSNR_fnirt)", "tSNR_fnirt.", (0.0, 130.0)),
    "SD": ("Temporal SD of the BOLD signal", "{sid}_SD.", (0.0, 12.0)),
}
PALETTE = "ROY-BIG-BL"


def range_text(metric):
    lo, hi = METRICS[metric][2]
    return f"Fixed palette {PALETTE}, {lo:g} to {hi:g} (positive values only; values above {hi:g} saturate)"

_T_PATH = "/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls/FCS_040_AMC"
_T_ATLAS = "MNI152_T1_1mm_t88"
_T_SID = "FCS_040_AMC"


def find_wb_command(cfg):
    for cand in (shutil.which("wb_command"),
                 os.path.join(cfg.pp_scripts, "workbench", "rhel", "bin_rh_linux64", "wb_command"),
                 os.path.join(cfg.pp_scripts, "workbench", "debian", "bin_linux64", "wb_command")):
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def study_atlas_mesh(cfg, project):
    """(atlas folder prefix, mesh) from Study.cfg: target basename and LowResMesh."""
    from . import pipeline
    atlas, mesh = "MNI152_T1_1mm", "32"
    for e in pipeline.parse_study_cfg(os.path.join(cfg.projects_root, project, "Study.cfg")).get("entries", []):
        if e["name"] == "target" and e["value"]:
            atlas = os.path.basename(e["value"].strip('"'))
        if e["name"] == "LowResMesh" and e["value"]:
            mesh = e["value"].strip()
    return atlas, mesh


def metric_files(sdir, sid, mesh):
    """{metric: (L.gii, R.gii)} for the metrics that exist."""
    out = {}
    for key, (_, pat, _rng) in METRICS.items():
        pre = pat.format(sid=sid)
        L = os.path.join(sdir, "QC", f"{pre}L.{mesh}k.func.gii")
        R = os.path.join(sdir, "QC", f"{pre}R.{mesh}k.func.gii")
        if os.path.isfile(L) and os.path.isfile(R):
            out[key] = (L, R)
    return out


def surfaces_ok(sdir, sid, atlas, mesh):
    d = os.path.join(sdir, "Anatomical", "Surface", f"{atlas}_{mesh}k")
    return all(os.path.isfile(os.path.join(d, f"{sid}.{h}.inflated.{mesh}k_fs_LR.surf.gii")) for h in ("L", "R"))


def png_path(sdir, sid, metric):
    return os.path.join(sdir, "QC", f"{sid}_{metric}_surface.png")


def make_scene(sdir, sid, atlas, mesh, name, metric_prefix, lo, hi, palette=PALETTE, interpolate=True):
    """Scene showing the L/R metric pair QC/<metric_prefix>{L,R}.<mesh>k.func.gii with a fixed range."""
    with open(TEMPLATE, errors="replace") as fh:
        text = fh.read()
    text = text.replace(_T_PATH, sdir)
    text = text.replace(_T_ATLAS, atlas)
    text = text.replace("32k", f"{mesh}k")
    text = text.replace(f"{_T_SID}_SD.", metric_prefix)   # metric file (before the generic sid swap)
    text = text.replace(_T_SID, sid)
    text = text.replace("<![CDATA[SurfaceSD]]>", f"<![CDATA[{name}]]>")
    # fixed palette range instead of auto-scale (UserScaleValues = negMax negMin posMin posMax)
    text = text.replace("<ScaleMode>MODE_AUTO_SCALE</ScaleMode>", "<ScaleMode>MODE_USER_SCALE</ScaleMode>")
    text = re.sub(r"<UserScaleValues>[^<]*</UserScaleValues>",
                  f"<UserScaleValues>{-hi:.6f} {-lo if lo else 0.0:.6f} {lo:.6f} {hi:.6f}</UserScaleValues>", text)
    text = text.replace(f"<PaletteName>{PALETTE}</PaletteName>", f"<PaletteName>{palette}</PaletteName>")
    text = re.sub(r"<InterpolatePalette>[^<]*</InterpolatePalette>",
                  f"<InterpolatePalette>{'true' if interpolate else 'false'}</InterpolatePalette>", text)
    text = text.replace("<DisplayNegativeData>true</DisplayNegativeData>", "<DisplayNegativeData>false</DisplayNegativeData>")
    text = text.replace("<DisplayPositiveData>false</DisplayPositiveData>", "<DisplayPositiveData>true</DisplayPositiveData>")
    scene = os.path.join(sdir, "QC", f".unpgui_{name}.scene")
    with open(scene, "w") as fh:
        fh.write(text)
    return scene


def _wb_env():
    env = dict(os.environ)
    if not env.get("DISPLAY"):
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
    return env


def _wb(wb, args, timeout=300):
    p = subprocess.run([wb] + args, capture_output=True, text=True, timeout=timeout, env=_wb_env())
    if p.returncode != 0:
        raise RuntimeError(f"wb_command {args[0]} failed: {(p.stderr or p.stdout).strip()[-600:]}")
    return p


def render_pair(cfg, sdir, sid, atlas, mesh, name, make_inputs, lo, hi, png, palette=PALETTE,
                interpolate=True, width=1600, height=900, keep_scene=False, timeout=600):
    """Generic renderer.  make_inputs(wb, L_path, R_path) must write the two metric files; they get
    the fixed palette stamped in, are shown via the template scene, then removed."""
    wb = find_wb_command(cfg)
    if not wb:
        raise RuntimeError("wb_command not found (expected in SCRIPTS/workbench/rhel/bin_rh_linux64)")
    qcdir = os.path.join(sdir, "QC")
    os.makedirs(qcdir, exist_ok=True)
    tmp_pre = f".unpgui_{name}."
    L = os.path.join(qcdir, f"{tmp_pre}L.{mesh}k.func.gii")
    R = os.path.join(qcdir, f"{tmp_pre}R.{mesh}k.func.gii")
    scene = None
    try:
        make_inputs(wb, L, R)
        for f in (L, R):
            _wb(wb, ["-metric-palette", f, "MODE_USER_SCALE", "-pos-user", f"{lo:g}", f"{hi:g}",
                     "-palette-name", palette, "-interpolate", "true" if interpolate else "false",
                     "-disp-pos", "true", "-disp-neg", "false", "-disp-zero", "false"], timeout=120)
        scene = make_scene(sdir, sid, atlas, mesh, name, tmp_pre, lo, hi, palette, interpolate)
        p = subprocess.run([wb, "-show-scene", scene, "1", png, str(width), str(height)],
                           capture_output=True, text=True, timeout=timeout, env=_wb_env(), cwd=qcdir)
        if p.returncode != 0 or not os.path.isfile(png):
            raise RuntimeError(f"wb_command -show-scene failed (rc={p.returncode}): {(p.stderr or p.stdout).strip()[-800:]}")
    finally:
        for t in (L, R) + ((scene,) if scene and not keep_scene else ()):
            try:
                os.remove(t)
            except OSError:
                pass
    with open(png + ".txt", "w") as fh:
        fh.write(f"{name}\t{lo:g}\t{hi:g}\t{palette}\t{_dt.datetime.now():%Y-%m-%d %H:%M}\n")
    _cfg.fix_group(png, cfg.get("study_group"))
    _cfg.fix_group(png + ".txt", cfg.get("study_group"))
    return png


def render(cfg, sdir, sid, atlas, mesh, metric, width=1600, height=900, keep_scene=False, timeout=600):
    """QC metric (SD / tSNR) .func.gii pair -> QC/<sid>_<metric>_surface.png"""
    lo, hi = METRICS[metric][2]
    src_pre = METRICS[metric][1].format(sid=sid)
    qcdir = os.path.join(sdir, "QC")

    def make_inputs(wb, L, R):
        shutil.copyfile(os.path.join(qcdir, f"{src_pre}L.{mesh}k.func.gii"), L)
        shutil.copyfile(os.path.join(qcdir, f"{src_pre}R.{mesh}k.func.gii"), R)
    return render_pair(cfg, sdir, sid, atlas, mesh, f"{sid}_{metric}", make_inputs, lo, hi,
                       png_path(sdir, sid, metric), width=width, height=height, keep_scene=keep_scene, timeout=timeout)


TM_PALETTE = "power_surf"


def tm_png_path(session_dir, session, tm_atlas):
    """QC/<session>_TM_<tag>_surface.png (HCP18 for the insulafix atlas); an existing PNG with the old long name is used if
    there is no new one."""
    new = os.path.join(session_dir, "QC", f"{session}_TM_{_tm.atlas_tag(tm_atlas)}_surface.png")
    old = os.path.join(session_dir, "QC", f"{session}_TM_{tm_atlas}_surface.png")
    return old if (not os.path.isfile(new) and os.path.isfile(old)) else new


def render_tm(cfg, session_dir, session, tm_atlas, clean_dscalar, atlas="MNI152_T1_1mm", mesh="32",
              width=1600, height=900, name=None):
    """Template-matching network map (cleaned assignments dscalar) on the inflated surfaces,
    power_surf palette 1-18 as written by run_template_matching_v2 (SCAN stored as 1.5).
    session = whose surfaces; name = the output name (session + optional suffix), used for the PNG name."""
    name = name or session
    def make_inputs(wb, L, R):
        _wb(wb, ["-cifti-separate", clean_dscalar, "COLUMN", "-metric", "CORTEX_LEFT", L, "-metric", "CORTEX_RIGHT", R])
    return render_pair(cfg, session_dir, session, atlas, mesh, f"{name}_TM_{_tm.atlas_tag(tm_atlas)}", make_inputs, 1, 18,
                       tm_png_path(session_dir, name, tm_atlas), palette=TM_PALETTE, interpolate=True,
                       width=width, height=height)


def _range_matches(png, metric):
    """True if png was rendered with the current fixed range (sidecar <png>.txt)."""
    try:
        f = open(png + ".txt").read().split("\t")
        lo, hi = METRICS[metric][2]
        return float(f[1]) == lo and float(f[2]) == hi
    except (OSError, IndexError, ValueError):
        return False


# ---------------------------------------------------------------------------
# background render jobs
# ---------------------------------------------------------------------------
class RenderJob:
    def __init__(self, cfg, project, sids, metrics, width, height, only_missing=True):
        self.cfg, self.project = cfg, project
        self.sids, self.metrics = sids, metrics
        self.width, self.height, self.only_missing = width, height, only_missing
        self.started = time.time()
        self.done = False
        self.total = 0
        self.completed = 0
        self.results = []      # {sid, metric, ok, png|error}
        self.current = ""
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        atlas, mesh = study_atlas_mesh(self.cfg, self.project)
        tasks = []
        for sid in self.sids:
            sdir = os.path.join(self.cfg.projects_root, self.project, "InProcess", sid)
            have = metric_files(sdir, sid, mesh)
            for m in self.metrics:
                if m not in have:
                    self.results.append({"sid": sid, "metric": m, "ok": False, "error": "metric .func.gii not found (run -QC)"})
                    continue
                if not surfaces_ok(sdir, sid, atlas, mesh):
                    self.results.append({"sid": sid, "metric": m, "ok": False,
                                         "error": f"inflated surfaces not found in Anatomical/Surface/{atlas}_{mesh}k"})
                    continue
                if self.only_missing and os.path.isfile(png_path(sdir, sid, m)) and _range_matches(png_path(sdir, sid, m), m):
                    self.results.append({"sid": sid, "metric": m, "ok": True, "png": png_path(sdir, sid, m), "skipped": True})
                    continue
                tasks.append((sid, sdir, m))
        self.total = len(tasks)
        for sid, sdir, m in tasks:
            self.current = f"{sid} {m}"
            try:
                png = render(self.cfg, sdir, sid, atlas, mesh, m, self.width, self.height)
                self.results.append({"sid": sid, "metric": m, "ok": True, "png": png})
            except Exception as e:      # noqa: BLE001
                self.results.append({"sid": sid, "metric": m, "ok": False, "error": str(e)})
            self.completed += 1
        self.current = ""
        self.done = True

    def status(self):
        return {"done": self.done, "total": self.total, "completed": self.completed, "current": self.current,
                "ok": sum(1 for r in self.results if r["ok"] and not r.get("skipped")),
                "skipped": sum(1 for r in self.results if r.get("skipped")),
                "failed": [r for r in self.results if not r["ok"]][:50],
                "elapsed": int(time.time() - self.started)}


# ---------------------------------------------------------------------------
# HTML report
# ---------------------------------------------------------------------------
def _img_tag(path, alt):
    try:
        with open(path, "rb") as fh:
            b = base64.b64encode(fh.read()).decode()
        return f'<img alt="{html.escape(alt)}" src="data:image/png;base64,{b}">'
    except OSError:
        return f'<div class="missing">{html.escape(alt)}: not rendered</div>'


def build_report(cfg, project, sids, qc_rows, fd_threshold, embed=True, extra_thresholds=()):
    """Write Projects/<project>/Analysis/QC_report_<stamp>.html; return path."""
    labs = _qc.labels(fd_threshold, extra_thresholds)
    rows_by = {r["sid"]: r for r in qc_rows}
    atlas, mesh = study_atlas_mesh(cfg, project)
    stamp = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    css = """
    body{font:14px/1.4 system-ui,sans-serif;margin:24px;color:#1d2330;background:#fff}
    h1{font-size:22px;margin:0 0 4px} h2{font-size:17px;margin:28px 0 8px;border-bottom:1px solid #ddd;padding-bottom:4px}
    .muted{color:#666} table{border-collapse:collapse;font-size:13px;margin:10px 0 20px}
    th,td{border:1px solid #ddd;padding:4px 8px;text-align:right} th{background:#f4f5f7;text-align:center;font-weight:600;max-width:140px}
    td:first-child,th:first-child{text-align:left} tr.bad td{background:#fff0ee}
    .imgs{display:flex;flex-wrap:wrap;gap:12px} .imgs figure{margin:0;flex:1 1 440px;max-width:48%}
    .imgs img{width:100%;border:1px solid #ddd;border-radius:4px;background:#000} figcaption{font-size:12px;color:#444;margin-top:3px}
    .missing{padding:30px;border:1px dashed #bbb;color:#888;text-align:center;border-radius:4px}
    .kv span{display:inline-block;margin-right:18px}
    .scale{display:flex;align-items:center;gap:6px;font-size:11px;color:#444;margin-top:4px}
    .scale i{display:block;height:10px;flex:0 0 220px;border:1px solid #bbb;
             background:linear-gradient(90deg,#8b0000,#ff0000 25%,#ff8c00 55%,#ffd700 80%,#ffff00)}
    @media print{.imgs figure{max-width:48%} h2{page-break-before:always}}
    """
    out = [f"<!doctype html><html><head><meta charset='utf-8'><title>QC report {html.escape(project)}</title><style>{css}</style></head><body>",
           f"<h1>UNP QC report — {html.escape(project)}</h1>",
           f"<div class='muted'>Generated {stamp} · {len(sids)} session(s) · atlas {html.escape(atlas)} · {mesh}k mesh · "
           f"FD threshold {html.escape(str(fd_threshold))} mm · PROJECTS_HOME {html.escape(cfg.projects_home)}</div>"]
    # summary table
    out.append("<h2>Summary</h2><table><tr>" + "".join(f"<th title='{html.escape(h)}'>{html.escape(l)}</th>" for _, l, h in labs) + "</tr>")
    for sid in sids:
        r = rows_by.get(sid, {"sid": sid})
        bad = (r.get("pct_good") is not None and r["pct_good"] < 70) or (r.get("mean_rms") is not None and r["mean_rms"] > 0.3)
        out.append(f"<tr class='{'bad' if bad else ''}'>" + "".join(
            f"<td>{html.escape(str(r.get(k, '') if r.get(k) is not None else ''))}</td>" for k, _, _ in labs) + "</tr>")
    out.append("</table>")
    # per-session sections
    for sid in sids:
        sdir = os.path.join(cfg.projects_root, project, "InProcess", sid)
        r = rows_by.get(sid, {})
        out.append(f"<h2>{html.escape(sid)}</h2><div class='kv muted'>" + "".join(
            f"<span>{html.escape(l)}: <b>{html.escape(str(r.get(k)))}</b></span>" for k, l, _ in labs[1:] if r.get(k) is not None) + "</div>")
        if r.get("fd_runs"):
            fx = r.get("fd_extra") or {}
            ext_hdr = "".join(f"<th>% kept (FD &lt; {t} mm)</th>" for t in fx)
            def ext_cells(i):
                return "".join(f"<td>{(fx[t]['runs'][i]['pct'] if i < len(fx[t]['runs']) else '')}</td>" for t in fx)
            out.append(f"<table><tr><th>Run</th><th>Frames censored (FD &ge; {html.escape(str(fd_threshold))} mm)</th><th>Frames kept</th><th>% frames kept</th><th>Seconds kept</th><th>RMS head motion (mm/frame)</th>{ext_hdr}</tr>" +
                       "".join(f"<tr><td>{x['run']}</td><td>{x['bad']}</td><td>{x['good']}</td><td>{x['pct']}</td><td>{x['sec']}</td>"
                               f"<td>{(r.get('rms') or [''] * 99)[i] if i < len(r.get('rms') or []) else ''}</td>{ext_cells(i)}</tr>"
                               for i, x in enumerate(r["fd_runs"])) + "</table>")
        out.append("<div class='imgs'>")
        for m, (label, _, (lo, hi)) in METRICS.items():
            p = png_path(sdir, sid, m)
            if not os.path.isfile(p):
                tag = f'<div class="missing">{html.escape(label)}: not rendered yet (QC tab → Render surface images)</div>'
            elif embed:
                tag = _img_tag(p, f"{sid} {m}")
            else:
                tag = f'<img src="file://{html.escape(p)}">'
            stale = os.path.isfile(p) and not _range_matches(p, m)
            out.append(f"<figure>{tag}<figcaption><b>{html.escape(sid)} — {html.escape(label)}</b><br>"
                       f"Inflated {mesh}k L/R surfaces, lateral and medial views. {html.escape(range_text(m))}."
                       + (" <b style='color:#c00'>Rendered with a different range — re-render.</b>" if stale else "")
                       + f"<div class='scale'><span>{lo:g}</span><i></i><span>&ge; {hi:g}</span></div></figcaption></figure>")
        out.append("</div>")
        # template-matching network maps, if rendered
        from . import tm as _tm
        _tm.refresh_atlases(cfg)
        tms = [(a, tm_png_path(sdir, sid, a)) for a in _tm.ATLASES if os.path.isfile(tm_png_path(sdir, sid, a))]
        if tms:
            out.append("<div class='imgs'>")
            for a, p in tms:
                names = ", ".join(f"{i}&nbsp;{html.escape(n)}" for i, n in enumerate(_tm.ATLASES[a], 1) if n)
                n18 = (_tm.ATLASES[a] + [''] * 18)[17]
                out.append(f"<figure>{_img_tag(p, sid + ' ' + a) if embed else f'<img src=file://{html.escape(p)}>'}"
                           f"<figcaption><b>{html.escape(sid)} — template-matching networks ({html.escape(a)}), island-cleaned</b><br>"
                           f"Palette {TM_PALETTE}, values 1–18 = networks: {names}"
                           f"{f' (network 18, {html.escape(n18)}, stored as 1.5 for display)' if n18 else ''}.</figcaption></figure>")
            out.append("</div>")
    out.append("</body></html>")
    adir = _cfg.ensure_dir(os.path.join(cfg.projects_root, project, "Analysis"), cfg.get("study_group"))
    path = os.path.join(adir, f"QC_report_{_dt.datetime.now().strftime('%Y%m%d_%H%M')}.html")
    with open(path, "w") as fh:
        fh.write("\n".join(out))
    _cfg.fix_group(path, cfg.get("study_group"))
    latest = os.path.join(adir, "QC_report_latest.html")
    shutil.copyfile(path, latest)
    _cfg.fix_group(latest, cfg.get("study_group"))
    return path


def render_subcort(cfg, dscalar, pfm_dir, timeout=600):
    """Subcortical WTA map -> PNG next to it, via PFM_tools/render_subcort_scene.sh (Workbench scene template)."""
    script = os.path.join(pfm_dir, "render_subcort_scene.sh")
    if not os.path.isfile(script):
        raise RuntimeError(f"{script} not found")
    env = _wb_env()
    wb = find_wb_command(cfg)
    if wb:
        env["WB_COMMAND"] = wb
    p = subprocess.run(["bash", script, dscalar], capture_output=True, text=True, timeout=timeout, env=env)
    if p.returncode != 0:
        raise RuntimeError((p.stdout + p.stderr).strip()[-700:])
    return dscalar[:-len(".dscalar.nii")] + ".png"
