#!/bin/bash
#
# start_unp_gui.sh - launch the UNP GUI on BigPurple.
#
#   ./start_unp_gui.sh                 # start and open Firefox (MATE desktop)
#   ./start_unp_gui.sh --no-browser    # just print the URL
#   ./start_unp_gui.sh --port 9000
#   ./start_unp_gui.sh --ssh          # SSH-friendly mode, print a Mac tunnel command
#   ./start_unp_gui.sh --ssh --port 9000 --fake
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
SELF_SCRIPT="$GUI_DIR/$(basename "${BASH_SOURCE[0]}")"
GROUP="${UNP_GUI_GROUP:-siegellab}"
umask 002

# --- re-exec under the lab group so new files get group=$GROUP -------------
# (skipped when sg is not permitted on this system, e.g. "setgid: Operation not
#  permitted" on BigPurple; the setgid bit on the UNP_GUI/Projects folders set by
#  fix_perms.sh makes new files inherit the group anyway)
if [ -z "$UNP_GUI_IN_SG" ] && [ "$(id -gn)" != "$GROUP" ] && id -Gn | tr ' ' '\n' | grep -qx "$GROUP" \
   && sg "$GROUP" -c true >/dev/null 2>&1; then
    export UNP_GUI_IN_SG=1
    q=""; for a in "$@"; do q="$q $(printf '%q' "$a")"; done
    exec sg "$GROUP" -c "umask 002; exec bash '$SELF_SCRIPT' $q"
fi
[ "$(id -gn)" = "$GROUP" ] || echo "note: running with primary group $(id -gn); relying on setgid folders for group $GROUP"


# --ssh is handled here, not passed into the Python application's argparse.
SSH_MODE=0
PORT=9000
PORT_GIVEN=0
HOST_GIVEN=0
HOST=""
NO_BROWSER=0
APP_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --ssh) SSH_MODE=1; shift ;;
        --port)
            [ "$#" -ge 2 ] || { echo "ERROR: --port needs a number" >&2; exit 2; }
            PORT="$2"; PORT_GIVEN=1
            APP_ARGS+=("$1" "$2"); shift 2 ;;
        --port=*)
            PORT="${1#--port=}"; PORT_GIVEN=1
            APP_ARGS+=("$1"); shift ;;
        --host)
            [ "$#" -ge 2 ] || { echo "ERROR: --host needs an address" >&2; exit 2; }
            HOST="$2"; HOST_GIVEN=1
            APP_ARGS+=("$1" "$2"); shift 2 ;;
        --host=*)
            HOST="${1#--host=}"; HOST_GIVEN=1
            APP_ARGS+=("$1"); shift ;;
        --no-browser)
            NO_BROWSER=1; APP_ARGS+=("$1"); shift ;;
        *) APP_ARGS+=("$1"); shift ;;
    esac
done

if [ "$SSH_MODE" -eq 1 ]; then
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo "ERROR: --ssh requires a port from 1 to 65535" >&2; exit 2
    fi
    if [ "$HOST_GIVEN" -eq 1 ] && [ "$HOST" != 127.0.0.1 ] && [ "$HOST" != localhost ]; then
        echo "ERROR: --ssh requires --host 127.0.0.1 (or localhost)" >&2; exit 2
    fi
    [ "$PORT_GIVEN" -eq 1 ] || APP_ARGS+=(--port "$PORT")
    [ "$HOST_GIVEN" -eq 1 ] || APP_ARGS+=(--host 127.0.0.1)
    [ "$NO_BROWSER" -eq 1 ] || APP_ARGS+=(--no-browser)
elif [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    # A headless SSH shell may have firefox installed but cannot show its window.
    [ "$NO_BROWSER" -eq 1 ] || APP_ARGS+=(--no-browser)
fi
set -- "${APP_ARGS[@]}"

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

# Fall back to URL-only mode if no browser is installed.
if ! command -v xdg-open >/dev/null && ! command -v firefox >/dev/null; then
    case " $* " in *" --no-browser "*) ;; *) set -- "$@" --no-browser ;; esac
fi
[ -n "$BROWSER" ] || { command -v firefox >/dev/null && export BROWSER=firefox; }


if [ "$SSH_MODE" -eq 1 ]; then
    COMPUTE_HOST="$(hostname -s)"
    REMOTE_USER="$(id -un)"
    JUMP_HOST="${UNP_GUI_JUMP_HOST:-bigpurple.nyumc.org}"
    printf '\nSSH mode: keep this terminal running on the compute node.\n'
    printf 'From a NEW terminal on your Mac, run:\n\n'
    printf '  ssh -N -J %s@%s -L %s:127.0.0.1:%s %s@%s\n\n' \
        "$REMOTE_USER" "$JUMP_HOST" "$PORT" "$PORT" "$REMOTE_USER" "$COMPUTE_HOST"
    printf 'Open http://127.0.0.1:%s in the browser on your Mac.\n' "$PORT"
    printf 'This requires SSH access from the login node to the compute node.\n\n'
fi

cd "$GUI_DIR"
exec "$PY" "$GUI_DIR/unp_gui.py" "$@"
