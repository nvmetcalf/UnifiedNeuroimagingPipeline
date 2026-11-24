#!/bin/bash
# check_access.sh - can I (the current user) use UNP_GUI?  Run it as the lab member who wants to use it:
#
#   bash /gpfs/data/siegellab/UnifiedNeuroimagingPipeline/UNP_GUI/check_access.sh            # every project
#   bash /gpfs/data/siegellab/UnifiedNeuroimagingPipeline/UNP_GUI/check_access.sh psil_stutter   # just these
#
# Checks the GUI code, its shared settings and job lists, the pipeline environment and your scratch folder,
# the programs the jobs run (P1/P2/propagate_scans, wb_command, PFM_tools, MATLAB templates) and each project's
# Study.cfg and folders.  Every problem is printed with the file's owner, group and mode.  Files owned by someone
# else are fixed by their owner with  UNP_GUI/fix_perms.sh .  Nothing is changed by this script, and it never
# logs in anywhere (no ssh).
GUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUP="${UNP_GUI_GROUP:-siegellab}"
ME=$(id -un)
NBAD=0; NWARN=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; NBAD=$((NBAD + 1)); }
warn() { echo "  warn  $*"; NWARN=$((NWARN + 1)); }
who()  { stat -c '%U:%G %A' "$1" 2>/dev/null || echo "?"; }
need() {        # need r|w|x PATH LABEL
    local m=$1 p=$2 l=${3:-$2} word
    if [ ! -e "$p" ]; then bad "$l: not found ($p)"; return 1; fi
    case $m in r) word=read ;; w) word=write ;; *) word=execute ;; esac
    if test "-$m" "$p"; then ok "$l"; return 0; fi
    bad "$l: no $word permission ($p; $(who "$p"))"
    return 1
}
userpath() {    # expand $USER / ${USER} in a path from a config file (nothing else is evaluated)
    local v=$1
    v=${v//\$\{USER\}/$ME}; v=${v//\$USER/$ME}
    echo "$v"
}
firstexisting() { local d=$1; while [ ! -e "$d" ] && [ "$d" != "/" ]; do d=$(dirname "$d"); done; echo "$d"; }
creatable() {   # can mkdir -p make PATH?  (its first existing parent is writable)
    local d; d=$(firstexisting "$1"); [ -d "$d" ] && [ -w "$d" ]
}
listbad() {     # listbad LABEL find-args...   (first 8 offenders)
    local l=$1; shift
    local out
    out=$(find "$@" -printf '%u:%g %M %p\n' 2>/dev/null | head -8)
    if [ -n "$out" ]; then bad "$l:"; echo "$out" | sed 's/^/          /'; else ok "$l"; fi
}

echo "UNP_GUI access check for $ME on $(hostname) ($(date '+%F %T'))"
echo "== group"
if id -Gn | tr ' ' '\n' | grep -qx "$GROUP"; then ok "member of $GROUP"; else bad "$ME is not in group $GROUP (ask HPC to add you)"; fi
case "$(umask)" in 0002|002) ;; *) warn "umask $(umask): start_unp_gui.sh sets 002 itself; files you make elsewhere may not be group-writable" ;; esac

echo "== GUI code ($GUI_DIR)"
need x "$GUI_DIR" "UNP_GUI folder" || true
listbad "all code readable" "$GUI_DIR" \( -path "$GUI_DIR/state" -o -path "$GUI_DIR/_old" -o -name '_backup_*' -o -name '__pycache__' -o -name '.nfs*' -o -name '._*' \) -prune -o ! -type l \( -type d \( ! -readable -o ! -executable \) -o -type f ! -readable \) -print
if [ -x "$GUI_DIR/start_unp_gui.sh" ]; then ok "start_unp_gui.sh executable"
else warn "start_unp_gui.sh not executable for you ($(who "$GUI_DIR/start_unp_gui.sh")): run it as  bash $GUI_DIR/start_unp_gui.sh"; fi

