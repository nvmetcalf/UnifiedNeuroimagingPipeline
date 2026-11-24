"""
Slurm integration: build sbatch scripts, submit (through `sg <group>` so job
output files belong to the lab group), track jobs in state/jobs.json, poll
squeue/sacct, cancel.

A `fake_slurm` mode simulates jobs locally so the GUI can be exercised away
from the cluster (used by --selftest and by the developer).
"""
import datetime as _dt
import json
import os
import random
import re
import shlex
import subprocess
import threading
import time

from . import config as _cfg

ACTIVE_STATES = {"PENDING", "RUNNING", "CONFIGURING", "COMPLETING", "SUSPENDED", "REQUEUED", "RESIZING"}
TERMINAL_OK = {"COMPLETED"}


def _now():
    return _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _safe(s):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", s)


class JobRegistry:
    """Persistent list of jobs submitted from this GUI."""

    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.jobs = []
        self._load()

    def _load(self):
        try:
            with open(self.path) as fh:
                self.jobs = json.load(fh)
        except (OSError, ValueError):
            self.jobs = []

    def _save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(self.jobs, fh, indent=1)
        os.replace(tmp, self.path)

    def add(self, job):
        with self.lock:
            self.jobs.append(job)
            self._save()

    def update(self, job_id, **fields):
        with self.lock:
            for j in self.jobs:
                if j["job_id"] == job_id:
                    j.update(fields)
            self._save()

    def all(self):
        with self.lock:
            return [dict(j) for j in self.jobs]

    def active_by_subject(self, project):
        """{sid: job} for the most recent job per subject (any state) in project."""
        out = {}
        for j in sorted(self.all(), key=lambda j: j.get("submitted", "")):
            if j.get("project") == project and j.get("sid"):
                out[j["sid"]] = j
        return out

    def prune(self, keep=500):
        with self.lock:
            if len(self.jobs) > keep:
                self.jobs = self.jobs[-keep:]
                self._save()


# ---------------------------------------------------------------------------
# script generation
# ---------------------------------------------------------------------------
def _sbatch_header(name, out, err, part, cpus, mem, tlimit, account, extra, mail_user, mail_type, dependency):
    lines = ["#!/bin/bash",
             f"#SBATCH --job-name={name}",
             f"#SBATCH --partition={part}",
             "#SBATCH --nodes=1", "#SBATCH --ntasks=1",
             f"#SBATCH --cpus-per-task={int(cpus)}",
             f"#SBATCH --mem={mem}",
             f"#SBATCH --time={tlimit}",
             f"#SBATCH --output={out}",
             f"#SBATCH --error={err}"]
    if account:
        lines.append(f"#SBATCH --account={account}")
    if mail_user and mail_type:
        lines += [f"#SBATCH --mail-user={mail_user}", f"#SBATCH --mail-type={mail_type}"]
    if dependency:
        lines.append(f"#SBATCH --dependency={dependency}")
        lines.append("#SBATCH --kill-on-invalid-dep=yes")
    for x in extra or []:
        x = x.strip()
        if x:
            lines.append(x if x.startswith("#SBATCH") else f"#SBATCH {x}")
    return lines


def _common_body(cfg):
    body = ["",
            f"umask {cfg.get('umask', '002')}",
            'START_TIME=$(date)',
            'SLURM_LOG=${SLURM_LOG:-$(scontrol show job "$SLURM_JOB_ID" 2>/dev/null | sed -n "s/.*StdOut=//p" | head -1)}',
            'echo "UNP_GUI job $SLURM_JOB_ID on $(hostname) started $START_TIME"',
            f"source {shlex.quote(cfg['env_script'])}"]
    for line in cfg.get("job_prologue") or []:
        if line.strip():
            body.append(line)
    body += ['echo "PROJECTS_HOME=$PROJECTS_HOME  PP_SCRIPTS=$PP_SCRIPTS"', ""]
    return body


