# UNP_GUI — batch GUI for the UnifiedNeuroimagingPipeline on BigPurple

A self-contained, standard-library-only Python web GUI for running UNP
preprocessing (`propagate_scans` → `P2 -BOLD -fMRI -surf -QC …`) on
multi-subject datasets through Slurm, watching progress per subject and step,
finding failures, and looking at QC metrics / images.

```
UNP_GUI/
  start_unp_gui.sh      launcher (group + umask + python selection)   <- use this
  unp_gui.py            entry point (python3 unp_gui.py --help)
  fix_perms.sh          give siegellab access (run by the files' owner; see Multiple users)
  check_access.sh       what can I not use? (run by any lab member; changes nothing)
  config.json           created on first run; edit here or in the Settings tab
  unp_gui/
    config.py           config + PipelineEnvironment.sh parsing
    pipeline.py         Scans/Projects discovery, Processing_Summary parsing, Study.cfg
    slurm.py            sbatch script generation, sg submission, squeue/sacct, registry
    qc.py               QC metrics, NIfTI montage (numpy optional)
    server.py           HTTP/JSON API
    selftest.py         fake dataset generator (--selftest)
    static/             index.html, app.js, style.css
  state/
    jobs.json           registry of jobs submitted from the GUI
    jobs/*.sbatch       every generated job script (kept for provenance)
```

## Quick start (BigPurple)

1. Open a **MATE desktop** (Open OnDemand) or an interactive shell on a compute
   node (`srun -p cpu_short --pty --x11 bash` or your `$START_BASH`).
   Do not run it on a login node — the pipeline environment breaks the login
   node environment (see `SCRIPTS/.bashrc`).
2. First time only, fix ownership of the folder:
   ```
   cd /gpfs/data/siegellab/UnifiedNeuroimagingPipeline/UNP_GUI
   ./fix_perms.sh
   ```
3. Start it:
   ```
   ./start_unp_gui.sh
   ```
   Firefox opens `http://127.0.0.1:8765/`. Use `--no-browser` to just get the
   URL, `--port N` to change the port, `--fake` to try it without submitting
   anything.

   From your Mac instead of the MATE desktop:
   `ssh -L 8765:localhost:8765 <node>` and browse to `http://localhost:8765/`
   (the node must be the one running the GUI).

The launcher picks a Python ≥ 3.8 (a `python/cpu/*` module, then FSL's
python which has numpy, then system python3) and re-executes itself under
`sg siegellab` with `umask 002` so everything it writes belongs to the lab
group. `numpy` is only needed for the NIfTI montage viewer.

## What the GUI does

**Run tab**
- Subject list: paste (`SP01`, `SP01 Session01`, `SP01_Session01`, or InProcess
  paths), load a text file, or tick subjects/sessions from `Scans/<project>/`.
  Each entry is resolved to an InProcess id `<Subject>_<Session>` and checked
  against `Scans/` and `Projects/<project>/InProcess/`.
- Steps: optional `propagate_scans` (+ `-f`, `-n`), then any P2 modules read
  live from `SCRIPTS/Config/P2.cfg`, plus per-run overrides (`-FD 0.5`,
  `-no_recon`, …).
- Slurm: partition (from `sinfo`), CPUs, memory, time, account, mail.
  **One sbatch job per subject/session**. P2 itself runs the chosen modules in
  order and stops that subject at the first failing module (its normal
  behaviour). If propagate is ticked, one propagate job runs first and the P2
  jobs are submitted with `--dependency=afterok:<propagate job>`.
- "Preview scripts" shows exactly what will be submitted (dry run).
- **Run on: This node, in the background** instead of Slurm runs the same job scripts with
  `bash` on the node the GUI is running on, detached (keeps running if you close the GUI, but
  stops when the desktop/interactive session ends). Default: one session at a time; P2 waits
  for propagate and only runs if it succeeded. Job ids look like `L1790873205 01`; status,
  logs (`logs/UNP_GUI/<id>_P2_<jobid>.out`), cancel and e-mail behave as for Slurm jobs.
  Marker files live in `state/local/`.

