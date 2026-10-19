#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

if($?day1_patid) then
	set target = $day1_path:t
	set target_path = $day1_path
	set target_patid = $day1_path:t
else
	set target = $patid
	set target_path = $SubjectHome
	set target_patid = $patid
endif

if($PET_FinalResolution == 0) then
	set FinalResTrailer = ""
else
	set FinalResTrailer = _${PET_FinalResolution}${PET_FinalResolution}${PET_FinalResolution}
endif

pushd PET/Volume

	if(! -e ${patid}_O2_on_T1${FinalResTrailer}_norm.nii.gz || ! -e ${patid}_H2O_on_T1${FinalResTrailer}_norm.nii.gz || ! -e ${patid}_CO_on_T1${FinalResTrailer}_norm.nii.gz || ! -e ${SubjectHome}/Masks/${patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz) then
		echo "Cannot compute OM as one or more of the following are missing: O2, H2O, CO, mask"
		exit 0
	endif

	echo "Computing OM..."
		python3 $PP_SCRIPTS/python3/compute_CMRO2_OEF.py ${patid}_O2_on_T1${FinalResTrailer}_norm.nii.gz ${patid}_H2O_on_T1${FinalResTrailer}_norm.nii.gz ${patid}_CO_on_T1${FinalResTrailer}_norm.nii.gz ${SubjectHome}/Masks/${patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz ${patid}_CMRO2_on_T1${FinalResTrailer}.nii.gz temp.nii.gz
		if ($status) exit 1
		
		rm temp.nii.gz
		
		set norm = `fslstats ${patid}_CMRO2_on_T1${FinalResTrailer}.nii.gz -k ${target_path}/Masks/${target_patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz -M`
		if($status) exit 1
		
		fslmaths ${patid}_CMRO2_on_T1${FinalResTrailer}.nii.gz -div $norm ${patid}_OM_on_T1${FinalResTrailer}.nii.gz
		if($status) exit 1
popd

