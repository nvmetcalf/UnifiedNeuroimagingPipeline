#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

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

setenv SUBJECTS_DIR $SubjectHome/Freesurfer	#strip the end off so we store freesurfer in the participants folder
mkdir ${SUBJECTS_DIR}

decho "FREESURFER_HOME = $FREESURFER_HOME" $DebugFile
decho "SUBJECTS_DIR = $SUBJECTS_DIR" $DebugFile

decho "Running recon-all (check back in 24 hours)..." ${DebugFile}

setenv SUBJECTS_DIR $SubjectHome/Freesurfer/${FreesurferVersionToUse}	#strip the end off so we store freesurfer in the participants folder
rm -rf ${SUBJECTS_DIR}/Freesurfer/${FreesurferVersionToUse}

#remove the old stuff that failed
if(-e $SUBJECTS_DIR/${FreesurferVersionToUse}) then
	rm -r $SUBJECTS_DIR/${FreesurferVersionToUse}
endif

recon-all -all -sd $SUBJECTS_DIR -s ${FreesurferVersionToUse} -i $T1
if($status) then
	decho "		FAILED! ${patid} failed freesurfer segmentation." ${DebugFile}
	exit 1
endif

rm fsaverage

exit 0