**Status tab** — one row per subject/session (union of Scans and InProcess):
propagated?, params present?, one coloured cell per P2 module
(done / failed / running / interrupted / never), which output products exist,
last activity, GUI job state, result of the last P2 run. Click a row for the
detail drawer (module logs, Processing_Summary, sbatch out/err, params editor,
QC metrics, movement plot PDFs, NIfTI montages). Tick rows → "Send selected →
Run tab" to re-run a subset (e.g. all failed).

Module state comes from `InProcess/<id>/Logs/Processing_Summary_*.txt`
(`Running Module -X`, `Module -X completed!`, `-=ERROR: Module -X failed!`),
combined with the `.inprocess` lock and the GUI's own job registry.
A "Running" line with no completion is *running* if a GUI job is active or the
lock is present and the summary was touched in the last 12 h; otherwise it is
shown as *interrupted* (crashed / node failure). "remove lock" in the drawer
deletes a stale `.inprocess` (P2 refuses to process a locked subject).

**Multi-session subjects (day 1)** — for a later session of a subject, pick its
first session in the "Day 1" column of the Run tab (or "change" in the subject
drawer). The GUI writes `set day1_path = <InProcess>/<day1 id>` into the
session's params (inside the job, after propagation, before P2; backup
`.params.day1.bak`). `-reg` then skips anatomical registration/FreeSurfer and
runs `Prepare_Multisession.csh`, so later sessions need `-reg` once before
`-BOLD`. The earliest other session with a registered T1 is pre-selected as a
suggestion; check it.

