"""
Configuration for UNP_GUI.

Everything lives in <UNP_GUI>/config.json.  On first run the file is created
from DEFAULTS, and PROJECTS_HOME / SCRATCH / PP_SCRIPTS are filled in by
parsing the pipeline's PipelineEnvironment.sh (so the GUI follows whatever the
pipeline itself is configured to use).
"""
import json
import os
import re
import shlex
import shutil
import sys

GUI_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(GUI_ROOT, "config.json")
STATE_DIR = os.path.join(GUI_ROOT, "state")

DEFAULTS = {
    # ---- pipeline locations -------------------------------------------------
    # Root that contains SCRIPTS/, Scans/, Projects/, PipelineEnvironment.sh.
    # Empty -> derived from env_script (PROJECTS_HOME=...), else from $PROJECTS_HOME,
    # else the parent directory of UNP_GUI.
    "projects_home": "",
    # bash environment script sourced at the top of every job.
    "env_script": "",            # default: <projects_home>/PipelineEnvironment.sh
    "scratch": "",               # per user: SCRATCH from env_script (/gpfs/scratch/$USER); never stored in config.json
    # Extra shell lines run in every job after sourcing env_script
    # (e.g. "module load matlab/R2024a").
    "job_prologue": [],

    # Extra FD thresholds (mm) for which frames-kept counts are recomputed from the
    # per-frame FD traces (Functional/Movement/bold*_upck_faln_dbnd_xr3d.ddat.fd),
    # in addition to the study threshold used by P2.
    "qc_extra_fd_thresholds": [0.3],
    # ---- PFM template matching -------------------------------------------------
    "pfm_tools_dir": "/gpfs/data/siegellab/PFM_tools",
    "pfm_tm_script": "run_template_matching_v3",   # (informational; jobs call run_PFM.sh)
    "tm_prologue": ["module load matlab/R2024a"],
    # ---- notifications --------------------------------------------------------
    # Address that receives an e-mail when a job finishes (summary + tail of the
    # P2 summary log).  Also offered as the default for Slurm --mail-user and for
    # P2's own UserEmailAddress in Study.cfg.  Empty = no e-mail.
    "notify_email": "",          # per user: stored in notify_by_user[<username>]
    "notify_on": "always",       # "always" | "fail" | "never"
    # ---- group / permissions ------------------------------------------------
    "study_group": "siegellab",  # files created by jobs/GUI get this group
    "use_sg": True,              # submit with `sg <group> -c "sbatch ..."`
    "umask": "002",

    # Prefix for every Slurm client call (sbatch/squeue/sacct/scancel/sinfo), e.g.
    # ["ssh", "-o", "BatchMode=yes", "bigpurple-ln1"] when the node the GUI runs on
    # cannot run the Slurm client itself.  Empty = run locally.
    "slurm_cmd_prefix": [],
    # Login node to run Slurm client commands on, through a multiplexed ssh
    # connection that start_unp_gui.sh opens once (password typed once).
    # BigPurple: "bigpurple.nyumc.org".  Empty = run Slurm commands locally.
    "slurm_ssh_host": "",
    # Directory put in front of PATH for Slurm client calls, e.g. "/usr/local/bin"
    # when the default sbatch on PATH is built for another OS release.
    "slurm_bin_dir": "",
    # ---- Slurm defaults -----------------------------------------------------
    "slurm": {
        "partition": "cpu_medium",
        "cpus_per_task": 6,
        "mem": "64G",
        "time": "2-00:00:00",
        "account": "",           # optional #SBATCH -A
        "extra_sbatch": [],      # extra raw "#SBATCH ..." lines
        "propagate_partition": "cpu_short",
        "propagate_cpus": 2,
        "propagate_mem": "16G",
        "propagate_time": "12:00:00",
        "mail_user": "",         # optional --mail-user
        "mail_type": "",         # e.g. "END,FAIL"
        "tm_partition": "cpu_short",
        "tm_cpus": 4,
        "tm_mem": "150G",
        "tm_time": "12:00:00"
    },

    # ---- GUI behaviour ------------------------------------------------------
    "port": 8765,
    "host": "127.0.0.1",
    "open_browser": True,
    "refresh_seconds": 60,
    # Steps shown in the "Steps" panel, in order (must exist in P2.cfg).
    "default_steps": ["-reg", "-fMRI", "-surf", "-QC"],
    "step_order": ["-reg", "-T1", "-T2", "-FLAIR", "-fs", "-BOLD", "-ASL", "-ASE",
                   "-SWI", "-DTIp", "-PET", "-fMRI", "-OEF", "-CMRO2", "-CBF",
                   "-surf", "-QC", "-export_results_matlab", "-run_cleanup"],
    # fake mode: no sbatch, jobs are simulated (for testing away from the cluster)
    "fake_slurm": False,
}


