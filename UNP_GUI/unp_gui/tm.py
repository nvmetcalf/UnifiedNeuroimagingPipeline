"""
Precision functional mapping (PFM) through PFM_tools/run_PFM.sh:

    concat   frame-censor + concatenate surface timeseries -> dconn   (concat_sessions.sh)
    tm       DCAN template matching -> cortical networks             (run_template_matching_v3.m)
    wta      subcortical winner-take-all assignment                  (run_subcort_WTA.sh)

Inputs per session: <sid>/Functional/Surface/<sid>_rsfMRI_<variant>.dtseries.nii
                    <sid>/Functional/TemporalMask/rsfMRI_tmask.txt   (1 = kept)
                    where <sid> is InProcess/<sid>, or Participants/<sid> for finished sessions (find_session_dir)
                    [rest_frames.txt, Functional/Movement/<sid>_all_bold_runs.fd]

Outputs         (<name> = <sid> or the concatenation's name, + the optional output-name suffix, e.g. _noGSR_sm2)
  one session   InProcess/<sid>/Functional/Surface/TemplateMatching/   (<sid><suffix>.dconn.nii, <sid><suffix>_TM_* ...)
  concatenated  Projects/<proj>/Participants/<Subject>/   (dtseries, dconn, tmask, <name>_sessions.txt)
                Projects/<proj>/Participants/<Subject>/TemplateMatching/
  TM files      <name>_TM_<tag>_{assignments,assignments_clean,eta,lowtSNR_mask}.dscalar.nii  (+ _Zscored.mat)
                (<tag> = HCP18 for HCP_networks_wSCAN_insulafix, HCP18orig for HCP_networks_wSCAN, else the atlas key;
                 results written before the renaming keep the long key and are still found)
  WTA files     Subcort/<name>_TM_<tag>_WTA_<tag>.dscalar.nii, _by_structure.csv, _params.txt
  status        pfm_status.txt   (step  OK|FAILED  date  detail  name; the name column since 2026-10-19)
"""
import csv
import glob
import html
import os
import re
import shlex
import struct
import time

# ---------------------------------------------------------------------------
# network atlases = the CIFTI network dlabels in the Parcellation folder
# ---------------------------------------------------------------------------
NETWORK_NAMES = ['Default', 'Visual', 'FrontoParietal', 'MedialVisual', 'DorsalAttention',
                 'Premotor', 'Language', 'Salience', 'ActionMode', 'SomatomotorHand', 'SomatomotorFace',
                 'Auditory', '', '', 'ParietalMemory', 'ContextualAssociation', 'SomatomotorFoot', 'SCAN']
GRAYORDINATES = 91282          # the standard 32k_fs_LR CIFTI space of the pipeline's dtseries / dconns
MAX_NETWORKS = 18              # template matching seeds 18 columns: a label's value is its network number
DEFAULT_ATLAS = "HCP_networks_wSCAN_insulafix"
BUILTIN_ATLASES = (DEFAULT_ATLAS, "HCP_networks_wSCAN")      # also named in run_template_matching_v3.m's registry
DEFAULT_PARCELLATION_DIR = "/gpfs/data/siegellab/UnifiedNeuroimagingPipeline/SCRIPTS/Parcellation"
ATLASES = {k: list(NETWORK_NAMES) for k in BUILTIN_ATLASES}  # usable atlas key -> 18 network names (see refresh_atlases)
ATLAS_INFO = {}                # every dlabel found: key -> {path, rel, usable, reason, short, nets, gray}
_ATLAS_STATE = {"t": 0.0, "dir": None}
_HEADER_CACHE = {}             # (path, mtime, size) -> (grayordinates, {label key: name})


def parcellation_dir(cfg=None):
    """config.json "parcellation_dir" if set, else SCRIPTS/Parcellation of the shared pipeline install."""
    return (cfg.get("parcellation_dir") if cfg is not None else None) or DEFAULT_PARCELLATION_DIR


