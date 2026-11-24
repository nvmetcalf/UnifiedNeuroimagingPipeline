"""
Build a small fake PROJECTS_HOME that mimics the real layout (psil_stutter-like)
so the GUI can be exercised anywhere with --selftest / --fake.
"""
import gzip
import os
import struct
import tempfile

P2_CFG = r'''
set PipelineModules = (\
		"Registration Modules" " " " " \
		"-reg" "$PP_SCRIPTS/Registration/Run_Register_MRI.csh" "Perform volume registration of all MR modalities. Freesurfer will run if a successfull one is not detected." \
		"-surf" "$PP_SCRIPTS/Surface/surface_projection_pipeline_V3.csh" "Project Volume date to the surface. Requires -c and -f to be completed successfully." \
		"-DTIp" "$PP_SCRIPTS/DTI/Process_DTI_probabalistic.csh" "Register DTI and compute FA/MD." \
		"-PET" "$PP_SCRIPTS/PET/Process_PET_fsl" "Run PET Processing (FDG, H2O, CO, O2 and derivatives)." \
		"-T1" "$PP_SCRIPTS/Registration/Run_Register_T1.csh" "Register T1 to Target" \
		"-T2" "$PP_SCRIPTS/Registration/Run_Register_T2.csh" "Register T2 to Target." \
		"-FLAIR" "$PP_SCRIPTS/Registration/Run_Register_FLAIR.csh" "Register FLAIR to Target." \
		"-BOLD" "$PP_SCRIPTS/Registration/Run_Register_BOLD.csh" "Register, normalize, timing correct, NORDIC denoise, echo combine, and frame align BOLD timeseries." \
		"-ASL" "$PP_SCRIPTS/Registration/Run_Register_ASL.csh" "Register and frame align ASL timeseries." \
		"-ASE" "$PP_SCRIPTS/Registration/Run_Register_ASE.csh" "Register and motion correct ASE sequences." \
		"-SWI" "$PP_SCRIPTS/Registration/Run_Register_SWI.csh" "Register SWI to Anatomical and compute r2*." \
		" " " " " " \
		"Derivatives Modules" " " " " \
		"-fMRI" "$PP_SCRIPTS/fMRI/RunFCMRIBoldProcessing_Volume.csh" "Run the resting state fcMRI denoising. (required for surface projection and requires -reg or -BOLD and -T1 to be successful)" \
		"-OEF" "$PP_SCRIPTS/ASE/Compute_ASE.csh" "Compute OEF from ASE sequences." \
		"-CMRO2" "$PP_SCRIPTS/ASE/Compute_CMRO2.csh" "Compute CMRO2 from OEF and CBF." \
		"-CBF" "$PP_SCRIPTS/ASL/Compute_CBF_Tyler.csh" "Compute CBF. If Multidelay, ATT and ABV will be computed as well." \
		" " " " " " \
		"Utility Modules" " " " " \
		"-QC" "$PP_SCRIPTS/QC/RunQC.csh" "Export QC measures" \
		"-export_results_matlab" "$PP_SCRIPTS/Utilities/RunResults.csh" "Exports surfaces, correlations, FD, etc. in a matlab friendly format." \
		"-run_cleanup" "$PP_SCRIPTS/Utilities/RunCleanup.csh" "Clears out the temporary folder for the participant. This is usually permanent and if you want to regenerate results, you will need to rerun the pipeline." \
		"-fs" "$PP_SCRIPTS/RunFreesurfer.csh" "Run Freesurfer. Version is determined by Study.cfg or override." \
		)

set PipelineOverrides = (\
		"-dbg" "set echo" "0" "Enable verbose terminal output." \
		"-DVAR" "set DVAR_Threshold" "1" "Set the DVAR threshold to use." \
		"-FD" "set FD_Threshold" "1" "Set the Frame Displacement threshold to use." \
		"-wb" "set ComputeWBRegressor" "1" "Enable(1)/Disable(0) Wholebrain Regressor computation." \
		"-no_recon" "set skip_recon = 1" "0" "Do NOT run recon-all, even if it is necessary." \
		"-force_recon" "set ForceRecon = 1" "0" "Force recon-all to rerun. Removes Freesurfer folder in each Participant." \
		"-10k" "set LowResMesh = 10" "0" "Use the 10k vertex surfaces for surface projection." \
		"-32k" "set LowResMesh = 32" "0" "Use the 32k vertex surfaces for surface projection." \
		"-smooth" "SmoothingFWHM" "1" "Set the Full Width-Half Max smoothing to do in mm in volume and surface" \
		"-use_old_surf" "set UseCurrentSurfs = 1" "0" "Using currently existing surfaces for surface projection." \
		"-bold_target" "set BOLD_Reg_Target" "1" "Choose the anatomical target for the BOLD (T1/T2/FLAIR)" \
		"-reg_method" "set FieldMapping" "1" "Change the registration method for metric modalities such as BOLD and ASL (gre/appa/appa_6dof/synth/6dof)" \
		"-skip_inprocess_check" "set SkipInProcessCheck = 1" "0" "Skip the check to see if the participant is already being processed." \
		"-skip_syntax_check" "set SkipParamsCheck = 1" "0" "Skip the check to make sure params file is valid." \
		"-cont_on_reg_fail" "set ContinueRegFail = 1" "0" "Should a modality fail target registration, continue with the rest. Applies to -reg" \
		"-fs_version_to_use" "set FreesurferVersionToUse" "1" "use a particular version of freesurfer. Must be a folder in the SCRIPTS/FreesurferVersions folder." \
        )

set FreesurferCommands = (\
		"fs_7_4_1" "$PP_SCRIPTS/FreesurferVersions/Run_Freesurfer_7_4_1.csh" \
		"fs_7_3_2" "$PP_SCRIPTS/FreesurferVersions/Run_Freesurfer_7_3_2.csh" \
		)
'''

