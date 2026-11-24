"""
Read-only knowledge of the UnifiedNeuroimagingPipeline (UNP) layout:

  <PROJECTS_HOME>/Scans/<project>/<subject>/<session>/       raw dicom / BIDS
  <PROJECTS_HOME>/Projects/<project>/Study.cfg
  <PROJECTS_HOME>/Projects/<project>/InProcess/<subject>_<session>/
        <id>.params, <id>_Execution.log, .inprocess (lock)
        Logs/Processing_Summary_<date>.txt      <- per-module status lines
        Logs/<module script>.log/.execution
        Anatomical/ Functional/ Masks/ QC/ Freesurfer/

Plus parsing of SCRIPTS/Config/P2.cfg (the list of P2 modules and overrides).
"""
import datetime as _dt
import os
import re
import shlex
import time

from . import config as _cfg

# ---------------------------------------------------------------------------
# P2.cfg : modules & overrides
# ---------------------------------------------------------------------------
_QUOTED = re.compile(r'"((?:[^"\\]|\\.)*)"')


def _csh_array(text, name):
    """Return the list of quoted strings of `set <name> = ( ... )`."""
    m = re.search(r'set\s+' + re.escape(name) + r'\s*=\s*\((.*?)\)\s*$', text, re.S | re.M)
    if not m:
        return []
    body = m.group(1)
    return [s.replace('\\"', '"') for s in _QUOTED.findall(body)]


def parse_p2_cfg(pp_scripts):
    path = os.path.join(pp_scripts, "Config", "P2.cfg")
    modules, overrides = [], []
    try:
        text = open(path, errors="replace").read()
    except OSError:
        return {"modules": modules, "overrides": overrides, "path": path, "error": "P2.cfg not found"}
    # strip line continuations
    text = text.replace("\\\n", " ")
    items = _csh_array(text, "PipelineModules")
    section = ""
    for i in range(0, len(items) - 2, 3):
        flag, script, desc = items[i].strip(), items[i + 1].strip(), items[i + 2].strip()
        if not flag:
            continue
        if not flag.startswith("-"):
            section = flag
            continue
        modules.append({
            "flag": flag,
            "script": script.replace("$PP_SCRIPTS", pp_scripts).replace("${PP_SCRIPTS}", pp_scripts),
            "log_base": os.path.basename(script),
            "desc": desc,
            "section": section,
        })
    items = _csh_array(text, "PipelineOverrides")
    for i in range(0, len(items) - 3, 4):
        flag, var, hasval, desc = (x.strip() for x in items[i:i + 4])
        if flag.startswith("-"):
            overrides.append({"flag": flag, "variable": var, "takes_value": hasval != "0", "desc": desc})
    fs = _csh_array(text, "FreesurferCommands")
    fs_versions = [fs[i] for i in range(0, len(fs) - 1, 2)]
    return {"modules": modules, "overrides": overrides, "fs_versions": fs_versions, "path": path}


