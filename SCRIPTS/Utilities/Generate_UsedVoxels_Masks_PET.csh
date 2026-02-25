#!/bin/csh

#Assumes you have run Generate_UsedVoxels_Masks.csh already, which is part of the MR processing.

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

if($#argv > 2) then
	set SubjectHome = $3
else
	set SubjectHome = $cwd
endif

if($target != "") then
	set AtlasName = `basename $target`
else
	set AtlasName = ${patid}_T1
endif

set FinalResTrailer = _${PET_FinalResolution}${PET_FinalResolution}${PET_FinalResolution}

if(! $?day1_path) then
	set day1_path = ""
	set day1_patid = ""
	set TargetPatid = $patid
	set TargetHome = $SubjectHome
else
	set day1_patid = $day1_path:t
	set TargetPatid = $day1_patid
	set TargetHome = $day1_path
endif

set Modalities = ()

if(-e ${SubjectHome}/Anatomical/Volume/FDG/${patid}_FDG.nii.gz) set Modalities = ($Modalities FDG)
if(-e ${SubjectHome}/Anatomical/Volume/H2O/${patid}_H2O.nii.gz) set Modalities = ($Modalities H2O)
if(-e ${SubjectHome}/Anatomical/Volume/CO/${patid}_CO.nii.gz) set Modalities = ($Modalities CO)
if(-e ${SubjectHome}/Anatomical/Volume/O2/${patid}_O2.nii.gz) set Modalities = ($Modalities O2)

pushd Masks
	rm -rf PET_Masks
	mkdir PET_Masks

	cp ${patid}_used_voxels_T1${FinalResTrailer}.nii.gz ${patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz

	#take the base images, binarize, transform, multiply against each other, save the result
	foreach mode($Modalities)
		fslmaths ${SubjectHome}/Anatomical/Volume/${mode}/${patid}_${mode} -mul 0 -add 1 ${SubjectHome}/Masks/PET_Masks/${patid}_${mode}_defined_voxels
		if($status) exit 1

		flirt -in PET_Masks/${patid}_${mode}_defined_voxels -ref ${TargetHome}/Anatomical/Volume/T1/${TargetPatid}_T1${FinalResTrailer} -out PET_Masks/${patid}_${mode}_defined_voxels_to_${TargetPatid}_T1${FinalResTrailer} -init ${SubjectHome}/Anatomical/Volume/${mode}/${patid}_${mode}_to_${TargetPatid}_T1.mat -applyxfm -setbackground 0 -interp nearestneighbour
		if($status) exit 1

		fslmaths ${patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz -mul PET_Masks/${patid}_${mode}_defined_voxels_to_${TargetPatid}_T1${FinalResTrailer} -bin ${patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz
		if($status) exit 1
	end
popd
