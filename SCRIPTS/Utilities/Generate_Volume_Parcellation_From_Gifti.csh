#!/bin/csh

source $1
source $2

if(! $?ParcellationName) then
	echo "ParcellationName needs to be set in the Study.cfg and exist in $PP_SCRIPTS/Parcellation."
	exit 1
endif

if($?day1_path) then
	set target = $day1_path:t
	set target_path = $day1_path
	set target_patid = $day1_path:t
else
	set target = $patid
	set target_path = $cwd
	set target_patid = $patid
endif

set Parcellation_ctab = /data/nil-bluearc/vlassenko/Pipeline/SCRIPTS/Parcellation/${ParcellationName}/${ParcellationName}.ctab
set Parcellation_LHlabel = /data/nil-bluearc/vlassenko/Pipeline/SCRIPTS/Parcellation/${ParcellationName}/${ParcellationName}.L.32k.label.gii
set Parcellation_RHlabel = /data/nil-bluearc/vlassenko/Pipeline/SCRIPTS/Parcellation/${ParcellationName}/${ParcellationName}.R.32k.label.gii

if(! -e $Parcellation_ctab || ! -e $Parcellation_LHlabel || ! -e $Parcellation_RHlabel) then
	echo "one or more of the following do not exist:"
	echo $Parcellation_ctab
	echo $Parcellation_LHlabel
	echo $Parcellation_RHlabel
	exit 1
endif

set ParticipantsFolder = $cwd

setenv SUBJECTS_DIR $ParticipantsFolder

if(! -e $target_path/Freesurfer/${FreesurferVersionToUse}) then
	echo "$target_path/Freesurfer does not exist."
	exit 1
endif

if (! -e ${target_path}/Freesurfer/${FreesurferVersionToUse}/mri/gtmseg.mgz) then
	echo "gtmseg has not been completed. Unable to continue."
	exit 1
endif

if(! -e ${target_path}/Anatomical/Surface/fsaverage_LR32k/${target_patid}.L.midthickness.32k_fs_LR.surf.gii) then
	echo "Surface projection does not seem to have completed successfully."
	exit 1
endif

#determine which version of the pipeline was used
 if(-e ${ParticipantsFolder}/PET/gtmseg+wmparc.mgz) then
 	set gtmseg = ${ParticipantsFolder}/PET/gtmseg+wmparc.mgz
 else if(-e ${SUBJECTS_DIR}/PET/gtmseg+wmparc.mgz) then
	set gtmseg = ${SUBJECTS_DIR}/PET/gtmseg+wmparc.mgz
else if(-e ${ParticipantsFolder}/PET/Parcellations/${FreesurferVersionToUse}/gtmseg+wmparc.mgz) then
 	set gtmseg = ${ParticipantsFolder}/PET/Parcellations/${FreesurferVersionToUse}/gtmseg+wmparc.mgz
else
	echo "Could not find a gtmseg.mgz."
	exit 1
endif

echo $cwd
rm -r PET/Parcellations/$ParcellationName
mkdir -p PET/Parcellations/$ParcellationName
pushd PET/Parcellations/$ParcellationName
	#niftigz_4dfp -n orig orig
	mri_convert $target_path/Freesurfer/${FreesurferVersionToUse}/mri/orig.mgz orig.nii.gz
	if($status) exit 1
	set orig_image = $cwd/orig.nii.gz

	wb_command -label-to-volume-mapping $Parcellation_LHlabel ${target_path}/Anatomical/Surface/fsaverage_LR32k/${target_patid}.L.midthickness.32k_fs_LR.surf.gii $orig_image LH_parcellation.nii.gz -ribbon-constrained ${target_path}/Anatomical/Surface/fsaverage_LR32k/${target_patid}.L.white.32k_fs_LR.surf.gii ${target_path}/Anatomical/Surface/fsaverage_LR32k/${target_patid}.L.pial.32k_fs_LR.surf.gii
	if($status) exit 1

	wb_command -label-to-volume-mapping $Parcellation_RHlabel ${target_path}/Anatomical/Surface/fsaverage_LR32k/${target_patid}.R.midthickness.32k_fs_LR.surf.gii $orig_image RH_parcellation.nii.gz -ribbon-constrained ${target_path}/Anatomical/Surface/fsaverage_LR32k/${target_patid}.R.white.32k_fs_LR.surf.gii ${target_path}/Anatomical/Surface/fsaverage_LR32k/${target_patid}.R.pial.32k_fs_LR.surf.gii
	if($status) exit 1

	fslmaths LH_parcellation.nii.gz -bin -mul -1 -add 1 -mul RH_parcellation.nii.gz RH_parcellation.nii.gz
	if($status) exit

	fslmaths LH_parcellation.nii.gz -add RH_parcellation.nii.gz $ParcellationName"_orig.nii.gz"
	if($status) exit 1

	lta_convert --inlta ${target_path}/Freesurfer/${FreesurferVersionToUse}/mri/gtmseg.lta --outlta gtm_to_orig.lta --invert
	if($status) exit 1

	#strip the cortical regions from the gtmswg+wmparc, mask the parcellation by that, then add the parcellation to the stripped gtmseg+wmparc
	mri_convert $gtmseg "gtmseg+wmparc.nii.gz"
	if($status) exit 1

	mri_vol2vol --mov "gtmseg+wmparc.nii.gz" --lta gtm_to_orig.lta --targ $orig_image --o "gtmseg+wmparc_on_orig.nii.gz" --nearest
	if ($status) exit 1

	fslmaths "gtmseg+wmparc_on_orig.nii.gz" -thr 1000 -uthr 3000 -bin cortical_regions.nii.gz
	if($status) exit 1

	fslmaths cortical_regions -mul -1 -add 1 cortical_regions_comp
	if($status) exit 1

	fslmaths "gtmseg+wmparc_on_orig.nii.gz" -mul cortical_regions_comp "gtmseg+wmparc_no_cortex.nii.gz"
	if($status) exit 1

	fslmaths $ParcellationName"_orig.nii.gz" -dilD -dilD -mul cortical_regions.nii.gz -add 20000 -thr 20001 $ParcellationName"_orig_cortical_regions.nii.gz"
	if($status) exit 1

	fslmaths "gtmseg+wmparc_no_cortex.nii.gz" -add $ParcellationName"_orig_cortical_regions.nii.gz" $ParcellationName"_orig"
	if($status) exit 1

	flirt -in $ParcellationName"_orig" -ref ${target_path}/Masks/FreesurferMasks/${target_patid}_orig_to_${target_patid}_T1 -out $ParcellationName"_T1" -init ${target_path}/Masks/FreesurferMasks/${target_patid}_orig_to_${target_patid}_T1.mat -applyxfm -interp nearestneighbour
	if($status) exit 1

	mri_vol2vol --mov $ParcellationName"_orig.nii.gz" --lta ${target_path}/Freesurfer/${FreesurferVersionToUse}/mri/gtmseg.lta --targ gtmseg+wmparc.nii.gz --o "${ParcellationName}_gtm.nii.gz" --nearest
	if ($status) exit 1

	mri_convert ${ParcellationName}_gtm.nii.gz ${ParcellationName}_gtm.mgz
	if($status) exit 1

	cp $Parcellation_ctab $ParcellationName"_orig.ctab"
	cp $Parcellation_ctab $ParcellationName"_T1.ctab"
	cp $Parcellation_ctab $ParcellationName"_gtm.ctab"

popd
exit 0