# ---------------------------------------------------------------------------
# Study.cfg
# ---------------------------------------------------------------------------
# Defaults copied from SCRIPTS/config_study (the interactive configurator).
STUDY_CFG_DEFAULTS = [
    ("TargetAtlas", "1", "Index into AtlTargets (P1.cfg). 0 = native T1 space"),
    ("target", "", "Path of atlas target (filled from P1.cfg AtlTargets[TargetAtlas])"),
    ("FD_Threshold", "0.3", "Frame displacement censoring threshold (mm)"),
    ("DVAR_Threshold", "0", "DVARS censoring threshold (0 = off)"),
    ("UseIterativeRegression", "0", ""),
    ("ScratchFolder", "", "Scratch dir for this study (default $SCRATCH/<project>)"),
    ("LowResMesh", "32", "Surface mesh (10/32/164 k)"),
    ("ComputeWBRegressor", "1", ""), ("ComputeVENT", "1", ""), ("ComputeWM", "1", ""),
    ("ComputeMOVERegressor", "1", ""), ("ComputeEACSFRegressor", "1", ""),
    ("ApplyWBRegressor", "1", ""), ("ApplyVENT", "1", ""), ("ApplyWM", "1", ""),
    ("ApplyMOVERegressor", "1", ""), ("ApplyEACSFRegressor", "1", ""),
    ("DoVolumeRegression", "1", ""), ("NonLinear", "1", "Non-linear atlas registration"),
    ("DoVolumeBPSS", "1", "Temporal bandpass in volume"),
    ("LowFrequency", "0.009", "Hz"), ("HighFrequency", "0.08", "Hz"),
    ("MaskTrailer", "", ""), ("DoSurfaceRegression", "1", ""),
    ("ConvertDTItoDWI", "1", ""), ("DTIFramesToUse", "( 3 4 5 6 7 8 9 10 11 12 13 14 )", ""),
    ("IncludeSubCortical", "1", ""), ("VolSmoothingFWHM", "0", "mm"), ("SurfSmoothingFWHM", "0", "mm"),
    ("StudyGroup", "siegellab", "Unix group applied to outputs"),
    ("ProcessUserScript", "", "Script to run after processing"),
    ("FinalResolution", "3", "mm"), ("RegisterEcho", "1", ""), ("MaximumRegDisplacement", "0", ""),
    ("MovementLowpass", "2", ""), ("MaxNumRegressors", "25", ""), ("RunNORDIC", "1", ""),
    ("FreesurferVersionToUse", "fs_7_4_1", "Folder in SCRIPTS/FreesurferVersions"),
    ("UserEmailAddress", "", "P2 e-mails a success/failure report per subject (with log tail) when set"),
]

_SET_RE = re.compile(r'^(\s*)set\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$')


def parse_study_cfg(path):
    """Return ordered list of {name, value, comment} + raw text."""
    entries, raw = [], ""
    try:
        raw = open(path, errors="replace").read()
    except OSError:
        return {"exists": False, "entries": [], "raw": ""}
    for line in raw.splitlines():
        code, _, comment = line.partition("#")
        m = _SET_RE.match(code)
        if m:
            entries.append({"name": m.group(2), "value": m.group(3).strip(), "comment": comment.strip()})
    return {"exists": True, "entries": entries, "raw": raw}


def render_study_cfg(values, existing_raw=""):
    """Write a Study.cfg.  If an existing file is given, values are replaced in
    place (comments preserved) and new keys appended; otherwise a fresh file
    is generated from STUDY_CFG_DEFAULTS order."""
    done = set()
    out = []
    if existing_raw:
        for line in existing_raw.splitlines():
            code, hash_, comment = line.partition("#")
            m = _SET_RE.match(code)
            if m and m.group(2) in values:
                name = m.group(2)
                done.add(name)
                out.append(f"{m.group(1)}set {name} = {values[name]}" + (f" #{comment}" if hash_ else ""))
            else:
                out.append(line)
    else:
        out += ["#######################", "#", "#\tStudy Configuration (written by UNP_GUI)", "#",
                "#######################"]
    order = [n for n, _, _ in STUDY_CFG_DEFAULTS] + [n for n in values if n not in {d[0] for d in STUDY_CFG_DEFAULTS}]
    for name in order:
        if name in values and name not in done:
            out.append(f"set {name} = {values[name]}")
            done.add(name)
    return "\n".join(out).rstrip("\n") + "\n"


def parse_p1_atlases(pp_scripts):
    path = os.path.join(pp_scripts, "Config", "P1.cfg")
    try:
        text = open(path, errors="replace").read().replace("\\\n", " ")
    except OSError:
        return []
    m = re.search(r'set\s+AtlTargets\s*=\s*\((.*?)\)', text, re.S)
    if not m:
        return []
    try:
        toks = shlex.split(m.group(1))
    except ValueError:
        toks = m.group(1).split()
    ph = os.path.dirname(pp_scripts)
    return [t.replace("${PROJECTS_HOME}", ph).replace("$PROJECTS_HOME", ph)
             .replace("${ATLAS}", os.path.join(ph, "ATLAS")).replace("$ATLAS", os.path.join(ph, "ATLAS"))
            for t in toks]


# ---------------------------------------------------------------------------
# Scans discovery
# ---------------------------------------------------------------------------
def _listdirs(path):
    try:
        with os.scandir(path) as it:
            return sorted(e.name for e in it if e.is_dir(follow_symlinks=True) and not e.name.startswith("."))
    except OSError:
        return []