def atlas_key_for(rel):
    """'Sub/Name.dlabel.nii' -> 'Sub__Name'.  The key names the atlas everywhere (--atlas, <name>_TM_<key>_* files)."""
    if rel.endswith(".dlabel.nii"):
        rel = rel[:-len(".dlabel.nii")]
    return rel.replace("\\", "/").replace("/", "__")


def read_dlabel(path):
    """(grayordinates, {label key: name}) from the CIFTI-2 header and the XML label table (header only, no data)."""
    with open(path, "rb") as fh:
        h = fh.read(540)
        if len(h) < 540 or struct.unpack("<i", h[:4])[0] != 540:
            raise ValueError("not a NIfTI-2 / CIFTI-2 file")
        dim = struct.unpack("<8q", h[16:80])
        vox = struct.unpack("<q", h[168:176])[0]
        if not 544 < vox < 64 * 1024 * 1024:
            raise ValueError("no CIFTI XML extension")
        ext = fh.read(vox - 540)
    if not 1 <= dim[0] <= 7:
        raise ValueError("bad dimensions")
    esize = struct.unpack("<i", ext[4:8])[0]
    xml = ext[12:4 + esize].decode("utf-8", "replace")
    table = re.search(r"<LabelTable>(.*?)</LabelTable>", xml, re.S)
    labels = {}
    for m in re.finditer(r'<Label\b[^>]*?\bKey="(-?\d+)"[^>]*>(.*?)</Label>', table.group(1) if table else "", re.S):
        labels[int(m.group(1))] = html.unescape(re.sub(r"<!\[CDATA\[|\]\]>", "", m.group(2))).strip()
    return dim[dim[0]], labels


def discover_atlases(pdir):
    """Every *.dlabel.nii under pdir (hidden files such as ._x skipped) -> {key: info}.  Raises OSError if pdir
    cannot be read.  usable = 91,282 grayordinates and every label value in 1..18 (what template matching can seed)."""
    def onerror(e):
        raise e
    found = {}
    for root, dirs, files in os.walk(pdir, onerror=onerror):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for fn in sorted(files):
            if fn.startswith(".") or not fn.endswith(".dlabel.nii"):
                continue
            path = os.path.join(root, fn)
            rel = os.path.relpath(path, pdir)
            key = atlas_key_for(rel)
            if key in found:
                continue
            info = {"path": path, "rel": rel, "usable": False, "reason": "", "short": "", "nets": {}, "gray": None}
            try:
                st = os.stat(path)
                ck = (path, st.st_mtime, st.st_size)
                if ck not in _HEADER_CACHE:
                    _HEADER_CACHE[ck] = read_dlabel(path)
                gray, labels = _HEADER_CACHE[ck]
                nets = {k: v for k, v in labels.items() if k != 0}
                info.update(gray=gray, nets=nets)
                if not re.fullmatch(r"[A-Za-z0-9_.-]+", key):
                    info["reason"] = info["short"] = "file name has characters other than letters, digits, _ . -"
                elif gray != GRAYORDINATES:
                    info["reason"] = f"{gray:,} grayordinates; the pipeline's dconns have {GRAYORDINATES:,}"
                    info["short"] = f"{gray:,} grayordinates"
                elif not nets:
                    info["reason"] = info["short"] = "no labels"
                elif min(nets) < 1 or max(nets) > MAX_NETWORKS:
                    info["reason"] = (f"{len(nets)} labels with values {min(nets)}-{max(nets)}; template matching needs "
                                      f"network labels 1-{MAX_NETWORKS}")
                    info["short"] = f"{len(nets)} labels, not networks 1-{MAX_NETWORKS}"
                else:
                    info["usable"] = True
            except (OSError, ValueError, struct.error) as e:
                info["reason"] = info["short"] = f"unreadable ({e})"
            found[key] = info
    return found