def _notify_block(cfg, slurm_opts, subject_prefix, extra_lines=None):
    """bash lines: send a summary e-mail at the end of a job (mail/mailx, else sendmail)."""
    addr = (slurm_opts.get("notify_email") if slurm_opts.get("notify_email") is not None
            else cfg.get("notify_email")) or ""
    mode = (slurm_opts.get("notify_on") or cfg.get("notify_on") or "always").lower()
    if not addr.strip() or mode == "never":
        return []
    cond = 'if [ "$status" != "0" ]; then' if mode == "fail" else "if true; then"
    lines = [
        "", "# ---- notification e-mail ----",
        f"NOTIFY={shlex.quote(addr.strip())}",
        'RESULT=$([ "$status" = "0" ] && echo OK || echo FAILED)',
        cond,
        f'  SUBJ="[UNP] {subject_prefix} $RESULT (job $SLURM_JOB_ID, $(hostname))"',
        "  {",
        f'    echo "{subject_prefix}"; echo "Result: $RESULT (exit $status)"; echo "Job: $SLURM_JOB_ID on $(hostname)";',
        '    echo "Started: $START_TIME"; echo "Finished: $(date)"; echo "Log: $SLURM_LOG";',
    ]
    for l in extra_lines or []:
        lines.append("    " + l)
    lines += [
        "  } > /tmp/unp_mail_$$.txt",
        '  if command -v mail >/dev/null 2>&1; then mail -s "$SUBJ" "$NOTIFY" < /tmp/unp_mail_$$.txt;',
        '  elif command -v mailx >/dev/null 2>&1; then mailx -s "$SUBJ" "$NOTIFY" < /tmp/unp_mail_$$.txt;',
        '  elif command -v sendmail >/dev/null 2>&1; then { printf "To: %s\\nSubject: %s\\n\\n" "$NOTIFY" "$SUBJ"; cat /tmp/unp_mail_$$.txt; } | sendmail "$NOTIFY";',
        '  else echo "UNP_GUI: no mail/sendmail on this node; e-mail not sent"; fi',
        "  rm -f /tmp/unp_mail_$$.txt",
        "fi",
    ]
    return lines


def build_p2_script(cfg, project, sid, steps, overrides, slurm_opts, out_dir, clear_lock=True, dependency=None,
                    day1_path=None):
    name = f"UNP_{_safe(project)}_{_safe(sid)}"
    out = os.path.join(out_dir, f"{_safe(sid)}_P2_%j.out")
    err = os.path.join(out_dir, f"{_safe(sid)}_P2_%j.err")
    s = slurm_opts
    lines = _sbatch_header(name, out, err, s["partition"], s["cpus_per_task"], s["mem"], s["time"],
                           s.get("account"), s.get("extra_sbatch"), s.get("mail_user"), s.get("mail_type"),
                           dependency)
    lines += _common_body(cfg)
    inproc = os.path.join(cfg.projects_root, project, "InProcess")
    flags = " ".join(steps + overrides)
    lines += [f"cd {shlex.quote(inproc)} || exit 1"]
    if clear_lock:
        lines += [f"rm -f {shlex.quote(os.path.join(inproc, sid, '.inprocess'))}"]
    if day1_path is not None:
        # multi-session: point day1_path at the first session (or clear it) before P2 runs
        helper = os.path.join(_cfg.GUI_ROOT, "unp_gui", "set_day1.py")
        params = os.path.join(inproc, sid, f"{sid}.params")
        lines += [f"python3 {shlex.quote(helper)} {shlex.quote(params)} {shlex.quote(day1_path)} || "
                  f"{{ echo 'UNP_GUI: could not set day1_path'; exit 3; }}"]
    lines += [f'echo "P2 {sid} {flags}"',
              f"P2 {shlex.quote(sid)} {flags}",
              "status=$?",
              'echo "P2 exit status: $status  ($(date))"',
              # P2 returns 0 even when a module failed; detect from the latest summary
              f"summary=$(ls -t {shlex.quote(os.path.join(inproc, sid, 'Logs'))}/Processing_Summary_*.txt 2>/dev/null | head -1)",
              'if [ -n "$summary" ] && grep -q "ERROR" "$summary"; then',
              '  echo "UNP_GUI: errors detected in $summary"; status=2',
              'fi',
              f"chgrp -Rf {shlex.quote(cfg.get('study_group') or '')} {shlex.quote(os.path.join(inproc, sid))} {shlex.quote(out_dir)} 2>/dev/null",
              f"chmod -Rf g+rwX {shlex.quote(os.path.join(inproc, sid))} {shlex.quote(out_dir)} 2>/dev/null"]
    lines += _notify_block(cfg, slurm_opts, f"P2 {project}/{sid} {flags}",
                           ['echo; echo "Processing summary ($summary):"; [ -n "$summary" ] && tail -40 "$summary"',
                            'echo; echo "Last 15 lines of job output:"; [ -n "$SLURM_LOG" ] && tail -15 "$SLURM_LOG"'])
    lines += ["exit $status"]
    return "\n".join(lines) + "\n"


