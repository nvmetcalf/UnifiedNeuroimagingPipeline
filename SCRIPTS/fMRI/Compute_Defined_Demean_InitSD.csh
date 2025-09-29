#!/bin/csh

if(! -e $1) then
	echo "SCRIPT: $0 : 00001 : $1 does not exist"
	exit 1
endif

if(! -e $2) then
	echo "SCRIPT: $0 : 00002 : $2 does not exist"
	exit 1
endif

source $1
source $2

set concroot	= $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI
set conc	= $concroot.conc
set SubjectHome = $cwd

if(! $?day1_path) then
	set day1_path = ""
	set day1_patid = ""
else
	set day1_patid = $day1_path:t
endif

if($target != "") then
	set AtlasName = `basename $target`
else
	if($day1_path == "") then
		set AtlasName = ${patid}_T1
	else
		set AtlasName = ${day1_patid}_T1
	endif
endif

set FinalResolution = $BOLD_FinalResolution

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if( ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz) then
	set DVAR_Threshold = 0
	decho "WARNING: Disabling DVAR threshold as denoised timeseries does not exist!"
endif

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

pushd Functional/Volume

	#########################
	# make timeseries zero mean
	#########################
	var_4dfp -F$format -m $conc
	if ($status) exit $status

	conc2nifti ${concroot}_uout.conc
	if($status) exit 1

	gzip -fc ${concroot}_uout.nii > ${SubjectHome}/Functional/Volume/${patid}_rsfMRI.nii.gz
	if($status) exit 1

	#mv ${concroot}_uout.nii.gz ${SubjectHome}/Functional/Volume/${patid}_rsfMRI.nii.gz
	#if($status) exit 1


	##########################
	# run compute_defined_4dfp
	##########################
	COMPUTE_DEFINED:
	pushd $ScratchFolder/${patid}/BOLD_temp/
		compute_defined_4dfp -F$format ${concroot}.conc
		if ($status) exit $status
	popd

	niftigz_4dfp -4 ${SubjectHome}/Masks/FreesurferMasks/${patid}_FSWB_on_${AtlasName}_${FinalResTrailer} ${SubjectHome}/Masks/FreesurferMasks/${patid}_FSWB_on_${AtlasName}_${FinalResTrailer}
	if($status) exit 1

	maskimg_4dfp ${concroot}_dfnd ${SubjectHome}/Masks/FreesurferMasks/${patid}_FSWB_on_${AtlasName}_${FinalResTrailer} ${concroot}_dfndm
	if ($status) exit $status

	niftigz_4dfp -n ${concroot}_dfndm ${SubjectHome}/Masks/FreesurferMasks/`basename ${concroot}`_dfndm
	if($status) exit 1

	#create our defined voxels whole brain mask
	fslmaths ${SubjectHome}/Masks/FreesurferMasks/${patid}_FSWB_on_${AtlasName}_${FinalResTrailer} -mul ${SubjectHome}/Masks/FreesurferMasks/`basename ${concroot}`_dfndm ${SubjectHome}/Masks/FreesurferMasks/${patid}_WholeBrain_mask
	if($status) exit 1

	#use the raw bold to determine the coefficient of variance. Should be atlas transformed
	fslmaths ${SubjectHome}/Functional/Volume/${patid}_rsfMRI.nii.gz -Tstd -mul ${SubjectHome}/Masks/FreesurferMasks/${patid}_WholeBrain_mask ${SubjectHome}/Masks/FreesurferMasks/std -odt float

	set STD = `fslstats ${SubjectHome}/Masks/FreesurferMasks/std -S`
	echo $STD
	set MEAN_SD = `fslstats ${SubjectHome}/Masks/FreesurferMasks/std -M`
	echo $MEAN_SD
	set Upper = `echo "$MEAN_SD + ($STD * 3)" | bc -l`
	echo $Upper
	set Lower = `echo "$MEAN_SD - ($STD * 3)" | bc -l`
	echo $Upper

	#generate a SD image based on the input timeseries, threshold it at 3, then binarize it
	fslmaths ${SubjectHome}/Masks/FreesurferMasks/std -uthr $Upper -bin ${SubjectHome}/Masks/FreesurferMasks/${patid}_rsfMRI_sd_mask.nii.gz
	if($status) exit 1

	fslmaths ${SubjectHome}/Masks/FreesurferMasks/${patid}_WholeBrain_mask -mul ${SubjectHome}/Masks/FreesurferMasks/${patid}_rsfMRI_sd_mask.nii.gz ${SubjectHome}/Masks/FreesurferMasks/${patid}_WholeBrain_mask
	if($status) exit 1

	niftigz_4dfp -4 ${SubjectHome}/Masks/FreesurferMasks/${patid}_WholeBrain_mask ${SubjectHome}/Masks/FreesurferMasks/${patid}_WholeBrain_mask
	if($status) exit 1

	#####################
	# compute initial sd1
	#####################
	var_4dfp -s -F$format ${concroot}_uout.conc
	if($status) exit 1

	ifh2hdr -r20 ${concroot}_uout_sd1
	if($status) exit 1

popd

exit 0