def refresh_atlases(cfg=None, force=False):
    """Re-scan the Parcellation folder (at most every 30 s) and rebuild ATLASES / ATLAS_INFO.  If the folder cannot
    be read or holds no dlabels, what was found last time (initially the two HCP atlases) stays in place."""
    global ATLASES, ATLAS_INFO
    pdir = parcellation_dir(cfg)
    now = time.time()
    if not force and _ATLAS_STATE["dir"] == pdir and now - _ATLAS_STATE["t"] < 30:
        return ATLASES
    _ATLAS_STATE.update(t=now, dir=pdir)
    try:
        found = discover_atlases(pdir)
    except OSError:
        return ATLASES
    if not found:
        return ATLASES
    usable = sorted((k for k, v in found.items() if v["usable"]),
                    key=lambda k: (k != DEFAULT_ATLAS, k != "HCP_networks_wSCAN", k.lower()))
    names = {}
    for k in usable:
        if k in BUILTIN_ATLASES:
            names[k] = list(NETWORK_NAMES)
        else:
            nets = found[k]["nets"]
            names[k] = [nets.get(i, "") for i in range(1, MAX_NETWORKS + 1)]
    ATLAS_INFO = found
    ATLASES = names
    return ATLASES


def default_atlas():
    return DEFAULT_ATLAS if DEFAULT_ATLAS in ATLASES else next(iter(ATLASES), DEFAULT_ATLAS)


def dlabel_path(atlas):
    """The dlabel file the GUI found for this atlas ('' if unknown)."""
    return (ATLAS_INFO.get(atlas) or {}).get("path", "")


def atlas_options(cfg=None):
    """Dropdown entries: usable atlases (default first), then the greyed-out ones with the reason."""
    pdir = parcellation_dir(cfg)
    out = []
    for k, names in ATLASES.items():
        out.append({"key": k, "label": f"{k} ({len([x for x in names if x])} networks)", "usable": True, "reason": "",
                    "path": dlabel_path(k) or os.path.join(pdir, k + ".dlabel.nii")})
    for k in sorted((k for k, v in ATLAS_INFO.items() if not v["usable"]), key=str.lower):
        v = ATLAS_INFO[k]
        out.append({"key": k, "label": f"{k} (not usable: {v['short']})", "usable": False,
                    "reason": v["reason"], "path": v["path"]})
    return out


DEFAULT_VARIANT = "uout_bpss_sr_sm2.ctx"
WTA_METHODS = {
    "scoresmoothing_v3": "enrichment of top-X% cortical connections (cortex closer than the min distance excluded), "
                         "score maps smoothed, then argmax (WTA_subcort_assignment_scoresmoothing_v3.m)",
    "networkseed": "per-network seed timecourse correlation maps smoothed (same σ as scoresmoothing; 0 = off), "
                   "normalised per structure, then argmax (WTA_subcort_assignment_networkseed.m; needs tSNR maps). "
                   "Tick 'No network normalization' for the raw-correlation variant (nonorm, no a-priori exclusions)",
    "both": "scoresmoothing_v3 then networkseed in the same job, same smoothing / cleanup / groups - for comparing "
            "the two (network groups left blank = each method's own default)",
}
WTA_METHOD_LIST = {"both": ["scoresmoothing_v3", "networkseed"]}   # expansion of composite methods


def wta_methods_of(method):
    return WTA_METHOD_LIST.get(method or "scoresmoothing_v3", [method or "scoresmoothing_v3"])
WTA_DEFAULTS = {"top_pct": 10, "smooth": 2, "cleanup": 40, "min_dist": 20,     # min_dist: scoresmoothing only, 0 = off
                "groups": {"scoresmoothing_v3": "{[10 17],[2 4],[5 6],[1 15 16]}", "networkseed": "{[10 17],[2 4],[5 6]}"}}
STEPS = ["concat", "tm", "wta"]


def pfm_dir(cfg):
    return cfg.get("pfm_tools_dir") or "/gpfs/data/siegellab/PFM_tools"


def run_script(cfg):
    return os.path.join(pfm_dir(cfg), "run_PFM.sh")


def find_session_dir(cfg, project, sid):
    """InProcess/<sid>, else the finished session Participants/<sid> (some projects, e.g. psilo_pfm, keep their
    sessions there); the InProcess path if neither exists."""
    root = os.path.join(cfg.projects_root, project)
    for sub in ("InProcess", "Participants"):
        d = os.path.join(root, sub, sid)
        if os.path.isdir(d):
            return d
    return os.path.join(root, "InProcess", sid)