def build_propagate_script(cfg, project, pairs, opts, slurm_opts, out_dir):
    """pairs: list of (subject, session|None).  opts: {force, no_init, extra}"""
    name = f"UNP_prop_{_safe(project)}"
    out = os.path.join(out_dir, f"propagate_%j.out")
    err = os.path.join(out_dir, f"propagate_%j.err")
    s = slurm_opts
    lines = _sbatch_header(name, out, err, s["propagate_partition"], s["propagate_cpus"], s["propagate_mem"],
                           s["propagate_time"], s.get("account"), s.get("extra_sbatch"), s.get("mail_user"),
                           s.get("mail_type"), None)
    lines += _common_body(cfg)
    lines += [f"cd {shlex.quote(cfg.projects_home)} || exit 1", "rc=0"]
    flags = ""
    if opts.get("force"):
        flags += " -f"
    if opts.get("no_init"):
        flags += " -n"
    if opts.get("extra"):
        flags += " " + opts["extra"]
    # group sessions by subject so each subject is one propagate_scans call
    by_sub = {}
    for sub, ses in pairs:
        by_sub.setdefault(sub, [])
        if ses:
            by_sub[sub].append(ses)
    for sub, sess in by_sub.items():
        cmd = f"propagate_scans {shlex.quote(project)} -L {shlex.quote(sub)}"
        if sess:
            cmd += f" -S {shlex.quote(' '.join(sess))}"
        cmd += flags
        # propagate_scans asks yes/no only when project/scan folders are missing;
        # the GUI creates them beforehand, but answer "yes" defensively.
        lines += [f'echo "=== {cmd}"', f"yes | {cmd} || rc=1"]
    lines += [f"chgrp -Rf {shlex.quote(cfg.get('study_group') or '')} {shlex.quote(os.path.join(cfg.projects_root, project))} 2>/dev/null",
              f"chmod -Rf g+rwX {shlex.quote(os.path.join(cfg.projects_root, project, 'InProcess'))} {shlex.quote(out_dir)} 2>/dev/null",
              'echo "propagate finished rc=$rc ($(date))"', "status=$rc"]
    subs = ", ".join(f"{a}_{b}" if b else a for a, b in pairs)
    lines += _notify_block(cfg, slurm_opts, f"propagate_scans {project}: {subs}",
                           ['echo; echo "Last 40 lines of job output:"; [ -n "$SLURM_LOG" ] && tail -40 "$SLURM_LOG"'])
    lines += ["exit $status"]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Submission / polling
