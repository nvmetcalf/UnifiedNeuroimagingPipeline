#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

if($?day1_patid) then
	set target = $day1_patid
	set target_path = $day1_path
	set target_patid = $day1_patid
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

	if(! -e ${patid}_FDG_on_T1${FinalResTrailer}_norm.nii.gz || ! -e ${patid}_OM_on_T1${FinalResTrailer}.nii.gz || ! -e ${SubjectHome}/Masks/${patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz) then
		echo "Cannot compute GI as FDG and or OM or the mask do not exist."
		exit 0
	endif

	echo "Computing GI..."

		#gi_4dfp ${patid}_CMRO2_on_T1${FinalResTrailer} ${patid}_FDG_on_T1${FinalResTrailer}_norm used_voxels ${patid}_GI_on_T1${FinalResTrailer} -n1
		python3 $PP_SCRIPTS/python3/compute_residual.py ${patid}_CMRO2_on_T1${FinalResTrailer}.nii.gz ${patid}_FDG_on_T1${FinalResTrailer}_norm.nii.gz ${patid}_GI_on_T1${FinalResTrailer}.nii.gz -m ${target_path}/Masks/${target_patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz -n 1 --stdout-file GI_parameters.txt
		if ($status) exit 1
		
		#maybe do FDG - (CMRO2/6). FDG needs to be converted to CMRglu... which we can't do...
		
popd