def list_sessions(cfg, project):
    """{session id: folder} usable for PFM: InProcess/<Subject>_<Session>, plus finished sessions in Participants/
    that have a Functional/Surface folder (participant folders such as Participants/PS03 have no '_' and are skipped)."""
    root = os.path.join(cfg.projects_root, project)
    out = {}
    for sub in ("InProcess", "Participants"):
        try:
            names = sorted(os.listdir(os.path.join(root, sub)))
        except OSError:
            continue
        for n in names:
            if "_" not in n or n.startswith(".") or n in out:
                continue
            d = os.path.join(root, sub, n)
            if os.path.isdir(d) and (sub == "InProcess" or os.path.isdir(os.path.join(d, "Functional", "Surface"))):
                out[n] = d
    return out


def variants(sdir, sid):
    """dtseries variants available: the <variant> in <sid>_rsfMRI_<variant>.dtseries.nii"""
    d = os.path.join(sdir, "Functional", "Surface")
    out = []
    try:
        for n in sorted(os.listdir(d)):
            m = re.match(rf"^{re.escape(sid)}_rsfMRI_(.+)\.dtseries\.nii$", n)
            if m:
                out.append(m.group(1))
    except OSError:
        pass
    return out


def dtseries_path(sdir, sid, variant):
    return os.path.join(sdir, "Functional", "Surface", f"{sid}_rsfMRI_{variant}.dtseries.nii")


def tmask_path(sdir):
    return os.path.join(sdir, "Functional", "TemporalMask", "rsfMRI_tmask.txt")


def rest_frames_path(sdir):
    return os.path.join(sdir, "Functional", "Surface", "rest_frames.txt")


def fd_path(sdir, sid):
    return os.path.join(sdir, "Functional", "Movement", f"{sid}_all_bold_runs.fd")


def tsnr_ok(sdir, sid=None):
    """True if the networkseed WTA method and the low-tSNR mask of the TM clean step can get tSNR maps for this session: QC/tSNR_fnirt.{L,R}.32k.func.gii
    (new pipeline -QC) or QC/<sid>_CoV.{L,R}.32k.func.gii (old pipeline; run_PFM.sh builds tSNR = 1/CoV)."""
    q = os.path.join(sdir, "QC")
    sid = sid or os.path.basename(sdir.rstrip("/"))
    return all(os.path.isfile(os.path.join(q, f"tSNR_fnirt.{h}.32k.func.gii")) or
               os.path.isfile(os.path.join(q, f"{sid}_CoV.{h}.32k.func.gii")) for h in ("L", "R"))


# ---------------------------------------------------------------------------
# where outputs live
# ---------------------------------------------------------------------------
def single_out_dir(sdir):
    return os.path.join(sdir, "Functional", "Surface", "TemplateMatching")


def participant_dir(cfg, project, subject):
    return os.path.join(cfg.projects_root, project, "Participants", subject)


def concat_name(subject, n):
    return f"{subject}_concat{n}"


SUFFIX_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
# what may follow <name> in an output file name (used to find which output names a TemplateMatching folder holds)
_NAME_ENDS = re.compile(r"^(.*?)(?:_TM_.+|\.dconn\.nii|\.dtseries\.nii|_sessions\.txt|_tmask\.txt)$")


def normalize_suffix(s):
    """Output-name suffix, same rule as run_PFM.sh --suffix: '' stays ''; letters, digits, _ . - only; a leading '_'
    is added if it starts with a letter or digit ('noGSR_sm2' -> '_noGSR_sm2'); may not contain '_TM_' (that separates
    the name from the atlas tag in <name>_TM_<tag>_*)."""
    s = (s or "").strip()
    if not s:
        return ""
    if not SUFFIX_RE.match(s):
        raise ValueError(f"output name suffix may only contain letters, digits, _ . - : {s!r}")
    if s[0].isalnum():
        s = "_" + s
    if "_TM_" in s:
        raise ValueError(f"output name suffix may not contain _TM_: {s!r}")
    return s


