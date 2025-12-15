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

set FinalResolution = $BOLD_FinalResolution

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if(! $?CSF_sd1t) then
	set CSF_sd1t    = 25            # threshold for CSF voxels in sd1 image
endif

if(! $?CSF_lcube) then
	set CSF_lcube   = 3             # cube dimension (in voxels) used by qntv_4dfp
endif

if(! $?CSF_svdt) then
	set CSF_svdt    = .2            # limit regressor covariance condition number to (1./{})^2
endif

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

	#compute an approximate skull image to mask from the region.
	bet ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1${mask_trailer}_${FinalResTrailer} ${patid}_T1${mask_trailer}_${FinalResTrailer} -s -R
	if($status) exit

	#make a brain compliment so we don't accidentally include brain in the skull image
	fslmaths ${SubjectHome}/Masks/${patid}_used_voxels${mask_trailer}_${FinalResTrailer} -mul -1 -add 1 brain_comp
	if($status) exit 1

	#dilate the skull, remove the brain, make a compliment so we can remove only known skull
	fslmaths ${patid}_T1${mask_trailer}_${FinalResTrailer}_skull -dilD -mul brain_comp -mul -1 -add 1 skull_comp
	if($status) exit 1

	#make the outside of brain without eyes mask
	if($target != "") then
		fslmaths ${SubjectHome}/Masks/${patid}_used_voxels${mask_trailer}_${FinalResTrailer} -dilD -bin -mul "-1" -add 1 -mul $PP_SCRIPTS/Masks/eyes_${FinalResTrailer}z -mul ${concroot}_dfnd -mul skull_comp ${SubjectHome}/Functional/Regressors/${patid}_eaCSF_region
		if($status) exit 1
	else
		#we are using native space, so need to make a version of the eyes mask in this persons space.
		flirt -in $PIPELINE_HOME/ATLAS/MNI152/MNI152_T1_1mm_${FinalResTrailer}.nii.gz -ref $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer} -omat eyes_to_T1.mat
		if($status) exit 1

		flirt -in $PP_SCRIPTS/Masks/eyes_${FinalResTrailer}z -ref $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer} -out eyes_${FinalResTrailer}z -interp nearestneighbour -applyxfm -init eyes_to_T1.mat
		if($status) exit 1

		fslmaths ${SubjectHome}/Masks/${patid}_used_voxels${mask_trailer}_${FinalResTrailer} -dilD -bin -mul "-1" -add 1 -mul eyes_${FinalResTrailer}z -mul ${concroot}_dfnd -mul skull_comp ${SubjectHome}/Functional/Regressors/${patid}_eaCSF_region
		if($status) exit 1
	endif

	conc2nifti -K ${concroot}_uout_bpss.conc
	if($status) exit 1

 	fslmaths ${concroot}_uout_bpss -nan -Tstd ${concroot}_uout_bpss_sd
 	if($status) exit 1

 	set CSF_thr = `fslstats ${concroot}_uout_bpss_sd -n -k ${SubjectHome}/Functional/Regressors/${patid}_eaCSF_region -S | awk '{print($1 * 2)}'`

 	echo "==========="
 	echo ""
 	echo "CSF_thr (2 sd outside brain, no eyes) = " $CSF_thr
 	echo ""
 	echo "==========="

	fslmaths ${concroot}_uout_bpss_sd -nan -thr $CSF_thr -bin -fillh26 -mul ${SubjectHome}/Functional/Regressors/${patid}_eaCSF_region ${SubjectHome}/Functional/Regressors/${patid}_eaCSF_mask
	if($status) exit 1

	niftigz_4dfp -4 ${SubjectHome}/Functional/Regressors/${patid}_eaCSF_mask ${patid}_eaCSF_mask
	if($status) exit 1
popd

pushd ${SubjectHome}/Functional/Regressors
	# compute extra-axial CSF mask
	@ n = `echo $CSF_lcube | awk '{print int($1^3/2)}'`	# minimum cube defined voxel count is 1/2 total
	qntv_4dfp ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_eaCSF_mask -F$format -l$CSF_lcube -t$CSF_svdt -n1 -D -O4 -o${patid}_EACSF_regressors.dat
	if ($status == 254) then

		decho "computing CSF regressors with minimum ROI size 1" $DebugFile
		qntv_4dfp ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_eaCSF_mask -F$format -l$CSF_lcube -t$CSF_svdt -n1  -D -O4 -o${patid}_eaCSF_regressors.dat
		if ($status) then
			echo "No extra axial CSF regressors identified."
			exit 1
		endif
	endif
	rm *.4dfp.*
popd

exit 0