P1_CFG = r'''
set ATLAS = ${PROJECTS_HOME}/ATLAS
set AtlTargets = ( \
	${ATLAS}/MNI152/MNI152_T1_1mm \
	${ATLAS}/711-2B/711-2B_111 \
	)
'''

STUDY_CFG = """#######################
#
#	Study Configuration
#
#######################
set TargetAtlas = 1
set target = {root}/ATLAS/MNI152/MNI152_T1_1mm
set FD_Threshold = 0.8
set DVAR_Threshold = 0
set UseIterativeRegression = 0
set ScratchFolder = {root}/scratch/psil_stutter
set LowResMesh = 32
set ComputeWBRegressor = 1
set ComputeVENT = 1
set ComputeWM = 1
set ComputeMOVERegressor = 1
set ComputeEACSFRegressor = 1
set ApplyWBRegressor = 1
set ApplyVENT = 1
set ApplyWM = 1
set ApplyMOVERegressor = 1
set ApplyEACSFRegressor = 1
set DoVolumeRegression = 1
set NonLinear = 1
set DoVolumeBPSS = 0
set LowFrequency = 0.009
set HighFrequency = 0.08
set MaskTrailer =
set DoSurfaceRegression = 1
set ConvertDTItoDWI = 1
set DTIFramesToUse = ( 3 4 5 6 7 8 9 10 11 12 13 14 )
set IncludeSubCortical = 1
set VolSmoothingFWHM = 0
set SurfSmoothingFWHM = 2
set StudyGroup = siegellab
set ProcessUserScript =
set FinalResolution = 3
set RegisterEcho = 1
set MaximumRegDisplacement = 0
set MovementLowpass = 2
set MaxNumRegressors = 25
set RunNORDIC = 1
set FreesurferVersionToUse = fs_7_4_1
"""

