"""
Local HTTP server: JSON API + static front-end.  Standard library only.
"""
import json
import mimetypes
import os
import posixpath
import re
import shutil
import sys
import threading
import time
import traceback
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import config as _cfg
from . import pipeline, qc, surfqc, tm as _tm, slurm as _slurm

STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")


class App:
    def __init__(self, cfg):
        self.cfg = cfg
        _cfg.ensure_dir(_cfg.STATE_DIR, cfg.get("study_group"))
        user = _cfg.current_user()
        regp = os.path.join(_cfg.STATE_DIR, f"jobs_{user}.json")
        legacy = os.path.join(_cfg.STATE_DIR, "jobs.json")
        if not os.path.exists(regp) and os.path.isfile(legacy):
            try:
                import pwd
                if pwd.getpwuid(os.stat(legacy).st_uid).pw_name == user:
                    shutil.copyfile(legacy, regp)       # first run after the multi-user change
            except (KeyError, OSError, ImportError):
                pass
        self.reg = _slurm.JobRegistry(regp)
        if os.path.exists(regp):
            _cfg.fix_group(regp, cfg.get("study_group"))
        self.slurm = _slurm.Slurm(cfg, self.reg)
        self._p2cfg = None
        self._p2cfg_ts = 0
        self._parts = None
        self._parts_ts = 0
        self.lock = threading.Lock()
        t = threading.Thread(target=self._poller, daemon=True)
        t.start()

    # -- cached bits -----------------------------------------------------------
    def p2cfg(self):
        if not self._p2cfg or time.time() - self._p2cfg_ts > 300:
            self._p2cfg = pipeline.parse_p2_cfg(self.cfg.pp_scripts)
            self._p2cfg_ts = time.time()
        return self._p2cfg

    def partitions(self):
        if self._parts is None or time.time() - self._parts_ts > 600:
            self._parts = self.slurm.partitions()
            self._parts_ts = time.time()
        return self._parts

    def _poller(self):
        while True:
            try:
                self.slurm.refresh()
            except Exception:
                traceback.print_exc()
            time.sleep(max(10, int(self.cfg.get("refresh_seconds") or 30)))

    # -- path safety -------------------------------------------------------------
    def allowed_roots(self):
        roots = [self.cfg.projects_home, _cfg.GUI_ROOT]
        if self.cfg.get("scratch"):
            roots.append(self.cfg.get("scratch"))
        return [os.path.realpath(r) for r in roots if r]

    def check_path(self, path):
        rp = os.path.realpath(path)
        for r in self.allowed_roots():
            if rp == r or rp.startswith(r + os.sep):
                return rp
        # symlinked project data may resolve elsewhere: allow if the un-resolved path is under a root
        ap = os.path.abspath(path)
        for r in self.allowed_roots():
            if ap.startswith(r + os.sep):
                return ap
        raise PermissionError(f"path outside allowed roots: {path}")

    # -- API ---------------------------------------------------------------------
    def api_state(self, q):
        cfg = self.cfg.public()
        return {
            "config": cfg,
            "fake_slurm": self.slurm.fake,
            "scan_projects": pipeline.list_scan_projects(self.cfg),
            "projects": pipeline.list_projects(self.cfg),
            "modules": self.p2cfg()["modules"],
            "overrides": self.p2cfg()["overrides"],
            "fs_versions": self.p2cfg().get("fs_versions", []),
            "partitions": self.partitions(),
            "user": os.environ.get("USER", ""),
            "host": os.uname().nodename,
            "numpy": qc.np is not None,
            "ssh_host": self.cfg.get("slurm_ssh_host") or "",
            "ssh_master": self.slurm.ssh_master_alive(),
        }

    def api_project(self, q):
        name = q["name"]
        jobs = self.reg.active_by_subject(name)
        ov = pipeline.project_overview(self.cfg, name, self.p2cfg()["modules"], jobs)
        pdir = os.path.join(self.cfg.projects_root, name)
        ov["study_cfg_parsed"] = pipeline.parse_study_cfg(os.path.join(pdir, "Study.cfg"))
        ov["scans"] = pipeline.list_scans(self.cfg, name)
        return ov

    def api_scans(self, q):
        return pipeline.list_scans(self.cfg, q["project"])

    def api_parse_list(self, body):
        project = body["project"]
        scans = pipeline.list_scans(self.cfg, project)
        inproc = set(pipeline.list_inprocess(self.cfg, project))
        pairs = pipeline.parse_subject_list(body.get("text", ""), scans)
        out = []
        for sub, ses in pairs:
            if ses is None:
                sess = scans.get(sub, [])
                if not sess:
                    out.append({"subject": sub, "session": None, "sid": sub, "in_scans": False,
                                "propagated": sub in inproc, "warning": "subject not found in Scans"})
                for s in sess:
                    out.append({"subject": sub, "session": s, "sid": f"{sub}_{s}", "in_scans": True,
                                "propagated": f"{sub}_{s}" in inproc})
            else:
                sid = f"{sub}_{ses}"
                ok = sub in scans and ses in scans[sub]
                out.append({"subject": sub, "session": ses, "sid": sid, "in_scans": ok,
                            "propagated": sid in inproc,
                            "warning": "" if ok or sid in inproc else "not found in Scans or InProcess"})
        # multi-session info: current day1 (from params) and candidate day-1 sessions
        selected = {p["sid"] for p in out}
        for p in out:
            sdir = os.path.join(self.cfg.projects_root, project, "InProcess", p["sid"])
            p["day1"] = pipeline.read_day1(os.path.join(sdir, f"{p['sid']}.params")) if p["propagated"] else ""
            cands = pipeline.day1_candidates(self.cfg, project, p["subject"], exclude_sid=p["sid"])
            # sessions in this same batch (not propagated yet) are candidates too
            known = {c["sid"] for c in cands}
            for q in out:
                if q["subject"] == p["subject"] and q["sid"] != p["sid"] and q["sid"] not in known:
                    cands.append({"sid": q["sid"], "has_t1": False, "day1": "", "in_batch": True})
            p["day1_candidates"] = sorted(cands, key=lambda c: c["sid"])
            # suggestion: earliest other session that is itself a day 1 and has a T1
            sugg = [c for c in p["day1_candidates"] if c["has_t1"] and not c["day1"] and c["sid"] < p["sid"]]
            p["day1_suggested"] = sugg[0]["sid"] if sugg and not p["day1"] else ""
        return {"pairs": out}

    def api_day1(self, q):
        project, sid = q["project"], q["sid"]
        sub = sid.split("_", 1)[0]
        sdir = os.path.join(self.cfg.projects_root, project, "InProcess", sid)
        return {"sid": sid, "day1": pipeline.read_day1(os.path.join(sdir, f"{sid}.params")),
                "candidates": pipeline.day1_candidates(self.cfg, project, sub, exclude_sid=sid)}

    def api_set_day1(self, body):
        """Set/clear day1_path in an existing params file right now."""
        project, sid, day1 = body["project"], body["sid"], (body.get("day1") or "").strip()
        sdir = os.path.join(self.cfg.projects_root, project, "InProcess", sid)
        params = self.check_path(os.path.join(sdir, f"{sid}.params"))
        if not os.path.isfile(params):
            raise ValueError(f"{sid} has no params file yet (propagate first)")
        if day1 == sid:
            raise ValueError("a session cannot be its own day 1")
        day1_path = os.path.join(self.cfg.projects_root, project, "InProcess", day1) if day1 else ""
        if day1 and not os.path.isdir(day1_path):
            raise ValueError(f"day-1 session folder does not exist: {day1_path}")
        from . import set_day1 as _sd
        line = _sd.set_day1(params, day1_path)
        _cfg.fix_group(params, self.cfg.get("study_group"))
        warn = ""
        if day1 and not pipeline.has_t1(self.cfg, project, day1):
            warn = f"{day1} has no registered T1 yet (Anatomical/Volume/T1/{day1}_T1.nii.gz); run -reg on it first or P2 will refuse."
        return {"ok": True, "line": line, "warning": warn}

    def api_studycfg(self, q):
        pdir = os.path.join(self.cfg.projects_root, q["project"])
        parsed = pipeline.parse_study_cfg(os.path.join(pdir, "Study.cfg"))
        parsed["defaults"] = [{"name": n, "value": v, "help": h} for n, v, h in pipeline.STUDY_CFG_DEFAULTS]
        parsed["atlases"] = pipeline.parse_p1_atlases(self.cfg.pp_scripts)
        parsed["project_dir_exists"] = os.path.isdir(pdir)
        parsed["scratch_default"] = _cfg.per_user(os.path.join(self.cfg.get("scratch") or "$SCRATCH", q["project"]))
        return parsed

    def api_save_studycfg(self, body):
        project = body["project"]
        values = {k: str(v) for k, v in body.get("values", {}).items()}
        group = self.cfg.get("study_group")
        pdir = os.path.join(self.cfg.projects_root, project)
        created = []
        if not os.path.isdir(pdir):
            if not body.get("create"):
                raise ValueError("project folder does not exist; pass create=true")
            for sub in ("", "Participants", "Analysis", "Excluded", "InProcess", "logs"):
                p = os.path.join(pdir, sub)
                if not os.path.isdir(p):
                    _cfg.ensure_dir(p, group)
                    created.append(p)
            # Scans folder for the project
            sdir = os.path.join(self.cfg.scans_dir, project)
            if not os.path.isdir(sdir):
                _cfg.ensure_dir(sdir, group)
                created.append(sdir)
        for sub in ("InProcess", "logs"):
            p = os.path.join(pdir, sub)
            if not os.path.isdir(p):
                _cfg.ensure_dir(p, group)
                created.append(p)
        scratch = _cfg.expand_user(values.get("ScratchFolder", ""))     # Study.cfg may say /gpfs/scratch/$USER/...
        if scratch and scratch.startswith("/") and "$" not in scratch and not os.path.isdir(scratch):
            try:
                _cfg.ensure_dir(scratch, group)
                created.append(scratch)
            except OSError as e:
                created.append(f"(could not create scratch {scratch}: {e})")
        cfg_path = os.path.join(pdir, "Study.cfg")
        existing = pipeline.parse_study_cfg(cfg_path)
        if existing["exists"]:
            shutil.copy2(cfg_path, cfg_path + ".bak")
        else:
            # a fresh Study.cfg must define every variable P2 expects
            full = {n: v for n, v, _ in pipeline.STUDY_CFG_DEFAULTS}
            full["ScratchFolder"] = _cfg.per_user(os.path.join(self.cfg.get("scratch") or "$SCRATCH", project))
            full["StudyGroup"] = group or full["StudyGroup"]
            atl = pipeline.parse_p1_atlases(self.cfg.pp_scripts)
            if atl:
                full["target"] = atl[0]
            full.update(values)
            values = full
        text = pipeline.render_study_cfg(values, existing.get("raw", ""))
        with open(cfg_path, "w") as fh:
            fh.write(text)
        _cfg.fix_group(cfg_path, group)
        return {"ok": True, "path": cfg_path, "created": created, "raw": text}

    def api_submit(self, body):
        project = body["project"]
        pairs = [(p["subject"], p.get("session")) for p in body.get("pairs", [])]
        day1_map = {}
        for p in body.get("pairs", []):
            sid = f"{p['subject']}_{p['session']}" if p.get("session") else p["subject"]
            d1 = (p.get("day1") or "").strip()
            if d1:
                if d1 == sid:
                    raise ValueError(f"{sid}: a session cannot be its own day 1")
                day1_map[sid] = os.path.join(self.cfg.projects_root, project, "InProcess", d1)
        steps = [s for s in body.get("steps", []) if s.startswith("-")]
        valid = {m["flag"] for m in self.p2cfg()["modules"]}
        bad = [s for s in steps if s not in valid]
        if bad:
            raise ValueError(f"unknown P2 modules: {bad}")
        # canonical execution order (config step_order, then P2.cfg order)
        cfg_order = [m["flag"] for m in self.p2cfg()["modules"]]
        pref = self.cfg.get("step_order") or []
        steps.sort(key=lambda s: (pref.index(s) if s in pref else 50 + cfg_order.index(s)))
        overrides = []
        for o in body.get("overrides", []):
            flag = o.get("flag", "")
            if not any(x["flag"] == flag for x in self.p2cfg()["overrides"]):
                raise ValueError(f"unknown override {flag}")
            overrides.append(flag)
            if o.get("value") not in (None, ""):
                overrides.append(str(o["value"]))
        do_prop = bool(body.get("propagate"))
        if not pairs:
            raise ValueError("no subjects selected")
        if not steps and not do_prop:
            raise ValueError("nothing to do: select propagate and/or at least one step")
        pdir = os.path.join(self.cfg.projects_root, project)
        if do_prop and not os.path.isfile(os.path.join(pdir, "Study.cfg")):
            raise ValueError("Projects/%s/Study.cfg does not exist. Create it first (Study.cfg tab) so that "
                             "propagate_scans does not drop into the interactive config_study menu." % project)
        if do_prop and any(s is None for _, s in pairs):
            raise ValueError("propagate needs explicit sessions for every subject")
        # refuse to double-submit an active subject
        act = self.reg.active_by_subject(project)
        busy = [f"{s}_{x}" if x else s for s, x in pairs
                if (j := act.get(f"{s}_{x}" if x else s)) and j.get("state") in _slurm.ACTIVE_STATES]
        if busy and not body.get("force"):
            raise ValueError("these subjects already have an active GUI job: " + ", ".join(busy) +
                             " (tick 'force' to submit anyway)")
        s = dict(self.cfg["slurm"])
        s.update({k: v for k, v in (body.get("slurm") or {}).items() if v not in (None, "")})
        # notification address/mode for this run ('' = none for this run)
        if "notify_email" in body:
            s["notify_email"] = (body.get("notify_email") or "").strip()
        if body.get("notify_on"):
            s["notify_on"] = body["notify_on"]
        report = _slurm.submit_batch(self.cfg, self.slurm, self.reg, project, pairs, steps, overrides,
                                     do_prop, body.get("propagate_opts") or {}, s,
                                     clear_locks=bool(body.get("clear_locks", True)),
                                     dry_run=bool(body.get("dry_run")), day1_map=day1_map,
                                     executor="local" if body.get("executor") == "local" else "slurm",
                                     local_serial=bool(body.get("local_serial", True)))
        return report

    def api_jobs(self, q):
        self.slurm.refresh()
        jobs = self.reg.all()
        jobs = [{k: v for k, v in j.items() if not k.startswith("_")} for j in jobs]
        jobs.sort(key=lambda j: j.get("submitted", ""), reverse=True)
        proj = q.get("project")
        if proj:
            jobs = [j for j in jobs if j.get("project") == proj]
        return {"jobs": jobs[:300], "queue": self.slurm.queue_summary(), "fake": self.slurm.fake,
                "last_error": self.slurm.last_error}

    def api_cancel(self, body):
        ok, msg = self.slurm.cancel(str(body["job_id"]))
        return {"ok": ok, "message": msg}

    def api_unlock(self, body):
        sdir = os.path.join(self.cfg.projects_root, body["project"], "InProcess", body["sid"])
        p = os.path.join(sdir, ".inprocess")
        self.check_path(p)
        if os.path.exists(p):
            os.remove(p)
            return {"ok": True, "message": f"removed {p}"}
        return {"ok": True, "message": "no lock present"}

    def api_tail(self, q):
        path = self.check_path(q["path"])
        n = int(q.get("n", 200))
        try:
            size = os.path.getsize(path)
            with open(path, "rb") as fh:
                if size > 256 * 1024:
                    fh.seek(-256 * 1024, 2)
                data = fh.read().decode("utf-8", "replace")
            lines = data.splitlines()
            return {"path": path, "size": size, "lines": lines[-n:], "truncated": len(lines) > n}
        except OSError as e:
            return {"path": path, "error": str(e), "lines": []}

    def api_subject(self, q):
        project, sid = q["project"], q["sid"]
        jobs = self.reg.active_by_subject(project)
        st = pipeline.subject_status(self.cfg, project, sid, self.p2cfg()["modules"], jobs)
        sdir = st["dir"]
        st["metrics"] = qc.subject_metrics(sdir, sid, self._extra_thr()) if st["exists"] else {}
        st["volumes"] = qc.candidate_volumes(sdir, sid) if st["exists"] else []
        logs = []
        try:
            for e in sorted(os.scandir(os.path.join(sdir, "Logs")), key=lambda e: -e.stat().st_mtime):
                if e.is_file():
                    logs.append({"name": e.name, "path": e.path, "size": e.stat().st_size,
                                 "mtime": time.strftime("%Y-%m-%d %H:%M", time.localtime(e.stat().st_mtime))})
        except OSError:
            pass
        st["logs"] = logs
        st["params_path"] = os.path.join(sdir, f"{sid}.params")
        st["params_text"] = ""
        try:
            with open(st["params_path"], errors="replace") as fh:
                st["params_text"] = fh.read(200000)
        except OSError:
            pass
        # sbatch outputs for this subject
        outs = []
        od = os.path.join(self.cfg.projects_root, project, "logs", "UNP_GUI")
        try:
            for e in sorted(os.scandir(od), key=lambda e: -e.stat().st_mtime):
                if e.name.startswith(_slurm._safe(sid) + "_") or (e.name.startswith("propagate_")):
                    outs.append({"name": e.name, "path": e.path, "size": e.stat().st_size})
        except OSError:
            pass
        st["sbatch_logs"] = outs[:20]
        return st

    def _fd_threshold(self, project):
        cfgp = pipeline.parse_study_cfg(os.path.join(self.cfg.projects_root, project, "Study.cfg"))
        for e in cfgp.get("entries", []):
            if e["name"] == "FD_Threshold":
                return e["value"]
        return None

    def _extra_thr(self):
        try:
            return [float(x) for x in (self.cfg.get("qc_extra_fd_thresholds") or [])]
        except (TypeError, ValueError):
            return []

    def _qc_rows(self, project):
        rows = []
        thr = self._extra_thr()
        for sid in pipeline.list_inprocess(self.cfg, project):
            sdir = os.path.join(self.cfg.projects_root, project, "InProcess", sid)
            m = qc.subject_metrics(sdir, sid, thr)
            rows.append({"sid": sid, **m["summary"], "fd_runs": m["fd_runs"], "rms": m["rms"], "fd_extra": m["fd_extra"]})
        return rows

    # -- PFM: template matching + subcortical WTA ------------------------------------------
    def api_tm_overview(self, q):
        project = q["project"]
        rows = []
        _tm.refresh_atlases(self.cfg)
        jobs = self.reg.active_by_subject(project)
        # single-session PFM jobs by SESSION (the registry keys jobs by output name, which may carry a suffix)
        session_jobs = {}
        for j in sorted(self.reg.all(), key=lambda j: j.get("submitted", "")):
            ss = (j.get("tm") or {}).get("sessions") or []
            if j.get("project") == project and j.get("kind") == "PFM" and len(ss) == 1:
                session_jobs[ss[0]] = j
        for sid, sdir in _tm.list_sessions(self.cfg, project).items():
            sub, _, ses = sid.partition("_")
            v = _tm.variants(sdir, sid)
            tmask = _tm.tmask_path(sdir)
            kept = total = None
            try:
                vals = [x for x in open(tmask).read().split() if x.strip()]
                total, kept = len(vals), sum(1 for x in vals if x.strip() not in ("0", "0.0"))
            except OSError:
                pass
            # every output name in the session's TemplateMatching folder: <sid> and <sid><suffix> (e.g. _noGSR_sm2)
            outs = _tm.session_outputs(sdir, sid)
            for o in outs.values():
                for a, info in o["tm"].items():
                    png = surfqc.tm_png_path(sdir, o["name"], a)
                    info["png"] = png if os.path.isfile(png) else ""
            base = outs[""]
            rows.append({"sid": sid, "dir": sdir, "subject": sub, "session": ses, "variants": v, "tmask": os.path.isfile(tmask),
                         "kept": kept, "total": total, "rest_frames": os.path.isfile(_tm.rest_frames_path(sdir)),
                         "fd_file": os.path.isfile(_tm.fd_path(sdir, sid)), "tsnr": _tm.tsnr_ok(sdir, sid),
                         "dconn": base["dconn"], "status": base["status"], "tm": base["tm"], "outputs": outs,
                         "job": session_jobs.get(sid) or jobs.get(sid)})
        concat = _tm.list_concat(self.cfg, project)
        for c in concat:
            for a, info in c["atlases"].items():
                png = surfqc.tm_png_path(c["dir"], c["name"], a)
                info["png"] = png if os.path.isfile(png) else ""
            c["job"] = jobs.get(c["name"])
        script = _tm.run_script(self.cfg)
        return {"rows": rows, "concat": concat, "atlases": {k: v for k, v in _tm.ATLASES.items()},
                "atlas_options": _tm.atlas_options(self.cfg), "default_atlas": _tm.default_atlas(),
                "parcellation_dir": _tm.parcellation_dir(self.cfg),
                "default_variant": _tm.DEFAULT_VARIANT, "wta_methods": _tm.WTA_METHODS, "wta_defaults": _tm.WTA_DEFAULTS,
                "script": script, "script_exists": os.path.isfile(script),
                "suffix_supported": True, "min_dist_supported": True}     # the page refuses a suffix if an older server (without it) is still running

    def api_submit_tm(self, body):
        project = body["project"]
        sids = body.get("sids") or []
        opts = {k: body.get(k) for k in ("atlas", "variant", "steps", "rest_only", "fd", "wta_method", "top_pct",
                                         "smooth", "cleanup", "groups", "rerun", "name", "mem_limit", "tsnr_mask", "suffix", "min_dist", "no_norm")}
        opts["suffix"] = _tm.normalize_suffix(opts.get("suffix"))      # ValueError -> shown to the user
        _tm.refresh_atlases(self.cfg, force=True)
        opts["atlas"] = opts["atlas"] or _tm.default_atlas()
        if opts["atlas"] not in _tm.ATLASES:
            why = (_tm.ATLAS_INFO.get(opts["atlas"]) or {}).get("reason")
            raise ValueError(f"atlas {opts['atlas']} cannot be used: " +
                             (why or f"no such network dlabel in {_tm.parcellation_dir(self.cfg)}"))
        opts["variant"] = opts["variant"] or _tm.DEFAULT_VARIANT
        steps = [s for s in _tm.STEPS if s in (opts.get("steps") or _tm.STEPS)]
        if not steps:
            raise ValueError("no steps selected")
        opts["steps"] = steps
        concat = bool(body.get("concat"))
        # ticked rows of "Concatenated analyses": rerun tm / wta on an existing concatenation (name + sessions from its sessions.txt)
        fixed_groups, fixed_names = [], {}
        if body.get("analyses"):
            if sids:
                raise ValueError("tick either sessions or concatenated analyses, not both")
            known = {c["name"]: c for c in _tm.list_concat(self.cfg, project)}
            for nm in body["analyses"]:
                c = known.get(nm)
                if not c or not c["sessions"]:
                    raise ValueError(f"concatenated analysis {nm}: no sessions.txt")
                if not c["dconn"]:
                    raise ValueError(f"concatenated analysis {nm}: no {nm}.dconn.nii (tick the 'concat' step with sessions instead)")
                fixed_groups.append(list(c["sessions"])); fixed_names[",".join(c["sessions"])] = nm
                m = re.search(r"variant:\s*(\S+)", c.get("options") or "")
                if m:
                    opts["variant"] = m.group(1)
            sids = [s for g in fixed_groups for s in g]
            concat = True
            steps = [s for s in steps if s != "concat"]      # the existing concatenation is reused as is
            if not steps:
                raise ValueError("a concatenated analysis is already concatenated: tick the template matching and/or subcortical WTA step")
            opts["steps"] = steps
            opts["names"] = fixed_names
        if opts.get("wta_method") and opts["wta_method"] not in _tm.WTA_METHODS:
            raise ValueError(f"unknown WTA method {opts['wta_method']}")
        if opts.get("fd") not in (None, ""):
            try:
                opts["fd"] = float(opts["fd"])
            except ValueError:
                raise ValueError("FD cutoff must be a number")
        else:
            opts["fd"] = None
        if "wta" in steps:
            for k, label, lo in (("top_pct", "Top %", 1e-9), ("smooth", "Smoothing σ", 0), ("cleanup", "Min cluster", 0),
                                 ("min_dist", "Min distance to cortex", 0)):
                if opts.get(k) in (None, ""):
                    continue
                try:
                    v = float(opts[k])
                except (TypeError, ValueError):
                    raise ValueError(f"{label} must be a number")
                if v < lo:
                    raise ValueError(f"{label} must be {'> 0' if lo else '>= 0'}")
        if not sids:
            raise ValueError("no sessions selected")
        problems = []
        if "concat" in steps:
            for sid in sids:
                sdir = _tm.find_session_dir(self.cfg, project, sid)
                if not os.path.isfile(_tm.dtseries_path(sdir, sid, opts["variant"])):
                    problems.append(f"{sid}: no {sid}_rsfMRI_{opts['variant']}.dtseries.nii (run -fMRI -surf)")
                if not os.path.isfile(_tm.tmask_path(sdir)):
                    problems.append(f"{sid}: no Functional/TemporalMask/rsfMRI_tmask.txt")
                if opts.get("rest_only") and not os.path.isfile(_tm.rest_frames_path(sdir)):
                    problems.append(f"{sid}: no Functional/Surface/rest_frames.txt (needed for rest-only)")
                if opts.get("fd") and not os.path.isfile(_tm.fd_path(sdir, sid)):
                    problems.append(f"{sid}: no Functional/Movement/{sid}_all_bold_runs.fd (needed for the FD cutoff)")
        opts["tsnr_mask"] = opts.get("tsnr_mask") is not False        # default on
        need_tsnr = ("wta" in steps and "networkseed" in _tm.wta_methods_of(opts.get("wta_method"))) or \
                    ("tm" in steps and opts["tsnr_mask"])
        if need_tsnr:
            for sid in sids:
                if not _tm.tsnr_ok(_tm.find_session_dir(self.cfg, project, sid), sid):
                    problems.append(f"{sid}: no QC/tSNR_fnirt.{{L,R}}.32k.func.gii and no QC/{sid}_CoV.{{L,R}}.32k.func.gii "
                                    "(needed for the low-tSNR mask of the clean map and for the networkseed method; run -QC, "
                                    "or untick 'Mask low-tSNR vertices' if only template matching is run)")
        if problems:
            raise ValueError("cannot run PFM:\n" + "\n".join(problems))
        if fixed_groups:
            groups = fixed_groups
        elif concat:
            by_sub = {}
            for sid in sids:
                by_sub.setdefault(sid.partition("_")[0], []).append(sid)
            groups = list(by_sub.values())
            single = [g for g in groups if len(g) < 2]
            if single:
                raise ValueError("concatenation needs at least 2 sessions per participant: " + ", ".join(g[0] for g in single))
        else:
            groups = [[sid] for sid in sids]
        # existing results are reused by the scripts; make the user say so explicitly
        # (WTA: only the same method + smoothing + cleanup counts - other WTA results are left alone)
        wta_tags = _tm.wta_tags_from_opts(opts) if "wta" in steps else []
        if not opts.get("rerun"):
            exist = []
            for g in groups:
                if concat:
                    nm = fixed_names.get(",".join(g)) or ((opts.get("name") if (opts.get("name") and len(groups) == 1) else _tm.concat_name(g[0].partition("_")[0], len(g))) + opts["suffix"])
                    d = os.path.join(_tm.participant_dir(self.cfg, project, g[0].partition("_")[0]), "TemplateMatching")
                else:
                    nm, d = g[0] + opts["suffix"], _tm.single_out_dir(_tm.find_session_dir(self.cfg, project, g[0]))
                st = _tm.atlas_status(d, nm).get(opts["atlas"]) or {}
                have = []
                if "tm" in steps and st.get("done"):
                    have.append("TM")
                for t in wta_tags:
                    if (st.get("wta") or {}).get(t):
                        have.append(f"WTA {t}")
                if have:
                    exist.append(f"{nm} ({', '.join(have)})")
            if exist:
                raise ValueError("results already exist for: " + ", ".join(exist) +
                                 "\nTick 'rerun (replace existing results)' to recompute them, or untick that step.")
        s = dict(self.cfg["slurm"])
        s.update({k: v for k, v in (body.get("slurm") or {}).items() if v not in (None, "")})
        if "notify_email" in body:
            s["notify_email"] = (body.get("notify_email") or "").strip()
        return _slurm.submit_tm(self.cfg, self.slurm, self.reg, project, groups, opts, s, dry_run=bool(body.get("dry_run")))

    def api_render_tm(self, body):
        """Render network maps for finished template-matching results (synchronous; one image ~20 s)."""
        project = body["project"]
        items = body.get("items") or []          # [{dir, out_dir, session (= output name), sid (surfaces; default session), atlas}]
        atlas_name, mesh = surfqc.study_atlas_mesh(self.cfg, project)
        done, errors = [], []
        for it in items:
            d = self.check_path(it["dir"])
            out_dir = self.check_path(it.get("out_dir") or _tm.single_out_dir(d))
            o = _tm.tm_outputs(out_dir, it["session"], it["atlas"])
            if not os.path.isfile(o["clean"]):
                errors.append(f"{it['session']}: no cleaned assignments")
                continue
            try:
                done.append(surfqc.render_tm(self.cfg, d, it.get("sid") or it["session"], it["atlas"], o["clean"], atlas_name, mesh,
                                             name=it["session"]))
            except Exception as e:      # noqa: BLE001
                errors.append(f"{it['session']} {it['atlas']}: {e}")
        return {"ok": not errors, "rendered": done, "errors": errors}

    def api_render_subcort(self, body):
        """PNG (Workbench scene template over the MNI152 T1) for the subcortical WTA results of the ticked rows."""
        items = body.get("items") or []          # [{dir, out_dir, session, atlas}]
        done, errors = [], []
        for it in items:
            d = self.check_path(it["dir"])
            out_dir = self.check_path(it.get("out_dir") or _tm.single_out_dir(d))
            wta = _tm.wta_status(out_dir, it["session"], it["atlas"])
            if not wta:
                errors.append(f"{it['session']}: no subcortical WTA results for {it['atlas']}")
                continue
            for tag, w in wta.items():
                try:
                    done.append(surfqc.render_subcort(self.cfg, w["file"], _tm.pfm_dir(self.cfg)))
                except Exception as e:      # noqa: BLE001
                    errors.append(f"{it['session']} {tag}: {e}")
        return {"ok": not errors, "rendered": done, "errors": errors}

    def api_wta_table(self, q):
        """by-structure CSV of a subcortical WTA result as a table, network numbers labelled."""
        csvf = self.check_path(q["csv"])
        _tm.refresh_atlases(self.cfg)
        atlas = q.get("atlas") or _tm.default_atlas()
        t = _tm.by_structure(csvf)
        cols = [re.sub(r"^PctNet(\d+)$", lambda m: "% " + _tm.network_label(atlas, m.group(1)), c) for c in t["columns"]]
        params = csvf.replace("_by_structure.csv", "_params.txt")
        try:
            ptxt = open(params).read()
        except OSError:
            ptxt = ""
        return {"columns": cols, "rows": t["rows"], "params": ptxt}

    # -- surface QC renderings / report -----------------------------------------
    def api_surface_qc(self, body):
        project = body["project"]
        sids = body.get("sids") or pipeline.list_inprocess(self.cfg, project)
        metrics = [m for m in (body.get("metrics") or list(surfqc.METRICS)) if m in surfqc.METRICS]
        if not surfqc.find_wb_command(self.cfg):
            raise ValueError("wb_command not found: expected SCRIPTS/workbench/rhel/bin_rh_linux64/wb_command or on PATH")
        if not os.path.isfile(surfqc.TEMPLATE):
            raise ValueError(f"scene template missing: {surfqc.TEMPLATE}")
        if getattr(self, "_render", None) and not self._render.done:
            raise ValueError("a rendering job is already running")
        self._render = surfqc.RenderJob(self.cfg, project, sids, metrics, int(body.get("width") or 1600),
                                        int(body.get("height") or 900), only_missing=bool(body.get("only_missing", True)))
        return {"ok": True, "status": self._render.status()}

    def api_surface_qc_status(self, q):
        job = getattr(self, "_render", None)
        return job.status() if job else {"done": True, "total": 0, "completed": 0, "failed": [], "ok": 0, "skipped": 0}

    def api_qc_report(self, body):
        project = body["project"]
        sids = body.get("sids") or pipeline.list_inprocess(self.cfg, project)
        fd = self._fd_threshold(project)
        rows = self._qc_rows(project)
        path = surfqc.build_report(self.cfg, project, sids, rows, fd, embed=bool(body.get("embed", True)),
                                   extra_thresholds=self._extra_thr())
        return {"ok": True, "path": path, "size": os.path.getsize(path)}

    def api_qc_table(self, q):
        project = q["project"]
        fd = self._fd_threshold(project)
        return {"rows": self._qc_rows(project), "fd_threshold": fd,
                "labels": [{"key": k, "label": l, "help": h} for k, l, h in qc.labels(fd, self._extra_thr())]}

    def _write_csv(self, project, basename, header, rows):
        import csv, datetime
        adir = _cfg.ensure_dir(os.path.join(self.cfg.projects_root, project, "Analysis"), self.cfg.get("study_group"))
        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M")
        paths = [os.path.join(adir, f"{basename}.csv"), os.path.join(adir, f"{basename}_{stamp}.csv")]
        for pth in paths:
            with open(pth, "w", newline="") as fh:
                w = csv.writer(fh)
                w.writerow(header)
                w.writerows(rows)
            _cfg.fix_group(pth, self.cfg.get("study_group"))
        return paths

    def api_export_qc(self, body):
        project = body["project"]
        fd = self._fd_threshold(project)
        labs = qc.labels(fd, self._extra_thr())
        rows = self._qc_rows(project)
        max_runs = max([len(r.get("fd_runs") or []) for r in rows] + [0])
        header = [l for _, l, _ in labs] + [f"run{i + 1} % frames kept" for i in range(max_runs)] + \
                 [f"run{i + 1} RMS motion (mm/frame)" for i in range(max_runs)]
        out = []
        for r in rows:
            vals = [r.get(k, "") for k, _, _ in labs]
            pr = [x["pct"] for x in (r.get("fd_runs") or [])]
            rm = r.get("rms") or []
            vals += pr + [""] * (max_runs - len(pr)) + rm + [""] * (max_runs - len(rm))
            out.append(["" if v is None else v for v in vals])
        paths = self._write_csv(project, "QC_summary", header, out)
        return {"ok": True, "paths": paths, "rows": len(out)}

    def api_export_status(self, body):
        project = body["project"]
        mods = self.p2cfg()["modules"]
        ov = pipeline.project_overview(self.cfg, project, mods, self.reg.active_by_subject(project))
        flags = [m["flag"] for m in mods if any((r["modules"].get(m["flag"]) or {}).get("state", "none") != "none" for r in ov["rows"])]
        header = ["Subject_Session", "subject", "session", "in Scans", "propagated to InProcess", "params file", "day1 session"] + \
                 [f"P2 {f}" for f in flags] + ["last activity", "last run result", "last run errors", "GUI job id", "GUI job state"]
        out = []
        for r in ov["rows"]:
            lr = r.get("last_run") or {}
            out.append([r["id"], r["subject"], r["session"], r["in_scans"], r["propagated"], r["params"], r.get("day1", "")] +
                       [(r["modules"].get(f) or {}).get("state", "none") for f in flags] +
                       [r.get("last_activity", ""), lr.get("result", ""), "; ".join(lr.get("errors", [])),
                        (r.get("job") or {}).get("job_id", ""), (r.get("job") or {}).get("state", "")])
        paths = self._write_csv(project, "processing_status", header, out)
        return {"ok": True, "paths": paths, "rows": len(out)}

    def api_save_params(self, body):
        path = self.check_path(body["path"])
        if not path.endswith(".params"):
            raise ValueError("only .params files can be edited here")
        shutil.copy2(path, path + ".gui.bak")
        with open(path, "w") as fh:
            fh.write(body["text"])
        _cfg.fix_group(path, self.cfg.get("study_group"))
        return {"ok": True}

    def api_slurm_check(self, q):
        """Run `sbatch --version` the way the GUI would, to diagnose the environment."""
        rc, out, err = self.slurm.run(["sbatch", "--version"], timeout=30)
        rcw, which, _ = self.slurm.run(["bash", "-c", "which -a sbatch; cat /etc/redhat-release 2>/dev/null"], timeout=30)
        rc2, out2, err2 = self.slurm.run(["sinfo", "-h", "-o", "%P"], timeout=30)
        return {"sbatch_rc": rc, "sbatch_out": (out or err).strip(), "sinfo_rc": rc2,
                "partitions": out2.split()[:20], "sinfo_err": err2.strip(),
                "prefix": self.slurm.ssh_prefix(), "bin_dir": self.cfg.get("slurm_bin_dir") or "",
                "ssh_host": self.cfg.get("slurm_ssh_host") or "", "ssh_master": self.slurm.ssh_master_alive(),
                "fake": self.slurm.fake}

    def api_config_save(self, body):
        self.cfg.update(body)
        self._p2cfg = None
        self.slurm = _slurm.Slurm(self.cfg, self.reg)
        return {"ok": True, "config": self.cfg.public()}