def output_suffixes(out_dir, sid):
    """Suffixes of the output names present in a single-session TemplateMatching folder, '' (= plain <sid>) first:
    <sid>.dconn.nii / <sid>_TM_* -> '';  <sid>_noGSR_sm2.dconn.nii / <sid>_noGSR_sm2_TM_* -> '_noGSR_sm2'."""
    found = set()
    try:
        files = os.listdir(out_dir)
    except OSError:
        return []
    for f in files:
        if not f.startswith(sid):
            continue
        m = _NAME_ENDS.match(f[len(sid):])
        if not m:
            continue
        sfx = m.group(1)
        if sfx == "" or (sfx[0] in "_.-" and SUFFIX_RE.match(sfx) and "_TM_" not in sfx):
            found.add(sfx)
    return sorted(found, key=lambda x: (x != "", x))


# Short names used in output files (same mapping as run_PFM.sh / run_template_matching_v3.m): any other atlas key is used as is.
ATLAS_TAGS = {"HCP_networks_wSCAN_insulafix": "HCP18", "HCP_networks_wSCAN": "HCP18orig"}


def atlas_tag(atlas):
    return ATLAS_TAGS.get(atlas, atlas)


def tm_outputs(out_dir, name, atlas):
    """Paths of one TM result.  New runs are named <name>_TM_<tag>_*  (HCP18 for the insulafix atlas); results written
    before the renaming keep the long atlas key, so those are used when the new-named file is not there."""
    def paths(t):
        base = os.path.join(out_dir, f"{name}_TM_{t}")
        return {"mat": base + "_Zscored.mat", "assign": base + "_assignments.dscalar.nii",
                "clean": base + "_assignments_clean.dscalar.nii", "eta": base + "_eta.dscalar.nii",
                "params": base + "_params.txt", "subcort": os.path.join(out_dir, "Subcort"),
                "wta_prefix": f"{name}_TM_{t}_WTA", "tsnr_mask": base + "_lowtSNR_mask.dscalar.nii", "tag": t, "legacy": False}
    new = paths(atlas_tag(atlas))
    if atlas_tag(atlas) != atlas and not (os.path.isfile(new["clean"]) or os.path.isfile(new["mat"])):
        old = paths(atlas)
        if os.path.isfile(old["clean"]) or os.path.isfile(old["mat"]):
            old["legacy"] = True
            return old
    return new


def _mtime(p):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(p)))


def _g(x):
    """MATLAB/printf %g formatting, as used in the WTA output names (2 -> '2', 1.5 -> '1.5')."""
    return f"{float(x):g}"


def wta_tag(method, top_pct, smooth, cleanup, min_dist=0, nonorm=False):
    """Output tag written by the WTA .m files (same rule as run_subcort_WTA.sh):
    top<P>pct_scoresmoothing[_md<D>][_cleaned]  |  networkseed[_sm<S>][_nonorm][_cleaned]
    (_md only when D > 0, scoresmoothing only; _sm only when S > 0; '.' -> 'p')."""
    if method == "networkseed":
        tag = "networkseed" + (f"_sm{_g(smooth).replace('.', 'p')}" if float(smooth) > 0 else "") + ("_nonorm" if nonorm else "")
    else:
        tag = f"top{_g(top_pct)}pct_scoresmoothing" + (f"_md{_g(min_dist).replace('.', 'p')}" if float(min_dist or 0) > 0 else "")
    return tag + ("_cleaned" if float(cleanup or 0) > 0 else "")


def wta_tags_from_opts(opts):
    """[wta_tag(), ...] for the GUI's submit options (one per method; 'both' gives two), with the same defaults
    build_job() applies."""
    d = WTA_DEFAULTS
    pick = lambda k: opts.get(k) if opts.get(k) not in (None, "") else d[k]
    return [wta_tag(m, pick("top_pct"), pick("smooth"), pick("cleanup"), pick("min_dist"), bool(opts.get("no_norm"))) for m in wta_methods_of(opts.get("wta_method"))]