SUMMARY_OK = """Fri_Sep__4_05:48:44_PM_EDT_2026: ===== DIRECTIVES =====
Fri_Sep__4_05:48:44_PM_EDT_2026: ==========================
Fri_Sep__4_05:48:52_PM_EDT_2026: Checking params for completeness...
Fri_Sep__4_05:48:52_PM_EDT_2026:  Running Module -BOLD ({s}/Registration/Run_Register_BOLD.csh)
Fri_Sep__4_08:11:04_PM_EDT_2026:  Module -BOLD completed!
Fri_Sep__4_08:11:04_PM_EDT_2026:  Running Module -fMRI ({s}/fMRI/RunFCMRIBoldProcessing_Volume.csh)
Fri_Sep__4_08:26:17_PM_EDT_2026:  Module -fMRI completed!
Fri_Sep__4_08:26:17_PM_EDT_2026:  Running Module -surf ({s}/Surface/surface_projection_pipeline_V3.csh)
Fri_Sep__4_08:47:16_PM_EDT_2026:  Module -surf completed!
Fri_Sep__4_08:47:16_PM_EDT_2026:  Running Module -QC ({s}/QC/RunQC.csh)
Fri_Sep__4_08:58:00_PM_EDT_2026:  Module -QC completed!
Fri_Sep__4_08:58:00_PM_EDT_2026: {sid} completed requested operations successfully.
"""
SUMMARY_REG = """Sat_Aug_22_02:55:27_AM_EDT_2026: ===== DIRECTIVES =====
Sat_Aug_22_02:55:30_AM_EDT_2026:  Running Module -reg ({s}/Registration/Run_Register_MRI.csh)
Sat_Aug_22_03:28:30_PM_EDT_2026:  Module -reg completed!
Sat_Aug_22_03:28:30_PM_EDT_2026: {sid} completed requested operations successfully.
"""
SUMMARY_FAIL = """Thu_Sep__3_09:18:14_PM_EDT_2026: ===== DIRECTIVES =====
Thu_Sep__3_09:18:20_PM_EDT_2026:  Running Module -fMRI ({s}/fMRI/RunFCMRIBoldProcessing_Volume.csh)
Thu_Sep__3_09:32:43_PM_EDT_2026:  -=ERROR: Module -fMRI failed! (log: {d}/Logs/RunFCMRIBoldProcessing_Volume.csh.execution)
"""
SUMMARY_STALE = """Wed_Aug_19_22:32:55_EDT_2026: ===== DIRECTIVES =====
Wed_Aug_19_22:33:00_EDT_2026:  Running Module -reg ({s}/Registration/Run_Register_MRI.csh)
"""


def _w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def _fake_nifti(path, shape=(48, 56, 40)):
    try:
        import numpy as np
    except Exception:
        return
    z, y, x = np.mgrid[0:shape[2], 0:shape[1], 0:shape[0]]
    cx, cy, cz = shape[0] / 2, shape[1] / 2, shape[2] / 2
    r = ((x - cx) / (0.42 * shape[0])) ** 2 + ((y - cy) / (0.45 * shape[1])) ** 2 + ((z - cz) / (0.45 * shape[2])) ** 2
    vol = (np.clip(1.2 - r, 0, None) * 900 + np.random.rand(*x.shape) * 60).astype("f4")
    vol = np.transpose(vol, (2, 1, 0))  # x,y,z
    hdr = bytearray(352)
    struct.pack_into("<i", hdr, 0, 348)
    struct.pack_into("<8h", hdr, 40, 3, shape[0], shape[1], shape[2], 1, 1, 1, 1)
    struct.pack_into("<h", hdr, 70, 16)
    struct.pack_into("<h", hdr, 72, 32)
    struct.pack_into("<8f", hdr, 76, 1, 2, 2, 2, 1, 1, 1, 1)
    struct.pack_into("<f", hdr, 108, 352)
    hdr[344:348] = b"n+1\0"
    with gzip.open(path, "wb") as fh:
        fh.write(bytes(hdr))
        fh.write(np.asfortranarray(vol).tobytes(order="F"))