# ---------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    app: App = None
    server_version = "UNP_GUI/1.0"

    def log_message(self, fmt, *args):
        if os.environ.get("UNP_GUI_DEBUG"):
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    # -- helpers ------------------------------------------------------------------
    def _json(self, obj, code=200):
        data = json.dumps(obj, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _error(self, msg, code=400):
        self._json({"error": msg}, code)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        return json.loads(raw.decode() or "{}")

    def _send_file(self, path, download=False):
        ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
        if path.endswith((".txt", ".log", ".execution", ".params", ".csh", ".cfg", ".sbatch", ".out", ".err", ".dat")):
            ctype = "text/plain; charset=utf-8"
        try:
            size = os.path.getsize(path)
            with open(path, "rb") as fh:
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(size))
                self.send_header("Cache-Control", "no-cache")
                if download:
                    self.send_header("Content-Disposition", f'attachment; filename="{os.path.basename(path)}"')
                self.end_headers()
                shutil.copyfileobj(fh, self.wfile)
        except OSError as e:
            self._error(str(e), 404)

    # -- access control ---------------------------------------------------------
    # The server only listens on 127.0.0.1, but other people logged into the same node can
    # reach that too.  Every launch gets a random token; the link printed/opened at start
    # carries it once (?t=...), after which a per-port cookie authorises the browser.
    token = None
    cookie_name = "unpgui"

    def _authorised(self):
        if not self.token:
            return True
        import http.cookies
        c = http.cookies.SimpleCookie(self.headers.get("Cookie") or "")
        m = c.get(self.cookie_name)
        import hmac
        return bool(m) and hmac.compare_digest(m.value, self.token)

    def _deny(self):
        msg = ("<!doctype html><meta charset=utf-8><title>UNP GUI</title><body style='font:15px system-ui;margin:40px'>"
               "<h2>Access link required</h2><p>Open the link printed in the terminal where you started "
               "<code>start_unp_gui.sh</code> (it contains a one-time key, <code>?t=…</code>).</p>"
               "<p>Each GUI only accepts the person who started it.</p>").encode()
        self.send_response(403)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(msg)))
        self.end_headers()
        self.wfile.write(msg)

    # -- routing ------------------------------------------------------------------
    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        path = u.path
        if self.token and q.get("t"):
            import hmac
            if hmac.compare_digest(q["t"], self.token):
                self.send_response(303)
                self.send_header("Set-Cookie", f"{self.cookie_name}={self.token}; Path=/; HttpOnly; SameSite=Strict")
                self.send_header("Location", "/")
                self.end_headers()
                return
        if not self._authorised():
            if path.startswith("/api/"):
                return self._error("not authorised: open the link printed in the terminal", 403)
            return self._deny()
        try:
            if path.startswith("/api/"):
                name = path[5:]
                if name == "file":
                    return self._send_file(self.app.check_path(q["path"]), download=q.get("dl") == "1")
                if name == "montage":
                    p = self.app.check_path(q["path"])
                    png = qc.montage_png(p, n_slices=int(q.get("n", 20)), axis=int(q.get("axis", 2)))
                    self.send_response(200)
                    self.send_header("Content-Type", "image/png")
                    self.send_header("Content-Length", str(len(png)))
                    self.send_header("Cache-Control", "max-age=300")
                    self.end_headers()
                    return self.wfile.write(png)
                fn = getattr(self.app, "api_" + name, None)
                if not fn:
                    return self._error("unknown endpoint", 404)
                return self._json(fn(q))
            # static
            if path == "/":
                path = "/index.html"
            rel = posixpath.normpath(urllib.parse.unquote(path)).lstrip("/")
            full = os.path.join(STATIC_DIR, rel)
            if not os.path.realpath(full).startswith(os.path.realpath(STATIC_DIR)) or not os.path.isfile(full):
                return self._error("not found", 404)
            return self._send_file(full)
        except PermissionError as e:
            return self._error(str(e), 403)
        except KeyError as e:
            return self._error(f"missing parameter {e}", 400)
        except Exception as e:
            traceback.print_exc()
            return self._error(f"{type(e).__name__}: {e}", 500)

    def do_POST(self):
        u = urllib.parse.urlsplit(self.path)
        name = u.path[5:] if u.path.startswith("/api/") else ""
        if not self._authorised():
            return self._error("not authorised: open the link printed in the terminal", 403)
        try:
            body = self._body()
            fn = getattr(self.app, "api_" + name, None)
            if not fn:
                return self._error("unknown endpoint", 404)
            return self._json(fn(body))
        except PermissionError as e:
            return self._error(str(e), 403)
        except (ValueError, KeyError) as e:
            return self._error(str(e), 400)
        except Exception as e:
            traceback.print_exc()
            return self._error(f"{type(e).__name__}: {e}", 500)