def list_scan_projects(cfg):
    return _listdirs(cfg.scans_dir)


def list_projects(cfg):
    return _listdirs(cfg.projects_root)


def scan_root(cfg, project):
    root = os.path.join(cfg.scans_dir, project)
    if os.path.isdir(os.path.join(root, "rawdata")):
        return os.path.join(root, "rawdata")
    return root


def list_scans(cfg, project):
    """{subject: [sessions]} for Scans/<project>."""
    root = scan_root(cfg, project)
    out = {}
    for sub in _listdirs(root):
        if sub in ("derivatives", "sourcedata", "code", "BIDS", "DICOMS"):
            continue
        out[sub] = _listdirs(os.path.join(root, sub))
    return out


# ---------------------------------------------------------------------------
# Processing_Summary parsing
# ---------------------------------------------------------------------------
_MONTHS = {m: i for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], 1)}


def parse_p2_date(s):
    """'Fri_Sep__4_05:48:44_PM_EDT_2026' or 'Wed_Aug_19_22:14:08_EDT_2026' -> datetime (naive local)."""
    toks = [t for t in s.split("_") if t]
    try:
        mon = _MONTHS[toks[1]]
        day = int(toks[2])
        hh, mm, ss = (int(x) for x in toks[3].split(":"))
        year = int(toks[-1])
        if "PM" in toks and hh != 12:
            hh += 12
        if "AM" in toks and hh == 12:
            hh = 0
        return _dt.datetime(year, mon, day, hh, mm, ss)
    except (IndexError, KeyError, ValueError):
        return None


_LINE_RE = re.compile(r'^(\S+?):\s+(.*)$')
_RUN_RE = re.compile(r'Running Module (-\S+)')
_DONE_RE = re.compile(r'Module (-\S+) completed!')
_FAIL_RE = re.compile(r'ERROR: Module (-\S+) failed!(?: \(log: (.*?)\))?')
_SUMMARY_RE = re.compile(r'Processing_Summary_(.+)\.txt$')


def parse_summary_file(path):
    """Return list of events: (datetime|None, kind, module, extra)."""
    events = []
    try:
        fh = open(path, errors="replace")
    except OSError:
        return events
    with fh:
        for line in fh:
            line = line.rstrip("\n")
            m = _LINE_RE.match(line)
            if not m:
                continue
            ts, msg = parse_p2_date(m.group(1)), m.group(2)
            if (r := _RUN_RE.search(msg)):
                events.append((ts, "running", r.group(1), ""))
            elif (r := _DONE_RE.search(msg)):
                events.append((ts, "done", r.group(1), ""))
            elif (r := _FAIL_RE.search(msg)):
                events.append((ts, "failed", r.group(1), r.group(2) or ""))
            elif "completed requested operations successfully" in msg:
                events.append((ts, "success", "", ""))
            elif "ERROR" in msg:
                events.append((ts, "error", "", msg.strip()))
    return events


def _fmt(dt):
    return dt.strftime("%Y-%m-%d %H:%M") if dt else ""


