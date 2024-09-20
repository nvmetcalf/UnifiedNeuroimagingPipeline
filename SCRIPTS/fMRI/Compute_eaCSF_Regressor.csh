#!/bin/csh

source $1
source $2

set concroot	= $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI
set conc	= $concroot.conc

set SubjectHome = $cwd

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

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
	
	
if($NonLinear) then
	set mask_trailer = "_fnirt"
else
	set mask_trailer = ""
endif

#################################
# make extra-axial CSF regressors
#################################
pushd ${SubjectHome}/Masks/FreesurferMasks

	niftigz_4dfp -n ${concroot}_dfnd ${concroot}_dfnd
	if($status) exit 1
	
	#make the outside of brain without eyes mask
	if($target != "") then
		fslmaths ${SubjectHome}/Masks/${patid}_used_voxels${mask_trailer}_${FinalResTrailer} -dilD -bin -mul "-1" -add 1 -mul $PP_SCRIPTS/Masks/eyes_${FinalResTrailer}z -mul ${concroot}_dfnd ${SubjectHome}/Masks/FreesurferMasks/${patid}_eaCSF_region
		if($status) exit 1
	else
		#we are using native space, so need to make a version of the eyes mask in this persons space.
		flirt -in $PIPELINE_HOME/ATLAS/MNI152/MNI152_T1_1mm_${FinalResTrailer}.nii.gz -ref $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer} -omat eyes_to_T1.mat
		if($status) exit 1
		
		flirt -in $PP_SCRIPTS/Masks/eyes_${FinalResTrailer}z -ref $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer} -out eyes_${FinalResTrailer}z -interp nearestneighbour -applyxfm -init eyes_to_T1.mat
		if($status) exit 1
		
		fslmaths ${SubjectHome}/Masks/${patid}_used_voxels${mask_trailer}_${FinalResTrailer} -dilD -bin -mul "-1" -add 1 -mul eyes_${FinalResTrailer}z -mul ${concroot}_dfnd ${SubjectHome}/Masks/FreesurferMasks/${patid}_eaCSF_region
		if($status) exit 1
	endif
	
	conc2nifti -K ${concroot}_uout_bpss.conc
	if($status) exit 1
	
 	fslmaths ${concroot}_uout_bpss -nan -Tstd ${concroot}_uout_bpss_sd
 	if($status) exit 1
 	
# 	set CSF_thr = `fslstats ${concroot}_uout_bpss_sd -n -k ${SubjectHome}/Masks/FreesurferMasks/${patid}_eaCSF_region -S | awk '{print($1 * 1)}'`
# 	
# 	echo "==========="
# 	echo ""
# 	echo "CSF_thr (1 sd outside brain, no eyes) = " $CSF_thr
# 	echo ""
# 	echo "==========="
# 	
	fslmaths ${concroot}_uout_bpss_sd -nan -thr $CSF_sd1t -bin -fillh26 -mul ${SubjectHome}/Masks/FreesurferMasks/${patid}_eaCSF_region ${patid}_EACSF_mask
	if($status) exit 1
	
	niftigz_4dfp -4 ${patid}_EACSF_mask ${patid}_EACSF_mask
	if($status) exit 1
popd

pushd ${SubjectHome}/Functional/Regressors
	# compute extra-axial CSF mask
	@ n = `echo $CSF_lcube | awk '{print int($1^3/2)}'`	# minimum cube defined voxel count is 1/2 total
	qntv_4dfp ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_EACSF_mask -F$format -l$CSF_lcube -t$CSF_svdt -n1 -D -O4 -o${patid}_EACSF_regressors.dat
	if ($status == 254) then

		decho "computing CSF regressors with minimum ROI size 1" $DebugFile
		qntv_4dfp ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_EACSF_mask -F$format -l$CSF_lcube -t$CSF_svdt -n1  -D -O4 -o${patid}_EACSF_regressors.dat
		if ($status) then
			echo "No extra axial CSF regressors identified."
			exit 1
		endif
	endif

	popd 

exit 0