def _open_firefox(url, port):
    """Open the GUI in a NEW Firefox window.  Never fails silently: says what happened, and prints Firefox's own
    error output when it fails (e.g. 'cannot open display')."""
    import shutil as _sh
    import socket
    import subprocess
    import tempfile
    node = socket.gethostname().split(".")[0]
    hint = (f"          open the link above in a browser on {node}, or from your Mac:\n"
            f"          ssh -L {port}:127.0.0.1:{port} -J {_cfg.current_user()}@bigpurple.nyumc.org {_cfg.current_user()}@{node}\n"
            f"          and open the same link in your Mac's browser")
    exe = os.environ.get("UNP_GUI_FIREFOX") or _sh.which("firefox")
    if not exe:
        print(f" browser: firefox not found on {node} - not opening a window.\n{hint}", flush=True)
        return
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        print(f" browser: this terminal has no DISPLAY (not inside a desktop session) - not opening a window.\n{hint}", flush=True)
        return
    fd, log = tempfile.mkstemp(prefix="unpgui_firefox_", suffix=".log")
    try:
        p = subprocess.Popen([exe, "--new-window", url], stdout=fd, stderr=subprocess.STDOUT,
                             stdin=subprocess.DEVNULL, start_new_session=True)
    except OSError as e:
        os.close(fd)
        print(f" browser: could not start {exe}: {e}\n{hint}", flush=True)
        return
    os.close(fd)
    rc = None
    for _ in range(80):                       # up to 8 s
        rc = p.poll()
        if rc is not None:
            break
        time.sleep(0.1)
    try:
        lines = open(log, errors="replace").read().splitlines()
    except OSError:
        lines = []
    noise = ("Locale not supported", "Using the fallback 'C' locale")
    lines = [l for l in lines if l.strip() and not any(n in l for n in noise)]
    if rc is None:
        print(f" browser: Firefox started - new window on DISPLAY={os.environ.get('DISPLAY', '')} ({node})", flush=True)
        return                                # still running: its output keeps going to the temp log
    try:
        os.unlink(log)
    except OSError:
        pass
    if rc == 0 and not any("rror" in l for l in lines):
        print(" browser: opened a new window in the Firefox that was already running "
              "(look for it on this desktop - it may be behind other windows)", flush=True)
        return
    print(f" browser: Firefox FAILED (exit {rc}) - its message:", flush=True)
    for l in (lines[-15:] or ["(no output)"]):
        print("   " + l)
    print(hint, flush=True)


