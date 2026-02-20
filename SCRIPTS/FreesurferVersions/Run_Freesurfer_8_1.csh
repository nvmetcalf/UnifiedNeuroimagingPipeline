#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

decho "fs 8.1 recon-all WILL be run." $DebugFile

if(! $?T1) then
	decho "No T1 variable found in params. Cannot run Freesurfer." $DebugFile
	exit 1
endif

if(! -e ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz) then
	decho "${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz does not exist!" $DebugFile
	exit 1
else
	set T1 = "${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz"
endif

if($?T2 && ! -e ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_to_${patid}_T1.nii.gz) then
	decho "tse set in params file, but ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_to_${patid}_T1.nii.gz does not exist." $DebugFile
	exit 1
else if(-e ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_to_${patid}_T1.nii.gz) then
	set T2_args = "-T2 ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_to_${patid}_T1.nii.gz -T2pial"
else
	set T2_args = ""
endif

setenv SUBJECTS_DIR $SubjectHome/Freesurfer	#strip the end off so we store freesurfer in the participants folder
mkdir ${SUBJECTS_DIR}

decho "FREESURFER_HOME = $FREESURFER_HOME" $DebugFile
decho "SUBJECTS_DIR = $SUBJECTS_DIR" $DebugFile

decho "Running recon-all (check back in 24 hours)..." ${DebugFile}
decho "SUBJECTS_DIR = $SUBJECTS_DIR/Freesurfer/${FreesurferVersionToUse}" $DebugFile

#remove the old stuff that failed
if(-e $SUBJECTS_DIR/${FreesurferVersionToUse}) then
	rm -r $SUBJECTS_DIR/${FreesurferVersionToUse}
endif

recon-all -all -sd $SUBJECTS_DIR -s ${FreesurferVersionToUse} -i $T1 ${T2_args}
if($status) then
	decho "		FAILED! ${patid} failed freesurfer phase 1 segmentation." ${DebugFile}
	exit 1
endif

decho "performing sub region segmentations..." $DebugFile
segment_subregions thalamus --cross ${FreesurferVersionToUse} --sd $SubjectHome/Freesurfer
if($status) then
	decho "		FAILED! ${patid} failed to segment thalamus." $DebugFile
	exit 1
endif

segment_subregions hippo-amygdala --cross ${FreesurferVersionToUse} --sd $SubjectHome/Freesurfer
if($status) then
	decho "		FAILED! ${patid} failed to segment hippo-amygdala" $DebugFile
	exit 1
endif

segment_subregions brainstem --cross ${FreesurferVersionToUse} --sd $SubjectHome/Freesurfer
if($status) then
	decho "		FAILED! ${patid} failed to segment brainstem" $DebugFile
	exit 1
endif

rm fsaverage

exit 0