def wta_status(out_dir, name, atlas):
    """{tag: {done, mtime, file, csv, tag, method, cleaned}} from Subcort/<prefix>_*.dscalar.nii.
    Keyed by output tag (e.g. top10pct_scoresmoothing_cleaned, networkseed_sm2_cleaned), so runs of the same
    method with different smoothing / cleanup are listed separately."""
    o = tm_outputs(out_dir, name, atlas)
    st = {}
    prefixes = [o["wta_prefix"]] + ([f"{name}_TM_{atlas}_WTA"] if atlas_tag(atlas) != atlas and o["wta_prefix"] != f"{name}_TM_{atlas}_WTA" else [])
    files = [(f, p) for p in prefixes for f in sorted(glob.glob(os.path.join(o["subcort"], p + "_*.dscalar.nii")))]
    for f, pfx in files:
        b = os.path.basename(f)[:-len(".dscalar.nii")]
        tag = b[len(pfx) + 1:]
        if any(tag.endswith(x) for x in ("_continuous", "_raw")):
            continue
        method = "networkseed" if "networkseed" in tag else "scoresmoothing_v3" if "scoresmoothing" in tag else None
        if not method:
            continue
        csvf = f[:-len(".dscalar.nii")] + "_by_structure.csv"
        pngf = f[:-len(".dscalar.nii")] + ".png"
        st[tag] = {"done": True, "mtime": _mtime(f), "file": f, "tag": tag, "method": method,
                   "png": pngf if os.path.isfile(pngf) else "",
                   "csv": csvf if os.path.isfile(csvf) else "", "cleaned": tag.endswith("_cleaned"), "nonorm": "_nonorm" in tag}
    return st


def atlas_status(out_dir, name):
    """{atlas: {done, partial, mtime, clean, wta:{...}}} for one TM output folder."""
    st = {}
    for a in ATLASES:
        o = tm_outputs(out_dir, name, a)
        if os.path.isfile(o["clean"]):
            st[a] = {"done": True, "mtime": _mtime(o["clean"]), "clean": o["clean"], "wta": wta_status(out_dir, name, a),
                     "tag": o["tag"], "legacy": o["legacy"], "tsnr_masked": os.path.isfile(o["tsnr_mask"])}
        elif os.path.isfile(o["mat"]):
            st[a] = {"done": False, "partial": True, "wta": {}}
    return st


def session_status(sdir, sid, suffix=""):
    return atlas_status(single_out_dir(sdir), sid + suffix)


def session_outputs(sdir, sid):
    """{suffix: {name, dconn, tm (atlas_status), status}} for every output name in the session's TemplateMatching
    folder; always has '' (the plain session id, possibly empty)."""
    out_dir = single_out_dir(sdir)
    res = {}
    for sfx in [""] + [x for x in output_suffixes(out_dir, sid) if x]:
        name = sid + sfx
        res[sfx] = {"name": name, "dconn": os.path.isfile(os.path.join(out_dir, name + ".dconn.nii")),
                    "tm": atlas_status(out_dir, name), "status": read_status(out_dir, 6, name=name, legacy=(sfx == ""))}
    return res


def read_status(out_dir, n=12, name=None, legacy=True):
    """Last lines of pfm_status.txt: [{step, result, date, detail}].  With name: only that output name's lines -
    the 5th column (run_PFM.sh writes it since 2026-10-19); an older 4-column line counts if its detail is a path of
    that name (<name>.dconn.nii, <name>_TM_...), or - legacy=True - if it names no file (e.g. 'tm FAILED exit 1')."""
    rows = []
    try:
        with open(os.path.join(out_dir, "pfm_status.txt")) as fh:
            for line in fh:
                f = line.rstrip("\n").split("\t")
                if len(f) < 3:
                    continue
                det = f[3] if len(f) > 3 else ""
                if name is not None:
                    if len(f) >= 5:
                        if f[4] != name:
                            continue
                    elif not (f"/{name}.dconn.nii" in det or f"/{name}_TM_" in det or f"/{name}.dtseries.nii" in det
                              or (legacy and "/" not in det)):
                        continue
                rows.append({"step": f[0], "result": f[1], "date": f[2], "detail": det})
    except OSError:
        pass
    return rows[-n:]