def serve(cfg, host=None, port=None, open_browser=None):
    app = App(cfg)
    Handler.app = app
    host = host or cfg.get("host") or "127.0.0.1"
    port = int(port or cfg.get("port") or 8765)
    httpd = None
    for p in range(port, port + 20):
        try:
            httpd = ThreadingHTTPServer((host, p), Handler)
            port = p
            break
        except OSError:
            continue
    if httpd is None:
        print("ERROR: no free port", file=sys.stderr)
        sys.exit(1)
    import secrets
    Handler.token = None if cfg.get("no_token") else secrets.token_urlsafe(18)
    Handler.cookie_name = f"unpgui_{port}"
    url = f"http://{host}:{port}/" + (f"?t={Handler.token}" if Handler.token else "")
    print("=" * 70)
    print(f" UNP_GUI for {_cfg.current_user()} serving")
    print(f"   {url}")
    print("   (open this exact link; it is personal to this session)")
    print(f" PROJECTS_HOME = {cfg.projects_home}")
    print(f" Slurm: {'FAKE (simulated)' if app.slurm.fake else 'sbatch'}   group: {cfg.get('study_group')}")
    print(" Ctrl-C to stop")
    print("=" * 70, flush=True)
    if open_browser if open_browser is not None else cfg.get("open_browser"):
        threading.Timer(0.8, _open_firefox, args=(url, port)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")
    return url
