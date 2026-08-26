#!/bin/csh

source $1
source $2

set SubjectHome = $cwd
if (! -e ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtmseg.mgz) then

	if($?day1_path) then
		ln -s ${day1_path}/Freesurfer .
		if($status)then
			echo "Could not find ${day1_path}/Freesurfer"
			exit 1
		endif
	endif

	setenv SUBJECTS_DIR $SubjectHome/Freesurfer

	echo "Running gtmseg..."
	gtmseg --s $FreesurferVersionToUse --xcerseg
	if($status) then
		echo "gtmseg failed."
		exit 1
	endif
else
	echo "gtmseg found!"
endif

if(! -e $SubjectHome/PET/Parcellations/$FreesurferVersionToUse) then
	mkdir -p PET/Parcellations/$FreesurferVersionToUse
	if($status) exit 1
endif

pushd $SubjectHome/PET/Parcellations/$FreesurferVersionToUse
	rm gtmseg+wmparc.*
	echo "replacing gtmseg white matter parcellation with freesurfers white matter parcellation."

	python3 $PP_SCRIPTS/PET/python3/big_wmparc.py ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/wmparc.mgz ${SubjectHome}/PET/Parcellations/$FreesurferVersionToUse/wmparc_big.mgz
	if($status) then
		echo "python3/big_wmparc.py failed. Check to make sure you have the dependencies installed."
		exit 1
	endif

	mri_vol2vol --mov ${SubjectHome}/PET/Parcellations/$FreesurferVersionToUse/wmparc_big.mgz --lta-inv ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtmseg.lta --targ ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtmseg.mgz --o ${SubjectHome}/PET/Parcellations/$FreesurferVersionToUse/wmparc_on_gtmseg.mgz --nearest
	if($status) then
		echo "mri_vol2vol failed to register the wmparc_big.mgz to gtmseg."
		exit 1
	endif

	python3 $PP_SCRIPTS/PET/python3/add_wm.py ${SubjectHome}/PET/Parcellations/$FreesurferVersionToUse/wmparc_on_gtmseg.mgz ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtmseg.mgz ${SubjectHome}/PET/Parcellations/$FreesurferVersionToUse/gtmseg+wmparc.mgz
	if($status) then
		echo "python3/add_wm.py failed. Check to make sure you have the dependencies installed."
		exit 1
	endif

	cp $PP_SCRIPTS/PET/misc/"gtmseg+wmparc.ctab" .
	if($status) then
		echo "failed to copy $PP_SCRIPTS/PET/.fdb/gtmseg+wmparc.ctab."
		exit 1
	endif

	cp ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtmseg.lta "gtmseg+wmparc.lta"
	if($status) then
		echo "failed to copy ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtmseg.lta."
		exit 1
	endif

	#take the gtmseg.lta, invert it, and combine it with the orig -> t1 transform
	lta_convert -inlta ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtmseg.lta -outlta ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtm_to_orig.lta --invert
	if($status) exit 1

	mri_vol2vol --mov ${SubjectHome}/PET/Parcellations/$FreesurferVersionToUse/gtmseg+wmparc.mgz --lta-inv ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/gtm_to_orig.lta --targ ${SubjectHome}/Freesurfer/$FreesurferVersionToUse/mri/orig.mgz --o ${SubjectHome}/PET/Parcellations/$FreesurferVersionToUse/gtmseg+wmparc_orig.nii.gz --nearest
	if($status) then
		echo "mri_vol2vol failed to register the gtmseg+wmparc to orig."
		exit 1
	endif

	cp $PP_SCRIPTS/PET/misc/"gtmseg+wmparc.ctab" "gtmseg+wmparc_orig.ctab"
	if($status) then
		echo "failed to copy $PP_SCRIPTS/PET/.fdb/gtmseg+wmparc_orig.ctab."
		exit 1
	endif
exit 0