def read_sessions_doc(path):
    """<name>_sessions.txt -> {sessions:[...], frames, kept, options:{...}}"""
    out = {"sessions": [], "frames": None, "kept": None, "options": ""}
    try:
        for line in open(path):
            if line.startswith("# variant") or line.startswith("# rest_only"):
                out["options"] += line[2:].strip() + "  "
            elif line.startswith("# total"):
                f = line.split("\t")
                try:
                    out["frames"], out["kept"] = int(f[-2]), int(f[-1])
                except (ValueError, IndexError):
                    pass
            elif not line.startswith("#"):
                f = line.rstrip("\n").split("\t")
                if len(f) >= 2:
                    m = re.search(r"/(?:InProcess|Participants)/([^/]+)/", f[1])
                    out["sessions"].append(m.group(1) if m else os.path.basename(f[1]))
    except OSError:
        pass
    return out


def list_concat(cfg, project):
    """Concatenated analyses: Participants/<Subject>/<name>_sessions.txt"""
    root = os.path.join(cfg.projects_root, project, "Participants")
    out = []
    try:
        subs = sorted(os.listdir(root))
    except OSError:
        return out
    for sub in subs:
        d = os.path.join(root, sub)
        if not os.path.isdir(d):
            continue
        for doc in sorted(glob.glob(os.path.join(d, "*_sessions.txt"))):
            name = os.path.basename(doc)[:-len("_sessions.txt")]
            info = read_sessions_doc(doc)
            out_dir = os.path.join(d, "TemplateMatching")
            out.append({"name": name, "subject": sub, "dir": d, "out_dir": out_dir, "doc": doc,
                        "sessions": info["sessions"], "frames": info["frames"], "kept": info["kept"],
                        "options": info["options"].strip(),
                        "dconn": os.path.isfile(os.path.join(d, name + ".dconn.nii")),
                        "atlases": atlas_status(out_dir, name), "status": read_status(out_dir, name=name)})
    return out


def by_structure(csv_path):
    """Subcortical WTA summary table -> {columns, rows} with network numbers replaced by names where known."""
    with open(csv_path, newline="") as fh:
        r = list(csv.reader(fh))
    if not r:
        return {"columns": [], "rows": []}
    cols = r[0]
    return {"columns": cols, "rows": r[1:]}


def network_label(atlas, n):
    try:
        nm = ATLASES[atlas][int(n) - 1]
    except (ValueError, IndexError, KeyError):
        nm = ""
    return f"{n} {nm}".strip()