# ---------------------------------------------------------------------------
class Slurm:
    def __init__(self, cfg, registry):
        self.cfg = cfg
        self.reg = registry
        self.fake = bool(cfg.get("fake_slurm")) or (not cfg.get("_sbatch_available") and not cfg.get("slurm_cmd_prefix")
                                                    and not cfg.get("slurm_bin_dir") and not cfg.get("slurm_ssh_host"))
        self._fake_threads = {}
        self._fake_counter = 100000 + random.randint(0, 999)
        self.last_error = ""
        self.sg_ok = self._probe_sg()

    def _probe_sg(self):
        """sg is not permitted everywhere (BigPurple: 'setgid: Operation not permitted')."""
        group = self.cfg.get("study_group")
        if not (self.cfg.get("use_sg") and group and self.cfg.get("_sg_available")):
            return False
        rc, out, err = self.run(["sg", group, "-c", "true"], timeout=10)
        if rc != 0:
            self.last_error = f"sg {group} not usable ({(err or out).strip()}); submitting without sg"
            print("NOTE:", self.last_error)
        return rc == 0

    # -- helpers ---------------------------------------------------------------
    SLURM_CMDS = ("sbatch", "squeue", "sacct", "scancel", "sinfo")

    def clean_env(self):
        """Environment for Slurm client calls: drop loader variables that a
        sourced pipeline/module environment may have polluted."""
        env = dict(os.environ)
        for k in ("LD_LIBRARY_PATH", "LD_PRELOAD", "PYTHONPATH", "PYTHONHOME"):
            env.pop(k, None)
        bd = (self.cfg.get("slurm_bin_dir") or "").strip()
        if bd:
            env["PATH"] = bd + os.pathsep + env.get("PATH", "")
        return env

    def control_path(self):
        return os.path.join(os.path.expanduser("~"), ".ssh", "unp_gui_%r@%h:%p")

    def ssh_prefix(self):
        """Prefix for Slurm calls: explicit slurm_cmd_prefix, else a multiplexed
        ssh to slurm_ssh_host (master opened by start_unp_gui.sh)."""
        explicit = list(self.cfg.get("slurm_cmd_prefix") or [])
        if explicit:
            return explicit
        host = (self.cfg.get("slurm_ssh_host") or "").strip()
        if host and os.environ.get("UNP_GUI_LOCAL_SLURM"):
            host = ""          # launcher found a working local sbatch
        if host:
            return ["ssh", "-F", "/dev/null", "-o", "ControlPath=" + self.control_path(), "-o", "ControlMaster=no",
                    "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=no", "-o", "LogLevel=ERROR", host]
        return []

    def ssh_master_alive(self):
        host = (self.cfg.get("slurm_ssh_host") or "").strip()
        if not host or self.cfg.get("slurm_cmd_prefix") or os.environ.get("UNP_GUI_LOCAL_SLURM"):
            return None
        try:
            p = subprocess.run(["ssh", "-F", "/dev/null", "-o", "ControlPath=" + self.control_path(), "-O", "check", host],
                               capture_output=True, text=True, timeout=15)
            return p.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def _master_ok(self):
        """`ssh -O check` only talks to the local control socket (no network login).
        Cached for 20 s."""
        now = time.time()
        c = getattr(self, "_master_cache", None)
        if c and now - c[0] < 20:
            return c[1]
        ok = bool(self.ssh_master_alive())
        self._master_cache = (now, ok)
        return ok

    def run(self, args, timeout=60):
        prefix = self.ssh_prefix()
        bin_dir = self.cfg.get("slurm_bin_dir") or ""
        if bin_dir and args and args[0] in self.SLURM_CMDS:
            args = [os.path.join(bin_dir, args[0])] + list(args[1:])
        if prefix and args and (os.path.basename(args[0]) in self.SLURM_CMDS):
            # Never let the GUI open a NEW ssh login by itself: only ride on the master
            # connection opened (with your password/ticket) by start_unp_gui.sh.  Without
            # this, a dead master made every 30-s poll a fresh failed login attempt to
            # the login nodes, which can get the account/host blocked.
            if not self.cfg.get("slurm_cmd_prefix") and not self._master_ok():
                return 255, "", ("ssh connection to the login node is not open; the GUI will not "
                                 "reconnect by itself. Quit and restart start_unp_gui.sh.")
            # remote execution: login shell (loads the slurm module on BigPurple) and the
            # Slurm client called by absolute path when we know where it lives.
            bd = (self.cfg.get("slurm_bin_dir") or "").strip() or "/cm/shared/apps/slurm/current/bin"
            exe = shlex.quote(os.path.join(bd, args[0]))
            rest = " ".join(shlex.quote(a) for a in args[1:])
            remote = f'if [ -x {exe} ]; then {exe} {rest}; else {shlex.quote(args[0])} {rest}; fi'
            args = prefix + ["bash -l -c " + shlex.quote(remote)]
        try:
            p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=self.clean_env())
            return p.returncode, p.stdout, p.stderr
        except (OSError, subprocess.TimeoutExpired) as e:
            return 1, "", str(e)

    def submit_script(self, script_path):
        """Return (job_id, message)."""
        if self.fake:
            self._fake_counter += 1
            jid = str(self._fake_counter)
            return jid, "fake submission"
        cmd = ["sbatch", "--parsable", script_path]
        if self.cfg.get("slurm_bin_dir"):
            cmd[0] = os.path.join(self.cfg["slurm_bin_dir"], "sbatch")
        group = self.cfg.get("study_group")
        if self.sg_ok and not self.ssh_prefix():
            rc, out, err = self.run(["sg", group, "-c", " ".join(shlex.quote(c) for c in cmd)])
            if rc != 0 and not out.strip():
                rc, out, err = self.run(cmd)     # any sg problem -> plain sbatch
                err = "(sg failed, submitted without sg) " + err
        else:
            rc, out, err = self.run(cmd)
        if rc != 0:
            msg = (err or out).strip()
            if self.ssh_master_alive() is False:
                msg += "  [ssh connection to the login node is not open - restart start_unp_gui.sh and enter your password]"
            return None, msg
        jid = out.strip().split(";")[0]
        return jid, err.strip()

    # -- local (background) execution ---------------------------------------------
    LOCAL_DIR = os.path.join(_cfg.STATE_DIR, "local")

    def _lpath(self, jid, ext):
        return os.path.join(self.LOCAL_DIR, f"{jid}.{ext}")

    def submit_local(self, script_path, out_tmpl, err_tmpl, wait_for=(), require_ok=()):
        """Run an sbatch-style script with bash on this node, detached from the GUI.
        wait_for: local job ids to wait for (any result); require_ok: ids that must have exit 0."""
        import socket
        import subprocess as _sp
        _cfg.ensure_dir(self.LOCAL_DIR, self.cfg.get("study_group"))
        self._lseq = getattr(self, "_lseq", 0) + 1
        jid = f"L{int(time.time())}{self._lseq:02d}"
        out, err = out_tmpl.replace("%j", jid), err_tmpl.replace("%j", jid)
        q = shlex.quote
        w = ["#!/bin/bash",
             f"export SLURM_JOB_ID={jid} SLURM_LOG={q(out)} UNP_GUI_LOCAL=1",
             f"echo $$ > {q(self._lpath(jid, 'pid'))}"]
        for d in list(wait_for) + [x for x in require_ok if x not in wait_for]:
            w.append(f"while [ ! -f {q(self._lpath(d, 'exit'))} ]; do sleep 10; done")
        for d in require_ok:
            w.append(f"if [ \"$(cat {q(self._lpath(d, 'exit'))})\" != 0 ]; then echo 'dependency {d} did not succeed; not running' > {q(out)}; "
                     f"echo 98 > {q(self._lpath(jid, 'exit'))}; exit 98; fi")
        w += [
            # environment modules are normally present; make sure `module` exists for PipelineEnvironment.sh
            "type module >/dev/null 2>&1 || { [ -f /etc/profile ] && . /etc/profile >/dev/null 2>&1; }",
            f"date > {q(self._lpath(jid, 'started'))}; hostname >> {q(self._lpath(jid, 'started'))}",
            f"bash {q(script_path)} > {q(out)} 2> {q(err)} < /dev/null",
            "rc=$?",
            f"echo $rc > {q(self._lpath(jid, 'exit'))}",
        ]
        wrapper = self._lpath(jid, "sh")
        with open(wrapper, "w") as fh:
            fh.write("\n".join(w) + "\n")
        os.chmod(wrapper, 0o770)
        try:
            pr = _sp.Popen(["bash", wrapper], stdin=_sp.DEVNULL, stdout=_sp.DEVNULL, stderr=_sp.DEVNULL,
                           start_new_session=True, cwd=os.path.dirname(script_path))
        except OSError as e:
            return None, f"could not start: {e}"
        return jid, f"running in background on {socket.gethostname()} (pid {pr.pid})", pr.pid

    def _local_state(self, j):
        import socket
        jid = j["job_id"]
        ex, st = self._lpath(jid, "exit"), self._lpath(jid, "started")
        fields = {}
        if os.path.isfile(st):
            try:
                t0 = os.path.getmtime(st)
                t1 = os.path.getmtime(ex) if os.path.isfile(ex) else time.time()
                e = int(t1 - t0)
                fields["elapsed"] = f"{e // 3600:02d}:{e % 3600 // 60:02d}:{e % 60:02d}"
            except OSError:
                pass
        if os.path.isfile(ex):
            try:
                rc = int(open(ex).read().strip() or "1")
            except ValueError:
                rc = 1
            fields.update(state="COMPLETED" if rc == 0 else ("CANCELLED" if rc in (98, 143) else "FAILED"),
                          exit=f"{rc}:0", finished=fields.get("finished") or _now(),
                          reason="dependency failed" if rc == 98 else "")
            return fields
        alive = None
        if j.get("host") == socket.gethostname() and j.get("pid"):
            try:
                os.kill(int(j["pid"]), 0)
                alive = True
            except (OSError, ValueError):
                alive = False
        if alive is False:
            fields.update(state="FAILED", reason="process ended without exit status (node/session killed?)")
        else:
            fields.update(state="RUNNING" if os.path.isfile(st) else "PENDING",
                          reason="" if os.path.isfile(st) else "waiting for previous job",
                          **({} if alive else {"note": f"background on {j.get('host')}"}))
        return fields

    def cancel(self, job_id):
        if str(job_id).startswith("L"):
            import signal
            j = next((x for x in self.reg.all() if x["job_id"] == job_id), {})
            ok, msg = False, "not running on this node"
            try:
                pid = int(open(self._lpath(job_id, "pid")).read().strip())
                import socket
                if j.get("host") == socket.gethostname():
                    os.killpg(pid, signal.SIGTERM)
                    ok, msg = True, f"killed background job (pid {pid})"
            except (OSError, ValueError) as e:
                msg = str(e)
            if ok or not os.path.isfile(self._lpath(job_id, "exit")):
                try:
                    with open(self._lpath(job_id, "exit"), "w") as fh:
                        fh.write("143\n")
                except OSError:
                    pass
            self.reg.update(job_id, state="CANCELLED", finished=_now(), reason="cancelled")
            return ok, msg
        if self.fake:
            self.reg.update(job_id, state="CANCELLED", finished=_now())
            self._fake_threads.pop(job_id, None)
            return True, "cancelled (fake)"
        rc, out, err = self.run(["scancel", job_id])
        if rc == 0:
            self.reg.update(job_id, state="CANCELLED", finished=_now())
        return rc == 0, (err or out).strip()

    def partitions(self):
        if self.fake:
            return [{"name": "cpu_short", "avail": "up", "time": "12:00:00"},
                    {"name": "cpu_medium", "avail": "up", "time": "5-00:00:00"},
                    {"name": "cpu_long", "avail": "up", "time": "28-00:00:00"}]
        rc, out, _ = self.run(["sinfo", "-h", "-o", "%P|%a|%l"])
        parts, seen = [], set()
        for line in out.splitlines():
            f = line.split("|")
            if len(f) >= 3:
                name = f[0].rstrip("*")
                if name not in seen:
                    seen.add(name)
                    parts.append({"name": name, "avail": f[1], "time": f[2], "default": f[0].endswith("*")})
        return parts

    def queue_summary(self):
        """User's whole queue (not only GUI jobs), plus background jobs started by the GUI."""
        local = [{"job_id": j["job_id"], "name": j["name"], "state": j["state"], "time": j.get("elapsed", ""),
                  "reason": f"background on {j.get('host')}", "partition": "(local)"}
                 for j in self.reg.all() if j.get("executor") == "local" and j.get("state") in ACTIVE_STATES]
        return local + self._queue_summary()

    def _queue_summary(self):
        if self.fake:
            return [{"job_id": j["job_id"], "name": j["name"], "state": j["state"], "time": "", "reason": ""}
                    for j in self.reg.all() if j["state"] in ACTIVE_STATES]
        user = os.environ.get("USER", "")
        rc, out, _ = self.run(["squeue", "-h", "-u", user, "-o", "%i|%j|%T|%M|%R|%P"])
        rows = []
        for line in out.splitlines():
            f = line.split("|")
            if len(f) >= 6:
                rows.append({"job_id": f[0], "name": f[1], "state": f[2], "time": f[3], "reason": f[4], "partition": f[5]})
        return rows

    # -- polling ---------------------------------------------------------------
    def refresh(self):
        """Update states of active registry jobs from squeue/sacct."""
        active = [j for j in self.reg.all() if j.get("state") in ACTIVE_STATES or j.get("state") == "UNKNOWN"]
        for j in [x for x in active if x.get("executor") == "local"]:
            self.reg.update(j["job_id"], **self._local_state(j))
        active = [j for j in active if j.get("executor") != "local"]
        if not active:
            return
        if self.fake:
            return  # fake threads update the registry themselves
        ids = ",".join(j["job_id"] for j in active)
        states = {}
        rc, out, _ = self.run(["squeue", "-h", "-j", ids, "-o", "%i|%T|%M|%R"])
        if rc == 0:
            for line in out.splitlines():
                f = line.split("|")
                if len(f) >= 4:
                    states[f[0]] = {"state": f[1], "elapsed": f[2], "reason": f[3]}
        missing = [j["job_id"] for j in active if j["job_id"] not in states]
        if missing:
            rc, out, _ = self.run(["sacct", "-n", "-P", "-X", "-j", ",".join(missing),
                                   "-o", "JobID,State,Elapsed,ExitCode,End"])
            if rc == 0:
                for line in out.splitlines():
                    f = line.split("|")
                    if len(f) >= 4 and f[0] in missing:
                        states[f[0]] = {"state": f[1].split()[0], "elapsed": f[2], "exit": f[3],
                                        "finished": f[4] if len(f) > 4 else ""}
        for j in active:
            s = states.get(j["job_id"])
            if s:
                self.reg.update(j["job_id"], **s)
            elif j.get("state") in ACTIVE_STATES:
                # not in squeue and not (yet) in sacct: keep, but flag
                age = time.time() - j.get("_submitted_ts", time.time())
                if age > 600:
                    self.reg.update(j["job_id"], state="UNKNOWN")

    # -- fake mode ---------------------------------------------------------------
    def start_fake(self, job):
        t = threading.Thread(target=self._fake_run, args=(job,), daemon=True)
        self._fake_threads[job["job_id"]] = t
        t.start()

    def _fake_run(self, job):
        jid = job["job_id"]
        time.sleep(3)
        if jid not in self._fake_threads:
            return
        self.reg.update(jid, state="RUNNING", elapsed="00:00:03")
        sdir = job.get("subject_dir")
        steps = job.get("steps") or []
        if sdir and os.path.isdir(sdir) and steps:
            logs = os.path.join(sdir, "Logs")
            os.makedirs(logs, exist_ok=True)
            stamp = _dt.datetime.now().strftime("%a_%b_%d_%I:%M:%S_%p_EDT_%Y")
            summ = os.path.join(logs, f"Processing_Summary_{stamp}.txt")
            open(os.path.join(sdir, ".inprocess"), "w").close()
            fail = random.random() < 0.15
            with open(summ, "a") as fh:
                for i, s in enumerate(steps):
                    now = _dt.datetime.now().strftime("%a_%b_%d_%I:%M:%S_%p_EDT_%Y")
                    fh.write(f"{now}: \tRunning Module {s} (/fake/{s}.csh)\n"); fh.flush()
                    time.sleep(4)
                    if jid not in self._fake_threads:
                        return
                    now = _dt.datetime.now().strftime("%a_%b_%d_%I:%M:%S_%p_EDT_%Y")
                    if fail and i == len(steps) - 1:
                        fh.write(f"{now}: \t-=ERROR: Module {s} failed! (log: {logs}/fake.execution)\n")
                        break
                    fh.write(f"{now}: \tModule {s} completed!\n"); fh.flush()
                else:
                    now = _dt.datetime.now().strftime("%a_%b_%d_%I:%M:%S_%p_EDT_%Y")
                    fh.write(f"{now}: {job['sid']} completed requested operations successfully.\n")
            try:
                os.remove(os.path.join(sdir, ".inprocess"))
            except OSError:
                pass
            self.reg.update(jid, state="FAILED" if fail else "COMPLETED", finished=_now(), exit="2:0" if fail else "0:0")
        else:
            time.sleep(6)
            self.reg.update(jid, state="COMPLETED", finished=_now(), exit="0:0")
        self._fake_threads.pop(jid, None)