**Notifications** — Settings → notification e-mail (default set at install;
change it there or per run on the Run tab). Each job e-mails a summary when it
finishes (result, job id, tail of the Processing_Summary and of the job log) via
`mail`/`sendmail` on the compute node; "failures only" and "never" are options.
Independently, Slurm's own `--mail-user/--mail-type` can be set, and P2 sends its
own per-subject report (with the failing log's tail) when `UserEmailAddress` is
set in Study.cfg (there is a field for it in the Study.cfg tab).

**Jobs tab** — jobs submitted from the GUI (state via `squeue`/`sacct`),
their scripts and outputs, cancel; plus your whole `squeue -u $USER`.

**QC tab** — per-subject table from `QC/`: runs, good/bad frames after FD
thresholding, % good, minutes of usable data, mean/max RMS movement,
pre/post-denoising SD. Sortable, CSV export.

**Extra FD thresholds** — besides the study threshold used by P2, the QC table,
CSV and report also show frames/%/minutes kept at the thresholds listed in
Settings → "Extra FD thresholds" (default 0.3 mm), recomputed from
`Functional/Movement/bold*_upck_faln_dbnd_xr3d.ddat.fd` with the pipeline's rule
(frame kept if FD < threshold; the first `skip` frames count as censored).

**Surface QC images & HTML report** (QC tab) — "Render surface images" projects
each session's `QC/*_SD`, `tSNR_fnirt` and `*_CoV` `.func.gii` onto its inflated
32k surfaces with `wb_command -show-scene`, using `templates/SurfaceSD_template.scene`
(the lab's SurfRegQC scene with subject/atlas/mesh/metric substituted, as in
`gen_SurfaceSD.sh`), writing `QC/<id>_<SD|tSNR|CoV>_surface.png`. "Build HTML
report" writes `Analysis/QC_report_<stamp>.html` (+ `QC_report_latest.html`): the
summary table, per-run motion tables and the surface images, self-contained.

**PFM tab (precision functional mapping)** — one Slurm job per map running
`/gpfs/data/siegellab/PFM_tools/run_PFM.sh` (default cpu_short, 4 CPUs, 150G, 12 h), which chains
three skippable steps: (1) `concat_sessions.sh` censors each session's
`<id>_rsfMRI_<variant>.dtseries.nii` with `Functional/TemporalMask/rsfMRI_tmask.txt` (optionally
AND `rest_frames.txt`, optionally AND FD < cutoff from `Functional/Movement/<id>_all_bold_runs.fd`),
concatenates the sessions and builds one weighted Fisher-z dconn; (2) `run_template_matching_v3.m`
(DCAN template matching) writes the cortical network assignments for the chosen atlas; (3) `run_subcort_WTA.sh` assigns subcortical voxels to networks with
`WTA_subcort_assignment_scoresmoothing_v3.m` (default) or `WTA_subcort_assignment_networkseed.m`.
Sessions are `InProcess/<id>`, or finished sessions in `Participants/<id>` (projects such as psilo_pfm keep them there; InProcess wins if both exist). Mode "one map per session" writes to `<session>/Functional/Surface/TemplateMatching/`
(`<id>.dconn.nii`, `<id>_TM_<atlas>_*`, `Subcort/`). The "Network atlas" list is every `*.dlabel.nii` found
in `SCRIPTS/Parcellation` (override with `"parcellation_dir"` in `config.json`; re-scanned every 30 s, files in
sub-folders are named `Sub__Name`) that has 91,282 grayordinates and network labels 1&ndash;18; other dlabels
are listed greyed out with the reason. The default is `HCP_networks_wSCAN_insulafix`. The chosen file is passed
to `run_PFM.sh --dlabel`; each atlas gets its own shared group seed matrix. Mode "concatenate" pools the ticked sessions of
each participant: the series, dconn, mask and `<name>_sessions.txt` (which sessions, in which
order, frames kept) go to `Projects/<project>/Participants/<Subject>/`, the maps to
`Participants/<Subject>/TemplateMatching/` (default name `<Subject>_concat<N>`). Each step writes
`pfm_status.txt`; the tab shows TM / WTA state per atlas, the by-structure table of a subcortical
result, and renders cortical maps on the inflated surfaces ("Render network maps"). Existing
results are reused by the scripts, so the GUI refuses to resubmit unless "rerun" is ticked. The
shared HCP group template (`seed_matrix_HCPnetworks_insulafix_groupavg.mat`) is built once by the
first job and never deleted. `run_PFM.sh --help` documents the command line for use without the GUI.

**Study.cfg tab** — view/edit `Projects/<project>/Study.cfg` (backup kept as
`Study.cfg.bak`). For a brand-new project ("+ new" button) it creates
`Projects/<project>/{InProcess,Participants,Analysis,Excluded,logs}`, the
scratch folder and a complete Study.cfg with the same defaults as
`config_study`. This matters because `propagate_scans` drops into the
interactive `config_study` menu when Study.cfg is missing, which would hang a
batch job — the GUI refuses to submit a propagate job without a Study.cfg.

**Settings tab** — paths (`PROJECTS_HOME`, environment script), extra module
lines for jobs, group, `sg` on/off, Slurm defaults.

## How jobs are built

```bash
#!/bin/bash
#SBATCH --job-name=UNP_<project>_<id>  --partition=… --cpus-per-task=… --mem=… --time=…
#SBATCH --output=Projects/<project>/logs/UNP_GUI/<id>_P2_%j.out   (and .err)
umask 002
source /gpfs/data/siegellab/UnifiedNeuroimagingPipeline/PipelineEnvironment.sh
<job_prologue lines from config, e.g. module load matlab/R2024a>
cd $PROJECTS_HOME/Projects/<project>/InProcess
rm -f <id>/.inprocess              # optional (default on)
P2 <id> -BOLD -fMRI -surf -QC [overrides]
# P2 exits 0 even when a module fails -> the script greps the newest
# Processing_Summary for ERROR and exits 2 so Slurm shows FAILED.
```
This is the same recipe as `Projects/psil_stutter/P2_proc.sbatch`.
Submission is `sg siegellab -c "sbatch --parsable <script>"` so the job's
files (and the sbatch logs) belong to the lab group; P2 additionally
`chgrp -R $StudyGroup`s each subject at the end.

## Multiple users (lab group)

Anyone in `siegellab` can use the GUI. Each person runs their own copy; jobs are submitted as that person,
through their own ssh connection to the login node.

**A new lab member, once:**
1. Be in the `siegellab` group (`id -Gn`; HPC adds people).
2. Run the access check, which changes nothing and never logs in anywhere:
   `bash /gpfs/data/siegellab/UnifiedNeuroimagingPipeline/UNP_GUI/check_access.sh` (optionally followed by
   project names). It lists every file or folder you cannot use, with its owner and mode.
3. Add the shortcut to `~/.bashrc`:
   `UNP_GUI() { /gpfs/data/siegellab/UnifiedNeuroimagingPipeline/UNP_GUI/start_unp_gui.sh "$@"; }`

**Whoever owns the files** (normally Josh) fixes what the check reports with
`bash /gpfs/data/siegellab/UnifiedNeuroimagingPipeline/UNP_GUI/fix_perms.sh`: group `siegellab`, group
read/write, setgid folders, for UNP_GUI, PFM_tools, the top levels of every project and Scans folder, and read
access to PipelineEnvironment.sh, the pipeline programs, workbench, Parcellation and ATLAS. It only changes files
you own and lists other people's files that lack group access. `fix_perms.sh --all` also covers every file under
Projects/ and SCRIPTS/ (slow); `fix_perms.sh <path>` opens one project or session completely.
Files copied in over the Mac's sshfs mount arrive owner-only, so `start_unp_gui.sh` re-runs
`fix_perms.sh -q` on UNP_GUI and PFM_tools at every start, and stops with a clear message (pointing to
`check_access.sh`) when the person starting it cannot read the code or write `state/`.

**Personal vs shared:**
- Scratch is personal: `PipelineEnvironment.sh` sets `SCRATCH=/gpfs/scratch/$USER`, and each project's Study.cfg
  uses `set ScratchFolder = /gpfs/scratch/$USER/<project>` (csh expands `$USER` for whoever runs the job). New
  projects made in the Study.cfg tab get this form; config.json never stores a scratch path.
- `StudyGroup` in Study.cfg should be `siegellab`: P2 ends with `chgrp -R $StudyGroup`, so another group takes
  finished sessions away from the lab. `check_access.sh` warns about it.
- Lab-wide settings (paths, Slurm defaults, FD thresholds) live in `config.json`; the notification e-mail is
  personal (`notify_by_user` in config.json, set in Settings).
- Each person has their own job list (`state/jobs_<user>.json`).
- Each launch prints a personal link with a one-time key (`http://127.0.0.1:<port>/?t=…`); without it the GUI
  refuses access, so other users on the same node can't use your GUI.
- Two people on the same node get different ports automatically (8765, 8766, …).
- Re-running P2 on a session someone else processed needs group write inside that session:
  its owner runs `fix_perms.sh Projects/<project>/InProcess/<id>`.

## Notes / limits

- Read-only with respect to the pipeline: the GUI never edits anything under
  `SCRIPTS/`. It writes only `Projects/<project>/logs/UNP_GUI/`,
  `Projects/<project>/Study.cfg` (on request), `<id>.params` (on request, with
  backup), `.inprocess` (remove, on request) and its own `state/`.
- Subjects run by other people directly with `P2` show up in Status (from the
  summary logs) but not in the Jobs tab.
- `sacct` must be enabled for finished-job states; if it is not, finished jobs
  are marked UNKNOWN after 10 min and the Status tab (from the logs) is the
  source of truth.
- The server binds to 127.0.0.1 only. Anyone with a shell on the same node as
  your user could reach it; it has no authentication, so keep it that way.
- Test off-cluster: `python3 unp_gui.py --selftest` builds a fake dataset in
  `/tmp/UNP_fake` and simulates Slurm.
