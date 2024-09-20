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
 
recon-all -all -sd $SubjectHome -s Freesurfer -i $T1 ${T2_args}
if($status) then
	decho "		FAILED! ${patid} failed freesurfer phase 1 segmentation." ${DebugFile}
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