def subject_status(cfg, project, sid, modules, active_jobs=None):
    """Full status dict for InProcess/<sid>."""
    sdir = os.path.join(cfg.projects_root, project, "InProcess", sid)
    st = {
        "id": sid, "dir": sdir, "exists": os.path.isdir(sdir),
        "params": False, "locked": False, "modules": {}, "last_run": None,
        "last_command": "", "history": [], "outputs": {}, "job": None,
    }
    if not st["exists"]:
        return st
    st["params"] = os.path.isfile(os.path.join(sdir, f"{sid}.params"))
    st["day1"] = read_day1(os.path.join(sdir, f"{sid}.params")) if st["params"] else ""
    st["locked"] = os.path.exists(os.path.join(sdir, ".inprocess"))
    # execution history
    try:
        with open(os.path.join(sdir, f"{sid}_Execution.log"), errors="replace") as fh:
            hist = [l.strip() for l in fh if l.strip()]
        st["history"] = hist[-8:]
        if hist:
            st["last_command"] = hist[-1]
    except OSError:
        pass
    # summaries, ordered by parsed date (fallback mtime)
    logs = os.path.join(sdir, "Logs")
    summaries = []
    try:
        with os.scandir(logs) as it:
            for e in it:
                m = _SUMMARY_RE.match(e.name)
                if m and e.is_file():
                    dt = parse_p2_date(m.group(1))
                    summaries.append((dt or _dt.datetime.fromtimestamp(e.stat().st_mtime), e.path))
    except OSError:
        pass
    summaries.sort()
    summary_mtime = 0
    if summaries:
        try:
            summary_mtime = os.path.getmtime(summaries[-1][1])
        except OSError:
            pass
    st["last_activity"] = time.strftime("%Y-%m-%d %H:%M", time.localtime(summary_mtime)) if summary_mtime else ""
    latest = {}   # module -> (dt, kind, extra)
    last_run = None
    for dt, path in summaries:
        events = parse_summary_file(path)
        run = {"file": path, "started": _fmt(dt), "modules": [], "result": "incomplete", "errors": []}
        for ets, kind, mod, extra in events:
            ets = ets or dt
            if mod:
                latest[mod] = (ets, kind, extra)
                if kind == "running":
                    run["modules"].append(mod)
                if kind == "failed":
                    run["result"] = "failed"
                    run["errors"].append(f"{mod} failed" + (f" ({os.path.basename(extra)})" if extra else ""))
            elif kind == "success":
                run["result"] = "success"
            elif kind == "error":
                run["result"] = "failed"
                run["errors"].append(extra)
        last_run = run
    st["last_run"] = last_run
    # job (from registry) -----------------------------------------------------
    job = (active_jobs or {}).get(sid)
    st["job"] = job
    job_active = bool(job and job.get("state") in ("PENDING", "RUNNING", "CONFIGURING", "COMPLETING"))
    # per-module state --------------------------------------------------------
    for m in modules:
        flag = m["flag"]
        ent = latest.get(flag)
        if not ent:
            state, when, extra = "none", "", ""
        else:
            dt, kind, extra = ent
            when = _fmt(dt)
            if kind == "running":
                # a "Running" line with no completion: live if a GUI job is active, or if the
                # lock exists and the summary was touched recently; otherwise a crashed run.
                if job_active:
                    state = "running"
                elif st["locked"] and (time.time() - summary_mtime) < 12 * 3600:
                    state = "running"
                else:
                    state = "interrupted"
            else:
                state = kind
        logf = os.path.join(logs, m["log_base"] + ".execution")
        st["modules"][flag] = {"state": state, "when": when,
                               "log": logf if os.path.isfile(logf) else (extra or "")}
    st["outputs"] = output_checks(sdir, sid)
    return st


def output_checks(sdir, sid):
    """Cheap existence checks for the main products of each stage."""
    def any_glob(sub, pattern):
        d = os.path.join(sdir, sub)
        try:
            rx = re.compile(pattern)
            with os.scandir(d) as it:
                return any(rx.search(e.name) for e in it)
        except OSError:
            return False
    fs = False
    fsd = os.path.join(sdir, "Freesurfer")
    try:
        for v in os.listdir(fsd):
            if os.path.isfile(os.path.join(fsd, v, sid, "scripts", "recon-all.done")) or \
               os.path.isfile(os.path.join(fsd, v, "scripts", "recon-all.done")) or \
               os.path.isdir(os.path.join(fsd, v, "surf")):
                fs = True
    except OSError:
        pass
    return {
        "T1": os.path.isdir(os.path.join(sdir, "Anatomical", "Volume", "T1")),
        "Freesurfer": fs,
        "BOLD": any_glob("Functional/Volume", r"_xr3d.*_atl\.nii(\.gz)?$"),
        "fMRI": any_glob("Functional/Volume", r"_uout_bpss.*\.nii(\.gz)?$"),
        "surf": any_glob("Functional/Surface", r"\.dtseries\.nii$"),
        "QC": any_glob("QC", r"FD_Thresholding_frame_count\.txt$"),
    }


def list_inprocess(cfg, project):
    """Session folders in InProcess (<Subject>_<Session>).  Folders without an underscore
    (e.g. TemplateMatching, analysis outputs) are not sessions and are skipped."""
    return [d for d in _listdirs(os.path.join(cfg.projects_root, project, "InProcess")) if "_" in d]


