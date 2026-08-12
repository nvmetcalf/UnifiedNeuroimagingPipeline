#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

#generate gray plots
if($?FCProcIndex && -e ${SubjectHome}/Anatomical/Surface/RibbonVolumeToSurfaceMapping/ribbon_only.nii.gz) then
	pushd QC
		matlab -nodesktop -softwareopengl -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));VolumeGrayPlotQC('$patid','${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt','${SubjectHome}/Functional/TemporalMask/run_boundaries_tmask.txt','${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_mov_eacsf_vent_wm_gs_resid.nii.gz','${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz','${SubjectHome}/Anatomical/Surface/RibbonVolumeToSurfaceMapping/ribbon_only.nii.gz',${BOLD_TR},$FD_File,$DVAR_File);end;exit"
	popd
else if($?FCProcIndex && $?FC_Parcellation) then
	pushd QC
		matlab -nodesktop -softwareopengl -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));VolumeGrayPlotQC('$patid','${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt','${SubjectHome}/Functional/TemporalMask/run_boundaries_tmask.txt','${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_mov_eacsf_vent_wm_gs_resid.nii.gz','${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz','${FC_Parcellation}',${BOLD_TR},$FD_File,$DVAR_File);end;exit"
	popd
endif