# ---------------------------------------------------------------------------
# job script
# ---------------------------------------------------------------------------
def build_job(cfg, project, sessions, opts, slurm_opts, out_log_dir, sbatch_header):
    """One sbatch script that runs run_PFM.sh.  sessions: list of sids (one, or several of one subject).
    opts: atlas, variant, steps (list), rest_only, fd, tsnr_mask, wta_method, top_pct, smooth, cleanup, groups, rerun, name,
    suffix (appended to the output name; not to an existing concatenated analysis in opts['names']).
    Returns (job_name, name, lines, info)."""
    subject = sessions[0].partition("_")[0]
    atlas = opts.get("atlas") or default_atlas()
    steps = [s for s in STEPS if s in (opts.get("steps") or STEPS)]
    concat = len(sessions) > 1
    suffix = normalize_suffix(opts.get("suffix"))
    fixed = (opts.get("names") or {}).get(",".join(sessions))      # existing concatenated analysis: name as it is
    if concat:
        name = fixed or ((opts.get("name") or concat_name(subject, len(sessions))) + suffix)
        pdir = participant_dir(cfg, project, subject)
        out_dir = os.path.join(pdir, "TemplateMatching")
        session_dir = pdir
    else:
        name = sessions[0] + suffix
        session_dir = find_session_dir(cfg, project, sessions[0])
        out_dir = single_out_dir(session_dir)
    q = shlex.quote
    args = [run_script(cfg), "--project", project, "--sessions", ",".join(sessions),
            "--atlas", atlas, "--variant", opts.get("variant") or DEFAULT_VARIANT,
            "--steps", ",".join(steps), "--projects-home", cfg.projects_home]
    dlabel = dlabel_path(atlas)          # run exactly the file the dropdown listed
    if dlabel:
        args += ["--dlabel", dlabel]
    if concat and name != concat_name(subject, len(sessions)):
        args += ["--name", name]          # the full name (any suffix included)
    if not concat and suffix:
        args += ["--suffix", suffix]
    if opts.get("rest_only"):
        args.append("--rest-only")
    if opts.get("fd"):
        args += ["--fd", str(opts["fd"])]
    if "wta" in steps:
        m = opts.get("wta_method") or "scoresmoothing_v3"
        args += ["--wta-method", m, "--top-pct", str(opts.get("top_pct") or WTA_DEFAULTS["top_pct"]),
                 "--smooth", str(opts.get("smooth") if opts.get("smooth") not in (None, "") else WTA_DEFAULTS["smooth"]),
                 "--cleanup", str(opts.get("cleanup") if opts.get("cleanup") not in (None, "") else WTA_DEFAULTS["cleanup"]),
                 "--min-dist", str(opts.get("min_dist") if opts.get("min_dist") not in (None, "") else WTA_DEFAULTS["min_dist"])]
        if (opts.get("groups") or "").strip():
            args += ["--groups", opts["groups"].strip()]
        if opts.get("no_norm"):
            args.append("--no-norm")          # networkseed only (run_PFM.sh ignores it for scoresmoothing_v3)
    if "tm" in steps and opts.get("tsnr_mask") is False:
        args.append("--no-tsnr-mask")
    if opts.get("rerun"):
        args.append("--rerun")
    if opts.get("mem_limit"):
        args += ["--mem-limit", str(opts["mem_limit"])]

    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", f"{name}_{atlas_tag(atlas)}")
    job_name = f"PFM_{project}_{name}"
    s = slurm_opts
    lines = sbatch_header(job_name, os.path.join(out_log_dir, f"{safe}_PFM_%j.out"), os.path.join(out_log_dir, f"{safe}_PFM_%j.err"),
                          s.get("tm_partition", "cpu_short"), s.get("tm_cpus", 4), s.get("tm_mem", "150G"), s.get("tm_time", "12:00:00"))
    lines += ["", f"umask {cfg.get('umask', '002')}",
              'START_TIME=$(date)',
              'SLURM_LOG=${SLURM_LOG:-$(scontrol show job "$SLURM_JOB_ID" 2>/dev/null | sed -n "s/.*StdOut=//p" | head -1)}',
              'echo "UNP_GUI PFM job $SLURM_JOB_ID on $(hostname) started $START_TIME"',
              f'echo "sessions={",".join(sessions)} name={name} atlas={atlas} steps={",".join(steps)}"',
              f"export PROJECTS_HOME={q(cfg.projects_home)}"]
    if cfg.get("pp_scripts"):
        lines.append(f"export PP_SCRIPTS={q(cfg.pp_scripts)}")
    for line in cfg.get("tm_prologue") or ["module load matlab/R2024a"]:
        lines.append(line)
    lines += [f"[ -x {q(run_script(cfg))} ] || {{ echo 'run_PFM.sh not found/executable: {run_script(cfg)}'; exit 3; }}",
              "bash " + " ".join(q(a) for a in args),
              "status=$?",
              f"chgrp -Rf {q(cfg.get('study_group') or '')} {q(out_dir)} {q(out_log_dir)} 2>/dev/null",
              f"chmod -Rf g+rwX {q(out_dir)} {q(out_log_dir)} 2>/dev/null",
              'echo "PFM finished status=$status ($(date))"']
    info = {"name": name, "session_dir": session_dir, "out_dir": out_dir, "sessions": sessions, "concat": concat,
            "atlas": atlas, "dlabel": dlabel, "steps": steps, "variant": opts.get("variant") or DEFAULT_VARIANT,
            "suffix": "" if (concat and fixed) else suffix,
            "wta_method": opts.get("wta_method") if "wta" in steps else ""}
    return job_name, name, lines, info