def project_overview(cfg, project, modules, active_jobs=None, only=None):
    """Status table for a project.  Rows = union of Scans (sub x ses) and
    InProcess folders."""
    scans = list_scans(cfg, project) if os.path.isdir(os.path.join(cfg.scans_dir, project)) else {}
    inproc = set(list_inprocess(cfg, project))
    rows = {}
    for sub, sess in scans.items():
        for ses in sess:
            sid = f"{sub}_{ses}"
            rows[sid] = {"subject": sub, "session": ses, "in_scans": True}
    for sid in inproc:
        if sid not in rows:
            sub, _, ses = sid.partition("_")
            rows[sid] = {"subject": sub, "session": ses, "in_scans": False}
    if only:
        rows = {k: v for k, v in rows.items() if k in only}
    out = []
    for sid in sorted(rows):
        r = rows[sid]
        r.update(subject_status(cfg, project, sid, modules, active_jobs))
        r["propagated"] = sid in inproc
        out.append(r)
    other = {}
    pdir = os.path.join(cfg.projects_root, project)
    for folder in ("Participants", "Excluded", "Pending_PI_Review"):
        subs = _listdirs(os.path.join(pdir, folder))
        if subs:
            other[folder] = subs
    return {"project": project, "rows": out, "other_folders": other,
            "study_cfg": os.path.isfile(os.path.join(pdir, "Study.cfg")),
            "project_dir_exists": os.path.isdir(pdir), "scans_dir_exists": bool(scans) or
            os.path.isdir(os.path.join(cfg.scans_dir, project)), "generated": time.time()}


# ---------------------------------------------------------------------------
# Subject-list parsing
# ---------------------------------------------------------------------------
def parse_subject_list(text, scans=None):
    """Accepts lines like:
         SP01                 -> all sessions of SP01 (from scans if given)
         SP01 Session01       / SP01,Session01 / SP01/Session01 / SP01_Session01
         /path/to/InProcess/SP01_Session01
       Returns list of (subject, session|None)."""
    out, seen = [], set()
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip().rstrip("/")
        if not line:
            continue
        line = os.path.basename(line) if "/" in line and os.path.isabs(line) else line
        for sep in (",", "\t", "/", " "):
            if sep in line:
                sub, ses = (x.strip() for x in line.split(sep, 1))
                break
        else:
            sub, ses = line, None
            if scans is not None and sub not in scans and "_" in sub:
                s2, _, ss = sub.partition("_")
                if s2 in scans and (not scans[s2] or ss in scans[s2]):
                    sub, ses = s2, ss
            elif scans is None and "_" in sub:
                s2, _, ss = sub.partition("_")
                sub, ses = s2, ss
        key = (sub, ses)
        if key not in seen:
            seen.add(key)
            out.append(key)
    return out


# ---------------------------------------------------------------------------
# multi-session (day1_path)
# ---------------------------------------------------------------------------
_DAY1_RE = re.compile(r'^\s*set\s+day1_path\s*=\s*(\S+)')


def read_day1(params_path):
    """Return the InProcess id of the day-1 session set in a params file ('' = this is day 1)."""
    try:
        with open(params_path, errors="replace") as fh:
            for line in fh:
                m = _DAY1_RE.match(line)
                if m:
                    return os.path.basename(m.group(1).rstrip("/"))
    except OSError:
        pass
    return ""


def has_t1(cfg, project, sid):
    d = os.path.join(cfg.projects_root, project, "InProcess", sid, "Anatomical", "Volume", "T1")
    return os.path.isfile(os.path.join(d, f"{sid}_T1.nii.gz")) or os.path.isfile(os.path.join(d, f"{sid}_T1.nii"))


def day1_candidates(cfg, project, subject, exclude_sid=""):
    """Other InProcess sessions of the same subject: [{sid, has_t1, day1}] sorted by name."""
    out = []
    for sid in list_inprocess(cfg, project):
        if sid == exclude_sid:
            continue
        if sid == subject or sid.startswith(subject + "_"):
            params = os.path.join(cfg.projects_root, project, "InProcess", sid, f"{sid}.params")
            out.append({"sid": sid, "has_t1": has_t1(cfg, project, sid), "day1": read_day1(params)})
    return out