# ---------------------------------------------------------------------------
# High-level submit
# ---------------------------------------------------------------------------
def submit_batch(cfg, slurm, reg, project, pairs, steps, overrides, do_propagate, prop_opts, slurm_opts,
                 clear_locks=True, dry_run=False, day1_map=None, executor="slurm", local_serial=True):
    """Create scripts and submit.  Returns a report dict."""
    proj_dir = os.path.join(cfg.projects_root, project)
    out_dir = os.path.join(proj_dir, "logs", "UNP_GUI")
    if not dry_run:
        _cfg.ensure_dir(out_dir, cfg.get("study_group"))
    jobs_dir = _cfg.ensure_dir(os.path.join(_cfg.STATE_DIR, "jobs"), cfg.get("study_group"))
    stamp = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    report = {"submitted": [], "errors": [], "scripts": [], "dry_run": dry_run}

    def write_script(fname, text):
        p = os.path.join(jobs_dir, fname)
        with open(p, "w") as fh:
            fh.write(text)
        os.chmod(p, 0o770)
        _cfg.fix_group(p, cfg.get("study_group"))
        return p

    import socket
    local = executor == "local" and not slurm.fake
    host = socket.gethostname()
    prev_local = None          # for one-at-a-time background runs

    def launch(path, out_tmpl, err_tmpl, need_ok=None):
        """-> (job_id, message, extra job fields)"""
        if not local:
            jid, msg = slurm.submit_script(path)
            return jid, msg, {}
        wait = [prev_local] if (local_serial and prev_local) else []
        res = slurm.submit_local(path, out_tmpl, err_tmpl, wait_for=wait, require_ok=[need_ok] if need_ok else [])
        if not res[0]:
            return None, res[1], {}
        return res[0], res[1], {"executor": "local", "host": host, "pid": res[2]}

    dep = None
    dep_local = None
    if do_propagate:
        text = build_propagate_script(cfg, project, pairs, prop_opts or {}, slurm_opts, out_dir)
        report["scripts"].append({"name": "propagate", "text": text})
        if not dry_run:
            p = write_script(f"{stamp}_{_safe(project)}_propagate.sbatch", text)
            jid, msg, extra = launch(p, os.path.join(out_dir, "propagate_%j.out"), os.path.join(out_dir, "propagate_%j.err"))
            if jid:
                job = {"job_id": jid, "name": f"UNP_prop_{project}", "project": project, "sid": "",
                       "kind": "propagate", "steps": [], "script": p, "submitted": _now(),
                       "_submitted_ts": time.time(), "state": "PENDING", "out_dir": out_dir,
                       "pairs": [list(x) for x in pairs], "note": msg, **extra}
                reg.add(job)
                report["submitted"].append(job)
                if local:
                    dep_local = prev_local = jid
                else:
                    dep = f"afterok:{jid}"
                if slurm.fake:
                    slurm.start_fake(job)
            else:
                report["errors"].append(f"propagate: {msg}")
                return report
    if steps:
        for sub, ses in pairs:
            sid = f"{sub}_{ses}" if ses else sub
            d1 = (day1_map or {}).get(sid)
            text = build_p2_script(cfg, project, sid, steps, overrides, slurm_opts, out_dir,
                                   clear_lock=clear_locks, dependency=dep,
                                   day1_path=d1 if d1 else None)
            report["scripts"].append({"name": sid, "text": text})
            if dry_run:
                continue
            p = write_script(f"{stamp}_{_safe(project)}_{_safe(sid)}.sbatch", text)
            jid, msg, extra = launch(p, os.path.join(out_dir, f"{_safe(sid)}_P2_%j.out"),
                                     os.path.join(out_dir, f"{_safe(sid)}_P2_%j.err"), need_ok=dep_local)
            if jid:
                job = {"job_id": jid, "name": f"UNP_{project}_{sid}", "project": project, "sid": sid,
                       "kind": "P2", "steps": steps, "overrides": overrides, "script": p,
                       "submitted": _now(), "_submitted_ts": time.time(), "state": "PENDING",
                       "out_dir": out_dir, "dependency": dep or "", "note": msg,
                       "day1": os.path.basename((day1_map or {}).get(sid, "")),
                       "subject_dir": os.path.join(cfg.projects_root, project, "InProcess", sid), **extra}
                if local:
                    job["dependency"] = (f"after {dep_local} succeeds" if dep_local else "") + \
                        ((" / " if dep_local else "") + f"after {prev_local}" if (local_serial and prev_local and prev_local != dep_local) else "")
                    prev_local = jid
                reg.add(job)
                report["submitted"].append(job)
                if slurm.fake:
                    slurm.start_fake(job)
            else:
                report["errors"].append(f"{sid}: {msg}")
    return report


