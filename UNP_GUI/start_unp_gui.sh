#!/bin/bash
#
# start_unp_gui.sh - launch the UNP GUI on BigPurple.
#
#   ./start_unp_gui.sh                 # start and open a NEW Firefox window (MATE desktop); says why if it can't
#   ./start_unp_gui.sh --no-browser    # just print the URL
#   ./start_unp_gui.sh --port 9000
#   ./start_unp_gui.sh --fake          # simulate Slurm (no real submissions)
#
# What it does:
#   * runs everything with umask 002 and, if possible, under the lab group
#     (sg siegellab) so every file the GUI creates belongs to the lab group
#   * picks a Python >= 3.8 (module python -> FSL's python -> system python3)
#   * starts the local web server (127.0.0.1 only) and opens a browser
#
# Run it from a compute/desktop node (e.g. an Open OnDemand MATE desktop or
# an `srun --pty bash` shell), not from a login node: the pipeline
# environment breaks the login-node environment (see SCRIPTS/.bashrc).
#
GUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUP="${UNP_GUI_GROUP:-siegellab}"
umask 002
# no __pycache__ in the shared folder (it would belong to whoever ran first)
export PYTHONDONTWRITEBYTECODE=1

# --- re-exec under the lab group so new files get group=$GROUP -------------
# (skipped when sg is not permitted on this system, e.g. "setgid: Operation not
#  permitted" on BigPurple; the setgid bit on the UNP_GUI/Projects folders set by
#  fix_perms.sh makes new files inherit the group anyway)
if [ -z "$UNP_GUI_IN_SG" ] && [ "$(id -gn)" != "$GROUP" ] && id -Gn | tr ' ' '\n' | grep -qx "$GROUP" \
   && sg "$GROUP" -c true >/dev/null 2>&1; then
    export UNP_GUI_IN_SG=1
    q=""; for a in "$@"; do q="$q $(printf '%q' "$a")"; done
    exec sg "$GROUP" -c "umask 002; exec bash '$GUI_DIR/start_unp_gui.sh' $q"
fi
[ "$(id -gn)" = "$GROUP" ] || echo "note: running with primary group $(id -gn); relying on setgid folders for group $GROUP"

# --- keep the lab's access to the files you own here and in PFM_tools (files copied in from elsewhere, e.g. over
#     an sshfs mount, can arrive owner-only), then check that you can use the parts other people own
PFM_DIR="$(dirname "$(dirname "$GUI_DIR")")/PFM_tools"
[ -f "$GUI_DIR/fix_perms.sh" ] && bash "$GUI_DIR/fix_perms.sh" -q "$GUI_DIR" "$PFM_DIR" >/dev/null 2>&1
noaccess=""
for p in "$GUI_DIR/unp_gui.py" "$GUI_DIR/unp_gui" "$GUI_DIR/unp_gui/static" "$GUI_DIR/templates"; do
    [ -r "$p" ] || noaccess="$noaccess\n  cannot read $p"
done
f=$(find "$GUI_DIR/unp_gui" "$GUI_DIR/templates" \( -name __pycache__ -o -name '.nfs*' -o -name '._*' \) -prune -o \
        ! -type l \( -type d ! -executable -o ! -readable \) -print -quit 2>/dev/null)
[ -n "$f" ] && noaccess="$noaccess\n  cannot read $f (and maybe more)"
[ -e "$GUI_DIR/config.json" ] && [ ! -r "$GUI_DIR/config.json" ] && noaccess="$noaccess\n  cannot read $GUI_DIR/config.json (shared settings)"
[ -w "$GUI_DIR/state" ] || noaccess="$noaccess\n  cannot write $GUI_DIR/state (job lists and job scripts)"
if [ -n "$noaccess" ]; then
    echo -e "ERROR: $(id -un) cannot use parts of UNP_GUI:$noaccess" >&2
    echo "  Full list:  bash $GUI_DIR/check_access.sh" >&2
    echo "  The owner of those files fixes them by running  bash $GUI_DIR/fix_perms.sh" >&2
    exit 1
fi

