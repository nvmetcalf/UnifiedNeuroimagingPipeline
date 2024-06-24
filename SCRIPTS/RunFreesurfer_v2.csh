#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

if(! $?skip_recon) then
	set skip_recon = 0
endif

if($skip_recon) then
	decho "-no_recon set, skipping recon all" $DebugFile
	exit 0
endif

if($?day1_path || $?day1_patid) then
	decho "sessions is not a first session, skipping recon-all" $DebugFile
	exit 0
endif

if(`tail -1 ${SubjectHome}/Freesurfer/scripts/recon-all.log | grep "without error"` != "") then
	decho "recon-all has already been completed" $DebugFile
	exit 0
endif

decho "recon-all WILL be run." $DebugFile

if(! $?mprs) then
	decho "No mprs variable found in params. Cannot run Freesurfer." $DebugFile
	exit 1
endif

if(! -e ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz) then
	decho "${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz does not exist!" $DebugFile
	exit 1
else
	set T1 = "${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz"
endif

if($?tse && ! -e ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_to_${patid}_T1.nii.gz) then
	decho "tse set in params file, but ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_to_${patid}_T1.nii.gz does not exist." $DebugFile
	exit 1
else if(-e ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_to_${patid}_T1.nii.gz) then
	set T2_args = "-T2 ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_to_${patid}_T1.nii.gz -T2pial"
else 
	set T2_args = ""
endif

decho "Running recon-all (check back in 24 hours)..." ${DebugFile}
decho "SUBJECTS_DIR = $SUBJECTS_DIR/Freesurfer" $DebugFile
	
setenv SUBJECTS_DIR $SubjectHome	#strip the end off so we store freesurfer in the participants folder
rm -rf ${SUBJECTS_DIR}/Freesurfer

#we are using the pre-bias corrected T1 and T2/FLAIR so that freesurfer will have to "less work"

recon-all -autorecon1 -autorecon2 -sd $SubjectHome -s Freesurfer -i $T1 ${T2_args}
if($status) then
	decho "		FAILED! ${patid} failed freesurfer phase 1 segmentation." ${DebugFile}
	exit 1
endif



#compliment the freesurfer wm mask
#add the fslwhitematter segment
#backup the original wm.mgz
#replace the wm.mgz with the combined image.
pushd Freesurfer/mri
	mri_convert nu.mgz nu.nii.gz
	if($status) exit 1
	
	flirt -in $SubjectHome/Anatomical/Volume/T1/${patid}_T1.nii.gz -ref nu.nii.gz -omat T1_to_nu.mat -dof 6
	if($status) exit 1
	
	#see if we want to check how far a voxel displaces
	flirt -in nu.nii.gz -ref $SubjectHome/Anatomical/Volume/T1/${patid}_T1.nii.gz -omat nu_to_T1_rev.mat
	if($status) exit 1
		
	set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh $SubjectHome/Anatomical/Volume/T1/${patid}_T1.nii.gz nu.nii.gz T1_to_nu.mat nu_to_T1_rev.mat 0 50 0`
	decho "2 way registration displacement: $Displacement" registration_displacement.txt
		
	if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh $SubjectHome/Anatomical/Volume/T1/${patid}_T1.nii.gz nu.nii.gz T1_to_nu.mat nu_to_T1_rev.mat 0 50 0 1`) then
		decho "	Error: Registration from T1 to nu and nu to T1 has a displacement of "$Displacement
		exit 1
	endif

	#take the fsl whitematter segmentation
	#register it to the orig
	flirt -in $SubjectHome/Anatomical/Volume/T1/${patid}_T1_brain_seg_2 -ref nu.nii.gz -out fsl_wm_seg.nii.gz -init T1_to_nu.mat -applyxfm -interp nearestneighbour
	if($status) exit 1
	
	mri_convert wm.mgz wm.nii.gz
	if($status) exit 1
		
	#scale the fsl segmentation to 255
	fslmaths fsl_wm_seg -bin -fillh26 fsl_wm_seg_filled
	if($status) exit 1
	
	#remove wm voxels that exist in the freesurfer wm segmentation
	fslmaths wm.nii.gz -mul fsl_wm_seg_filled wm_fsl_masked
	if($status) exit 1

	mv wm.mgz wm.bak.mgz
	
	mri_convert wm_fsl_masked.nii.gz wm.mgz
	if($status) exit 1
	
popd

exit 0

recon-all -autorecon2-wm -autorecon3 -sd $SubjectHome -s Freesurfer ${T2_args}
if($status) then
	decho "		FAILED! ${patid} failed freesurfer phase 2 segmentation." ${DebugFile}
	exit 1
endif

decho "performing sub region segmentations..." $DebugFile
segment_subregions thalamus --cross Freesurfer --sd $SubjectHome
if($status) then
	decho "		FAILED! ${patid} failed to segment thalamus." $DebugFile
	exit 1
endif

segment_subregions hippo-amygdala --cross Freesurfer --sd $SubjectHome
if($status) then
	decho "		FAILED! ${patid} failed to segment hippo-amygdala" $DebugFile
	exit 1
endif

segment_subregions brainstem --cross Freesurfer --sd $SubjectHome
if($status) then
	decho "		FAILED! ${patid} failed to segment brainstem" $DebugFile
	exit 1
endif

rm fsaverage
exit 0