def build_fake_tree(root=None):
    root = root or os.path.join(tempfile.gettempdir(), "UNP_fake")
    s = os.path.join(root, "SCRIPTS")
    _w(os.path.join(s, "Config", "P2.cfg"), P2_CFG)
    _w(os.path.join(s, "Config", "P1.cfg"), P1_CFG)
    _w(os.path.join(root, "PipelineEnvironment.sh"),
       f"export PROJECTS_HOME={root}\nexport SCRATCH={root}/scratch\nexport PROJECTS_DIR=\"Projects\"\n"
       f"export PP_SCRIPTS=${{PROJECTS_HOME}}/SCRIPTS\n")
    os.makedirs(os.path.join(root, "scratch"), exist_ok=True)
    proj = "psil_stutter"
    for sub, n in (("SP01", 6), ("SP02", 6), ("SP03", 2)):
        for i in range(1, n + 1):
            d = os.path.join(root, "Scans", proj, sub, f"Session{i:02d}", "BIDS")
            _w(os.path.join(d, "T1w.json"), "{}")
            _w(os.path.join(d, "T1w.nii.gz"), "")
    os.makedirs(os.path.join(root, "Scans", proj, "SP01", "mri_test"), exist_ok=True)
    os.makedirs(os.path.join(root, "Scans", "Anhedonia"), exist_ok=True)
    for sub in ("AN001", "AN002"):
        os.makedirs(os.path.join(root, "Scans", "Anhedonia", sub, "ses-01"), exist_ok=True)
    pdir = os.path.join(root, "Projects", proj)
    _w(os.path.join(pdir, "Study.cfg"), STUDY_CFG.format(root=root))
    for f in ("Participants", "Analysis", "Excluded", "logs"):
        os.makedirs(os.path.join(pdir, f), exist_ok=True)
    ip = os.path.join(pdir, "InProcess")
    scen = {"SP01_Session01": "ok", "SP01_Session02": "ok", "SP01_Session03": "fail", "SP01_Session04": "reg",
            "SP01_Session05": "stale", "SP01_Session06": "none", "SP02_Session01": "ok", "SP02_Session02": "ok",
            "SP02_Session03": "reg"}
    for sid, kind in scen.items():
        d = os.path.join(ip, sid)
        for sub in ("Logs", "QC", "Functional/Volume", "Functional/Surface", "Anatomical/Volume/T1", "Masks", "dicom"):
            os.makedirs(os.path.join(d, sub), exist_ok=True)
        _w(os.path.join(d, f"{sid}.params"), f'set T1 = ("ABCD_T1w_MPR_vNav_1.nii.gz")\nset BOLD = ("rest1.nii.gz" "rest2.nii.gz")\n')
        _w(os.path.join(d, f"{sid}_Execution.log"),
           f"Sat_Aug_22_02:55:27_AM_EDT_2026 : metcan01 : {sid} -reg -fMRI -surf -QC\n"
           f"Fri_Sep__4_05:48:43_PM_EDT_2026 : siegej08 : {sid} -BOLD -fMRI -surf -QC\n")
        fmt = dict(s=s, sid=sid, d=d)
        if kind in ("ok", "fail", "reg"):
            _w(os.path.join(d, "Logs", "Processing_Summary_Sat_Aug_22_02:55:27_AM_EDT_2026.txt"), SUMMARY_REG.format(**fmt))
        if kind == "ok":
            _w(os.path.join(d, "Logs", "Processing_Summary_Fri_Sep__4_05:48:43_PM_EDT_2026.txt"), SUMMARY_OK.format(**fmt))
            _w(os.path.join(d, "QC", f"{sid}_BOLD_FD_Thresholding_frame_count.txt"),
               "Run#,#BadFrames,#GoodFrames,%Remaining,SecondsRemaining\n1\t4\t313\t98\t626\n2\t11\t310\t96\t620\n3\t15\t300\t95\t600\n4\t17\t205\t92\t410\n")
            _w(os.path.join(d, "QC", "RMS_movements.txt"),
               "#total rms velocity at radius=50 mm     0.1109 mm/frame\n#total rms velocity at radius=50 mm     0.1957 mm/frame\n")
            _w(os.path.join(d, "QC", "fMRI_denoising.txt"),
               "Atlas Aligned resting state fMRI within brain sd: 23.095935\nDenoised resting state fMRI within brain sd: 6.030407\n")
            _w(os.path.join(d, "QC", "bold1_upck_faln_dbnd_xr3d_movement_plot.pdf"), "%PDF-1.4\n%fake\n")
            _w(os.path.join(d, "Functional", "Surface", f"{sid}_rsfMRI_uout_bpss_sr.ctx.dtseries.nii"), "")
            _w(os.path.join(d, "Functional", "Volume", f"{sid}_rsfMRI_uout_bpss.nii.gz"), "")
            _w(os.path.join(d, "Functional", "Volume", f"{sid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz"), "")
            _fake_nifti(os.path.join(d, "QC", "tmean.nii.gz"))
            _fake_nifti(os.path.join(d, "QC", "tSNR.nii.gz"))
        elif kind == "fail":
            _w(os.path.join(d, "Logs", "Processing_Summary_Thu_Sep__3_09:18:14_PM_EDT_2026.txt"), SUMMARY_FAIL.format(**fmt))
            _w(os.path.join(d, "Logs", "RunFCMRIBoldProcessing_Volume.csh.execution"),
               "\n".join(f"line {i}: doing stuff" for i in range(300)) + "\nERROR: something broke\n")
        elif kind == "stale":
            _w(os.path.join(d, "Logs", "Processing_Summary_Wed_Aug_19_22:32:55_EDT_2026.txt"), SUMMARY_STALE.format(**fmt))
            open(os.path.join(d, ".inprocess"), "w").close()
        if kind != "none":
            _w(os.path.join(d, "Anatomical", "Volume", "T1", f"{sid}_T1_atl.nii.gz"), "")
    return root


if __name__ == "__main__":
    print(build_fake_tree())
