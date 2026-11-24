#!/bin/bash
# fix_perms.sh - give the lab group access to UNP_GUI and the folders it works in.
#
#   ./fix_perms.sh                  # the defaults below (run it as the person who owns the files)
#   ./fix_perms.sh --all            # the defaults, plus every file under Projects/ and the pipeline SCRIPTS (slow)
#   ./fix_perms.sh PATH ...         # read/write for the group on these paths (whole tree) instead
#   ./fix_perms.sh --read PATH ...  # read-only for the group on these paths (whole tree)
#   ./fix_perms.sh -q ...           # quiet (start_unp_gui.sh runs  fix_perms.sh -q <UNP_GUI> <PFM_tools>  at every start)
#
# Defaults (PH = PROJECTS_HOME from PipelineEnvironment.sh, /gpfs/data/siegellab/UnifiedNeuroimagingPipeline)
#   read/write, whole tree : UNP_GUI, /gpfs/data/siegellab/PFM_tools
#   read/write, top levels : PH/Projects/<project>/... down to the session / participant folders
#                            (Study.cfg, InProcess/<id>, Participants/<id>, logs/UNP_GUI, Analysis),
#                            PH/Scans/<project>/<Subject>/<Session>
#   read only              : PH/PipelineEnvironment.sh, PH/SCRIPTS/{P1,P2,propagate_scans,config_study,Config,
#                            Parcellation,workbench}, PH/ATLAS
#   To open up everything inside one project or session:  ./fix_perms.sh PH/Projects/<project>[/InProcess/<id>]
#
# For every file and folder YOU own: group = siegellab, group read (+ write on read/write paths), group execute
# where the owner has it (folders, scripts, programs), setgid on folders so new files keep the group.  Files owned
# by someone else cannot be changed by you: those without group access are listed at the end (their owner runs this
# script).  Symbolic links are never followed.  Nothing is removed and no "other" permission is added.
GROUP="${UNP_GUI_GROUP:-siegellab}"
GUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUIET=0; ALL=0
[ "${1:-}" = "-q" ] && { QUIET=1; shift; }
[ "${1:-}" = "--all" ] && { ALL=1; shift; }
say() { [ "$QUIET" = 1 ] || echo "$@"; }
ME=$(id -un)
if ! id -Gn | tr ' ' '\n' | grep -qx "$GROUP"; then
    echo "fix_perms: you ($ME) are not in group $GROUP" >&2; exit 1
fi

PH="$(sed -n 's/^export PROJECTS_HOME=//p' "$GUI_DIR/../PipelineEnvironment.sh" 2>/dev/null | head -1)"
PH="${PH:-$(dirname "$GUI_DIR")}"
LAB="$(dirname "$PH")"                      # /gpfs/data/siegellab
RW=(); RO=(); SHALLOW=()                    # SHALLOW entries are "PATH:DEPTH", read/write
if [ "${1:-}" = "--read" ]; then
    shift; RO=("$@")
elif [ $# -gt 0 ]; then
    RW=("$@")
else
    RW=("$GUI_DIR" "$LAB/PFM_tools")
    SHALLOW=("$PH/Projects:3" "$PH/Scans:3")
    RO=("$PH/PipelineEnvironment.sh" "$PH/SCRIPTS/P1" "$PH/SCRIPTS/P2" "$PH/SCRIPTS/propagate_scans"
        "$PH/SCRIPTS/config_study" "$PH/SCRIPTS/Config" "$PH/SCRIPTS/Parcellation" "$PH/SCRIPTS/workbench" "$PH/ATLAS")
    if [ "$ALL" = 1 ]; then
        SHALLOW=("$PH/Scans:3"); RW+=("$PH/Projects"); RO+=("$PH/SCRIPTS")
    fi
fi

parents() {      # group needs x on every folder above a target (only the ones you own are changed)
    local d
    d=$(dirname "$1")
    while [ "$d" != "/" ] && [ "$d" != "/gpfs/data" ] && [ "$d" != "/gpfs" ]; do
        if [ -O "$d" ] && [ ! -L "$d" ]; then
            chgrp "$GROUP" "$d" 2>/dev/null
            chmod g+rx "$d" 2>/dev/null
        fi
        d=$(dirname "$d")
    done
}

fix() {          # fix PATH rw|ro [MAXDEPTH]
    local t=$1 m=$2 depth=() desc
    [ -n "${3:-}" ] && depth=(-maxdepth "$3")
    if [ ! -e "$t" ]; then say "  skip (not found): $t"; return; fi
    desc=$([ "$m" = rw ] && echo read/write || echo read-only)
    [ -n "${3:-}" ] && desc="$desc, $3 levels"
    say "== $t ($desc)"
    parents "$t"
    find -P "$t" "${depth[@]}" -user "$ME" ! -type l ! -group "$GROUP" -exec chgrp "$GROUP" {} + 2>/dev/null
    if [ "$m" = rw ]; then
        find -P "$t" "${depth[@]}" -user "$ME" -type d ! -perm -2070 -exec chmod g+rwxs {} + 2>/dev/null
        find -P "$t" "${depth[@]}" -user "$ME" -type f ! -perm -g+rw -exec chmod g+rw {} + 2>/dev/null
    else
        find -P "$t" "${depth[@]}" -user "$ME" -type d ! -perm -2050 -exec chmod g+rxs {} + 2>/dev/null
        find -P "$t" "${depth[@]}" -user "$ME" -type f ! -perm -g+r -exec chmod g+r {} + 2>/dev/null
    fi
    # programs: the group may run what the owner may run; scripts always executable
    find -P "$t" "${depth[@]}" -user "$ME" -type f -perm -u+x ! -perm -g+x -exec chmod g+x {} + 2>/dev/null
    find -P "$t" "${depth[@]}" -user "$ME" -type f \( -name "*.sh" -o -name "*.csh" -o -name "*.py" -o -name "*.sbatch" \) \
        ! -perm -ug+x -exec chmod ug+x {} + 2>/dev/null
    local o
    if [ "$m" = rw ]; then
        o=$(find -P "$t" "${depth[@]}" ! -user "$ME" ! -type l ! -name '.nfs*' \
                \( -type d ! -perm -g+rwx -o -type f ! -perm -g+r \) -printf '    %u:%g  %M  %p\n' 2>/dev/null | head -10)
    else
        o=$(find -P "$t" "${depth[@]}" ! -user "$ME" ! -type l ! -name '.nfs*' \
                \( -type d ! -perm -g+rx -o -type f ! -perm -g+r \) -printf '    %u:%g  %M  %p\n' 2>/dev/null | head -10)
    fi
    [ -n "$o" ] && { echo "  owned by someone else, no group access (their owner runs fix_perms.sh):"; echo "$o"; }
}

for t in "${RW[@]}"; do fix "$t" rw; done
for s in "${SHALLOW[@]}"; do fix "${s%:*}" rw "${s##*:}"; done
for t in "${RO[@]}"; do fix "$t" ro; done
say "done."