# --- find a suitable python ---------------------------------------------------
py_ok() { "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; }
PY=""
# 1) explicit
[ -n "$UNP_GUI_PYTHON" ] && py_ok "$UNP_GUI_PYTHON" && PY="$UNP_GUI_PYTHON"
# 2) whatever python3 is already on PATH (e.g. after `module load python/...`)
[ -z "$PY" ] && command -v python3 >/dev/null && py_ok python3 && PY="$(command -v python3)"
# 3) a python module
if [ -z "$PY" ] && type module >/dev/null 2>&1; then
    for m in $(module -t avail python/cpu 2>&1 | grep -i '^python/cpu' | sort -V | tail -3 | tac); do
        module load "$m" >/dev/null 2>&1 && command -v python3 >/dev/null && py_ok python3 && PY="$(command -v python3)" && break
    done
fi
# 4) FSL's python shipped with the pipeline (has numpy)
if [ -z "$PY" ]; then
    PH="$(sed -n 's/^export PROJECTS_HOME=//p' "$GUI_DIR/../PipelineEnvironment.sh" 2>/dev/null | head -1)"
    for c in "$FSLDIR"/bin/python3* "$PH"/SCRIPTS/fsl/bin/python3* "$GUI_DIR"/../SCRIPTS/fsl/bin/python3*; do
        [ -x "$c" ] && py_ok "$c" && PY="$c" && break
    done
fi
if [ -z "$PY" ]; then
    echo "ERROR: no python >= 3.8 found. Try: module load python/cpu/3.10  (or set UNP_GUI_PYTHON=/path/to/python3)" >&2
    exit 1
fi
echo "Using python: $PY ($("$PY" -c 'import sys; print(sys.version.split()[0])'))"
echo "Group: $(id -gn)   umask: $(umask)"

# --- ssh connection to a login node for Slurm commands ------------------------
# BigPurple desktop/compute nodes cannot run the Slurm client (GLIBC mismatch); IT's
# guidance is to submit from a login node.  Open ONE multiplexed ssh session now
# (password once); the GUI reuses it for every sbatch/squeue/sacct/scancel/sinfo.
#   host:  config.json "slurm_ssh_host"  >  $UNP_GUI_LOGIN_HOST  >  bigpurple.nyumc.org
#          (auto-enabled when the local sbatch is broken; set to "" in Settings to disable)
LOGIN_HOST="$(sed -n 's/^ *"slurm_ssh_host": *"\(.*\)",*$/\1/p' "$GUI_DIR/config.json" 2>/dev/null | head -1)"
if [ -z "$LOGIN_HOST" ] && ! grep -q '"slurm_ssh_host"' "$GUI_DIR/config.json" 2>/dev/null; then
    if ! sbatch --version >/dev/null 2>&1; then
        LOGIN_HOST="${UNP_GUI_LOGIN_HOST:-bigpurple.nyumc.org}"
        # persist so the GUI's Slurm layer uses it too
        if [ -f "$GUI_DIR/config.json" ] && ! { [ -w "$GUI_DIR/config.json" ] && [ -w "$GUI_DIR" ]; }; then
            echo "note: cannot write config.json; set the login node in Settings (or ask its owner)"
        elif [ -f "$GUI_DIR/config.json" ]; then
            sed -i "s|^{|{\n  \"slurm_ssh_host\": \"$LOGIN_HOST\",|" "$GUI_DIR/config.json"
        else
            printf '{\n  "slurm_ssh_host": "%s"\n}\n' "$LOGIN_HOST" > "$GUI_DIR/config.json"
        fi
    fi
fi
# If the Slurm client works on this node (e.g. a cn-XXXX compute node), use it directly.
if [ -n "$LOGIN_HOST" ] && sbatch --version >/dev/null 2>&1; then
    echo "Local sbatch works on $(hostname) ($(sbatch --version)); not using the login-node ssh hop."
    export UNP_GUI_LOCAL_SLURM=1
    LOGIN_HOST=""
fi
if [ -n "$LOGIN_HOST" ] && [[ " $* " != *" --fake "* ]] && [[ " $* " != *" --selftest "* ]]; then
    CP="$HOME/.ssh/unp_gui_%r@%h:%p"
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    SSH_OPTS=(-F /dev/null -o "ControlPath=$CP" -o StrictHostKeyChecking=no -o LogLevel=ERROR)
    if ssh "${SSH_OPTS[@]}" -O check "$LOGIN_HOST" >/dev/null 2>&1; then
        echo "Login-node ssh connection to $LOGIN_HOST already open."
    else
        # a socket left behind by a previous session (other node / dead master) blocks multiplexing
        SOCK="$HOME/.ssh/unp_gui_$(id -un)@${LOGIN_HOST}:22"
        [ -S "$SOCK" ] && { echo "Removing stale ssh control socket $SOCK"; rm -f "$SOCK"; }
        echo "Opening ssh connection to $LOGIN_HOST for Slurm commands (enter your password once)..."
        ssh "${SSH_OPTS[@]}" -o ControlMaster=yes -o ControlPersist=yes -fN "$LOGIN_HOST" \
            || { echo "ERROR: could not connect to $LOGIN_HOST. Slurm submissions will fail." >&2; }
    fi
    if ssh "${SSH_OPTS[@]}" -O check "$LOGIN_HOST" >/dev/null 2>&1; then
        echo "  ok: $(ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$LOGIN_HOST" 'bash -l -c "hostname; /cm/shared/apps/slurm/current/bin/sbatch --version || sbatch --version"' 2>/dev/null 2>&1 | tr '\n' ' ')"
    fi
fi

# make sure a browser exists for --open-browser; fall back to printing the URL
if ! command -v firefox >/dev/null; then
    echo "note: no firefox on $(hostname -s) - not opening a browser window; open the link printed below yourself"
    set -- "$@" --no-browser
fi
[ -n "$BROWSER" ] || { command -v firefox >/dev/null && export BROWSER=firefox; }

# --- run the GUI; close the login-node ssh connection when it stops ----------
cleanup() {
    if [ -n "$LOGIN_HOST" ]; then
        ssh "${SSH_OPTS[@]}" -O exit "$LOGIN_HOST" >/dev/null 2>&1 && echo "Closed ssh connection to $LOGIN_HOST."
        rm -f "$HOME/.ssh/unp_gui_$(id -un)@${LOGIN_HOST}:22"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
cd "$GUI_DIR"
"$PY" "$GUI_DIR/unp_gui.py" "$@"