# ---------------------------------------------------------------------------
# PFM template matching
# ---------------------------------------------------------------------------
def submit_tm(cfg, slurm, reg, project, groups, opts, slurm_opts, dry_run=False):
    """groups: list of lists of sids (one per job: a single session, or several sessions of one
    participant to concatenate).  opts: see tm.build_job."""
    from . import tm as _tm
    out_dir = os.path.join(cfg.projects_root, project, "logs", "UNP_GUI")
    if not dry_run:
        _cfg.ensure_dir(out_dir, cfg.get("study_group"))
    jobs_dir = _cfg.ensure_dir(os.path.join(_cfg.STATE_DIR, "jobs"), cfg.get("study_group"))
    stamp = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    report = {"submitted": [], "errors": [], "scripts": [], "dry_run": dry_run}
    s = slurm_opts

    def header(name, out, err, part, cpus, mem, tlimit):
        return _sbatch_header(name, out, err, part, cpus, mem, tlimit, s.get("account"), s.get("extra_sbatch"),
                              s.get("mail_user"), s.get("mail_type"), None)

    for grp in groups:
        o = dict(opts)
        if len(groups) > 1:
            o.pop("name", None)          # an explicit name only makes sense for a single job
        if (opts.get("names") or {}).get(",".join(grp)):
            o["name"] = opts["names"][",".join(grp)]      # existing concatenated analysis: keep its name
        job_name, name, lines, info = _tm.build_job(cfg, project, grp, o, s, out_dir, header)
        lines += _notify_block(cfg, s, f"PFM {project}/{name} ({info['atlas']}, {'+'.join(info['steps'])})",
                               ['echo; echo "Steps:"; cat ' + shlex.quote(os.path.join(info["out_dir"], "pfm_status.txt")) + ' 2>/dev/null | tail -6',
                                'echo; echo "Outputs:"; ls -la ' + shlex.quote(info["out_dir"]) + ' 2>/dev/null | tail -12',
                                'echo; echo "Last 30 lines of job output:"; [ -n "$SLURM_LOG" ] && tail -30 "$SLURM_LOG"'])
        lines += ["exit $status"]
        text = "\n".join(lines) + "\n"
        report["scripts"].append({"name": name, "text": text})
        if dry_run:
            continue
        pth = os.path.join(jobs_dir, f"{stamp}_{_safe(project)}_{_safe(name)}_PFM_{_safe(info['atlas'])}.sbatch")
        with open(pth, "w") as fh:
            fh.write(text)
        os.chmod(pth, 0o770)
        _cfg.fix_group(pth, cfg.get("study_group"))
        jid, msg = slurm.submit_script(pth)
        if jid:
            job = {"job_id": jid, "name": job_name, "project": project, "sid": name,
                   "kind": "PFM", "steps": [f"PFM:{x}" for x in info["steps"]],
                   "overrides": [info["atlas"], info["variant"]] + ([info["wta_method"]] if info["wta_method"] else []),
                   "script": pth, "submitted": _now(), "_submitted_ts": time.time(), "state": "PENDING",
                   "out_dir": out_dir, "note": msg, "tm": info,
                   "log_base": f"{_safe(name + '_' + info['atlas'])}_PFM_"}
            reg.add(job)
            report["submitted"].append(job)
            if slurm.fake:
                slurm.start_fake(job)
        else:
            report["errors"].append(f"{name}: {msg}")
    return report
