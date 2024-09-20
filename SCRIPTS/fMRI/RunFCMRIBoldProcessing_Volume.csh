#!/bin/csh

#run the volume fcmri preprocessing

set ParamsFile = $1
set ProcessingParams = $2

source $ParamsFile
source $ProcessingParams

set SubjectHome = $cwd
#if we are not doing iterative regression and the fcmaps folder exists
#then remove the folder

#clean out the old fcPreproc
if(! $?FCProcIndex) then
	decho "Unable to preprocess fMRI runs as there are no runs specified to be processed. FCProcIndex not set" $DebugFile
	exit 1
endif

if(! $?day1_path) then
	set day1_path = ""
	set day1_patid = ""
endif

if(! -e ${SubjectHome}/Freesurfer/mri/aparc+aseg.mgz && $day1_path == "") then
	decho "ERROR - aparc+aseg.mgz not found for subject $patid. Freesurfer needs to be completed first." ${DebugFile}
	exit 1
else if($day1_path != "" && ! -e $day1_path/Freesurfer/mri/aparc+aseg.mgz) then
	decho "ERROR - aparc+aseg.mgz not found for subject $day1_patid ($day1_path/Freesurfer/mri). Freesurfer needs to be completed first on the first session." $DebugFile
endif

echo "Clearing out rsfMRI results..."
rm ${SubjectHome}/Functional/Volume/*rsfMRI*

echo "Running fcMRI preprocessing..."

if($FD_Threshold != "0") then
	$PP_SCRIPTS/Utilities/Compute_temporal_mask.csh $ParamsFile $ProcessingParams

	if($status) then
		exit 1
	endif
endif

if($FD_Threshold != 0) then
	set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format
endif

## Run Avi's preproc script
$PP_SCRIPTS/fMRI/FcMRI_preprocessing.csh $ParamsFile -options $ProcessingParams -format $format
if($status) then
	decho "		fcMRI preprocessing did not complete properly." ${DebugFile}
	exit 1
endif

########################################################################
## Compute a temporal mask
##
##	Computes a mask of frames to exclude based upon the
##	DVAR or FD values in the Study.cfg file. If a percent
##	frames remaining criteria is present in the Study.cfg
##	then runs that do not have enough frames remaining will
##	be removed from the conc file.
#########################################################################

if($DVAR_Threshold != "0" || $FD_Threshold != "0") then
	$PP_SCRIPTS/Utilities/Compute_temporal_mask.csh $ParamsFile $ProcessingParams

	if($status) then
		exit 1
	endif
endif

#################
#	Iterative Regression. This basically just runs fcMRI preproc using a format
#################
if($UseIterativeRegression && $DoVolumeRegression) then
	
	if( ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz) then
		decho "ERROR:denoised timeseries does not exist!"
		exit 1
	endif

	#need to add the flag for a format

	if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
		set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_dvar.format
	else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
		set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format
	else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
		set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_resid_dvar_fd.format
	else
		decho "Unknown combination of format criteria. Iterative rsfMRI processing not possible." ${DebugFile}
		exit 1
	endif
		

	$PP_SCRIPTS/fMRI/FcMRI_preprocessing.csh $ParamsFile -options $ProcessingParams -format $format
	if($status) then
		exit 1
	endif
endif

decho "		Finished!" ${DebugFile}
exit 0