echo "== shared settings and job lists"
need w "$GUI_DIR" "UNP_GUI folder writable (Settings are saved through a temporary file there)"
[ -e "$GUI_DIR/config.json" ] && { need r "$GUI_DIR/config.json" "config.json readable"; need w "$GUI_DIR/config.json" "config.json writable"; }
need w "$GUI_DIR/state" "state/ writable (your job list state/jobs_$ME.json)"
for d in jobs local; do [ -d "$GUI_DIR/state/$d" ] && need w "$GUI_DIR/state/$d" "state/$d/ writable"; done
[ -e "$GUI_DIR/state/jobs_$ME.json" ] && need w "$GUI_DIR/state/jobs_$ME.json" "your job list"

echo "== pipeline environment"
ENV="$GUI_DIR/../PipelineEnvironment.sh"
PH=""
if need r "$ENV" "PipelineEnvironment.sh readable"; then
    PH=$(sed -n 's/^export PROJECTS_HOME=//p' "$ENV" | head -1)
    SCR=$(userpath "$(sed -n 's/^export SCRATCH=//p' "$ENV" | head -1)")
    case "$SCR" in
        "") warn "SCRATCH not set in PipelineEnvironment.sh" ;;
        */$ME|*/$ME/*) if [ -d "$SCR" ]; then need w "$SCR" "your scratch ($SCR) writable"
                       else bad "your scratch folder $SCR does not exist (ask HPC; it is normally made for every account)"; fi ;;
        *) if [ -w "$SCR" ]; then warn "SCRATCH is someone else's folder ($SCR) but you can write to it"
           else bad "SCRATCH in PipelineEnvironment.sh is someone else's folder ($SCR; $(who "$SCR")): it must be /gpfs/scratch/\$USER"; fi ;;
    esac
fi
PH=${PH:-$(dirname "$GUI_DIR")}

echo "== programs the jobs run"
for p in P1 P2 propagate_scans config_study; do need x "$PH/SCRIPTS/$p" "SCRIPTS/$p" || true; done
need r "$PH/SCRIPTS/Config/P2.cfg" "SCRIPTS/Config/P2.cfg" || true
need x "$PH/SCRIPTS/workbench/rhel/bin_rh_linux64/wb_command" "wb_command" || true
need r "$PH/SCRIPTS/Parcellation" "SCRIPTS/Parcellation (network atlases)" || true
PT="$(dirname "$PH")/PFM_tools"
for p in run_PFM.sh concat_sessions.sh run_subcort_WTA.sh; do need x "$PT/$p" "PFM_tools/$p" || true; done
need r "$PT/run_template_matching_v3.m" "PFM_tools/run_template_matching_v3.m" || true
listbad "PFM_tools code readable" "$PT" \( -name PFM_deprecated -o -name logs -o -name '.nfs*' -o -name '._*' \) -prune -o ! -type l \( -type d \( ! -readable -o ! -executable \) -o -type f \( -name '*.m' -o -name '*.sh' -o -name '*.mat' -o -name '*.scene' \) ! -readable \) -print
if [ -w "$PT" ]; then ok "PFM_tools writable (a new network atlas builds its group template there)"
else warn "PFM_tools not writable ($(who "$PT")): template matching with an atlas that has no group template yet will fail"; fi
for f in "$PH"/ATLAS/HCP_S1200_812_rfMRI_MSMAll_groupPCA_d4500ROW_zcorr_recon2.dconn.nii; do
    [ -e "$f" ] && { need r "$f" "HCP group dconn (for new group templates)" || true; }
done
PY=""; for c in "${UNP_GUI_PYTHON:-}" python3; do [ -n "$c" ] && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null && { PY=$c; break; }; done
if [ -n "$PY" ]; then ok "python >= 3.8 for the GUI ($(command -v "$PY"))"; else echo "  info  no python >= 3.8 on PATH here: start_unp_gui.sh will try modules / FSL's python"; fi

echo "== projects"
if [ $# -gt 0 ]; then PROJS=("$@"); else PROJS=(); for d in "$PH"/Projects/*/; do [ -f "$d/Study.cfg" ] && PROJS+=("$(basename "$d")"); done; fi
for p in "${PROJS[@]}"; do
    P="$PH/Projects/$p"
    echo "-- $p"
    if [ ! -d "$P" ]; then bad "no such project: $P"; continue; fi
    need x "$P" "project folder" || continue
    if need r "$P/Study.cfg" "Study.cfg readable"; then
        [ -w "$P/Study.cfg" ] || warn "Study.cfg not writable for you ($(who "$P/Study.cfg")): you cannot change it in the Study.cfg tab"
        SFRAW=$(sed -n 's/^[[:space:]]*set[[:space:]]\+ScratchFolder[[:space:]]*=[[:space:]]*//p' "$P/Study.cfg" | head -1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//; s/^"//; s/"$//')
        SF=$(userpath "$SFRAW")
        if [ -z "$SF" ]; then warn "no ScratchFolder in Study.cfg"
        elif [ -d "$SF" ] && [ -w "$SF" ]; then ok "ScratchFolder $SF writable"
        elif [ ! -e "$SF" ] && creatable "$SF"; then ok "ScratchFolder $SF will be created by the jobs"
        else
            case "$SFRAW" in
                *'$USER'*|*'${USER}'*) bad "ScratchFolder $SF cannot be created or written ($(who "$(firstexisting "$SF")"))" ;;
                *) bad "ScratchFolder $SFRAW is someone else's ($(who "$(firstexisting "$SF")")): use /gpfs/scratch/\$USER/... in Study.cfg" ;;
            esac
        fi
        SG=$(sed -n 's/^[[:space:]]*set[[:space:]]\+StudyGroup[[:space:]]*=[[:space:]]*//p' "$P/Study.cfg" | head -1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//; s/"//g')
        if [ "$SG" = "$GROUP" ]; then ok "StudyGroup $SG"
        elif [ -n "$SG" ]; then warn "StudyGroup is '$SG', not $GROUP: P2 gives finished sessions that group, so others in $GROUP may lose access"; fi
    fi
    for d in InProcess Participants logs Analysis; do [ -d "$P/$d" ] && { need w "$P/$d" "$d/ writable" || true; }; done
    [ -d "$P/logs/UNP_GUI" ] && { need w "$P/logs/UNP_GUI" "logs/UNP_GUI/ writable (job logs)" || true; }
    [ -d "$PH/Scans/$p" ] && { need w "$PH/Scans/$p" "Scans/$p writable (propagate_scans)" || true; }
    listbad "session folders writable (needed to run P2 or PFM on them)" "$P/InProcess" "$P/Participants" -mindepth 1 -maxdepth 1 -type d ! -name '.*' ! -writable -print
    listbad "session logs and QC readable" "$P/InProcess" "$P/Participants" -mindepth 2 -maxdepth 3 \( -name Logs -o -name QC -o -name TemplateMatching \) \( ! -readable -o ! -executable \) -print
done

echo "== Slurm"
if command -v sbatch >/dev/null 2>&1 && sbatch --version >/dev/null 2>&1; then ok "sbatch works on this node"
else echo "  info  no working sbatch here: the GUI submits through one ssh connection to bigpurple.nyumc.org, opened when it starts"; fi
command -v firefox >/dev/null 2>&1 || echo "  info  no firefox on $(hostname -s): open the link the GUI prints in a browser on this desktop"

echo
if [ $NBAD = 0 ]; then echo "No problems found ($NWARN warning(s)).  Start the GUI with:  $GUI_DIR/start_unp_gui.sh"
else echo "$NBAD problem(s), $NWARN warning(s).  Files owned by someone else are fixed by their owner with:  bash $GUI_DIR/fix_perms.sh"; fi
exit $([ $NBAD = 0 ] && echo 0 || echo 1)