def _deep_update(base, new):
    for k, v in new.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            _deep_update(base[k], v)
        else:
            base[k] = v
    return base


def parse_env_script(path):
    """Pull simple `export VAR=value` / `setenv VAR value` assignments out of a
    PipelineEnvironment.{sh,csh}.  Handles ${VAR} substitution for variables
    defined earlier in the same file."""
    env = {}
    if not path or not os.path.isfile(path):
        return env
    pat_sh = re.compile(r'^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
    pat_csh = re.compile(r'^\s*setenv\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.*)$')
    try:
        with open(path, errors="replace") as fh:
            for line in fh:
                line = line.split("#", 1)[0].rstrip()
                m = pat_sh.match(line) or pat_csh.match(line)
                if not m:
                    continue
                name, val = m.group(1), m.group(2).strip()
                try:
                    parts = shlex.split(val)
                    val = parts[0] if parts else ""
                except ValueError:
                    val = val.strip('"').strip("'")

                def sub(mm):
                    v = mm.group(1) or mm.group(2)
                    if v == "USER":
                        return env.get(v) or os.environ.get(v) or current_user()
                    return env.get(v, os.environ.get(v, ""))
                val = re.sub(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)', sub, val)
                env[name] = val
    except OSError:
        pass
    return env


def current_user():
    import getpass
    try:
        return getpass.getuser()
    except Exception:       # noqa: BLE001
        return os.environ.get("USER", "unknown")


def expand_user(path):
    """'/gpfs/scratch/$USER/x' -> '/gpfs/scratch/<you>/x' ($USER and ${USER} only; nothing else is evaluated)."""
    me = current_user()
    return (path or "").replace("${USER}", me).replace("$USER", me)


def per_user(path):
    """'/gpfs/scratch/<you>/x' -> '/gpfs/scratch/$USER/x': for paths written into files that other lab members'
    jobs also read (Study.cfg is sourced by csh, which expands $USER for whoever runs the job)."""
    me = current_user()
    parts = (path or "").split("/")
    return "/".join("$USER" if x == me else x for x in parts) if me and me in parts else (path or "")


# settings that belong to the person running the GUI, not to the lab
USER_KEYS = ("notify_email", "notify_on")


class Config:
    def __init__(self, path=CONFIG_PATH):
        self.path = path
        self.data = json.loads(json.dumps(DEFAULTS))
        if os.path.isfile(path):
            try:
                with open(path) as fh:
                    loaded = json.load(fh)
                if loaded.get("notify_email") and "notify_by_user" not in loaded:
                    self.data["_legacy_notify"] = (loaded["notify_email"], loaded.get("notify_on", "always"))
                loaded.pop("notify_email", None)
                loaded.pop("notify_on", None)
                # scratch is personal (/gpfs/scratch/<user>): always taken from the environment script, never
                # from the shared config.json (older versions stored the first user's scratch there)
                loaded.pop("scratch", None)
                _deep_update(self.data, loaded)
            except (OSError, ValueError) as e:
                print(f"WARNING: could not read {path}: {e}", file=sys.stderr)
        self.resolve()

    # -- resolution of derived paths -----------------------------------------
    def _user_prefs(self):
        """Map shared notify_by_user[<user>] onto notify_email / notify_on.  A legacy single
        notify_email in config.json is attributed to the owner of config.json."""
        d = self.data
        nbu = d.get("notify_by_user")
        if not isinstance(nbu, dict):
            nbu = d["notify_by_user"] = {}
        legacy = d.pop("_legacy_notify", None)
        if legacy and not nbu:
            try:
                import pwd
                owner = pwd.getpwuid(os.stat(self.path).st_uid).pw_name
            except (KeyError, OSError, ImportError):
                owner = current_user()
            nbu[owner] = {"email": legacy[0], "on": legacy[1]}
        me = nbu.get(current_user(), {})
        d["notify_email"] = me.get("email", "")
        d["notify_on"] = me.get("on", "always")

    def resolve(self):
        d = self.data
        self._user_prefs()
        # 1) projects_home
        ph = d.get("projects_home") or os.environ.get("PROJECTS_HOME", "")
        env_script = d.get("env_script")
        if not ph:
            # try env script next to UNP_GUI
            cand = os.path.join(os.path.dirname(GUI_ROOT), "PipelineEnvironment.sh")
            env = parse_env_script(env_script or cand)
            ph = env.get("PROJECTS_HOME", "")
        if not ph:
            ph = os.path.dirname(GUI_ROOT)
        d["projects_home"] = ph
        if not env_script:
            env_script = os.path.join(ph, "PipelineEnvironment.sh")
            d["env_script"] = env_script
        env = parse_env_script(env_script)
        d["_env"] = env
        if not d.get("scratch"):
            d["scratch"] = env.get("SCRATCH", os.environ.get("SCRATCH", ""))
        d["pp_scripts"] = env.get("PP_SCRIPTS") or os.path.join(ph, "SCRIPTS")
        d["projects_dir"] = env.get("PROJECTS_DIR") or "Projects"
        d["_sg_available"] = bool(shutil.which("sg"))
        bd = d.get("slurm_bin_dir") or ""
        d["_sbatch_available"] = bool(os.path.isfile(os.path.join(bd, "sbatch")) if bd else shutil.which("sbatch"))

    # -- accessors ------------------------------------------------------------
    def __getitem__(self, k):
        return self.data[k]

    def get(self, k, default=None):
        return self.data.get(k, default)

    @property
    def projects_home(self):
        return self.data["projects_home"]

    @property
    def scans_dir(self):
        return os.path.join(self.projects_home, "Scans")

    @property
    def projects_root(self):
        return os.path.join(self.projects_home, self.data["projects_dir"])

    @property
    def pp_scripts(self):
        return self.data["pp_scripts"]

    def public(self):
        """Config as sent to the browser (no private keys)."""
        out = {k: v for k, v in self.data.items() if not k.startswith("_")}
        out.update({
            "sg_available": self.data.get("_sg_available", False),
            "sbatch_available": self.data.get("_sbatch_available", False),
            "gui_root": GUI_ROOT,
            "user": current_user(),
            "scans_dir": self.scans_dir,
            "projects_root": self.projects_root,
            "env": self.data.get("_env", {}),
        })
        return out

    def update(self, new):
        allowed = set(DEFAULTS.keys())
        clean = {k: v for k, v in new.items() if k in allowed}
        _deep_update(self.data, clean)
        if "notify_email" in clean or "notify_on" in clean:
            self.data.setdefault("notify_by_user", {})[current_user()] = {
                "email": (self.data.get("notify_email") or "").strip(), "on": self.data.get("notify_on") or "always"}
        self.resolve()
        self.save()

    def save(self):
        # other people's notification settings may have changed since we loaded: merge them back in
        nbu = dict(self.data.get("notify_by_user") or {})
        try:
            with open(self.path) as fh:
                disk = json.load(fh).get("notify_by_user") or {}
            for u, v in disk.items():
                if u != current_user():
                    nbu[u] = v
        except (OSError, ValueError):
            pass
        self.data["notify_by_user"] = nbu
        out = {k: v for k, v in self.data.items()
               if not k.startswith("_") and k not in ("pp_scripts", "projects_dir", "scratch") + USER_KEYS}
        tmp = self.path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(out, fh, indent=2)
        os.replace(tmp, self.path)
        fix_group(self.path, self.data.get("study_group"))


def fix_group(path, group, mode=None):
    """Best-effort chgrp + group rw (and setgid on dirs)."""
    if not group:
        return
    try:
        import grp
        gid = grp.getgrnam(group).gr_gid
    except (KeyError, ImportError):
        return
    try:
        st = os.stat(path)
        if st.st_gid != gid:
            os.chown(path, -1, gid)
        if os.path.isdir(path):
            os.chmod(path, (st.st_mode & 0o7777) | 0o2770 if mode is None else mode)
        else:
            os.chmod(path, (st.st_mode & 0o7777) | 0o660 if mode is None else mode)
    except OSError:
        pass


def ensure_dir(path, group=None):
    os.makedirs(path, exist_ok=True)
    fix_group(path, group)
    return path
