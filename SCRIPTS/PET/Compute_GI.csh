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

	if(! -e ${target_path}/Masks/${target_patid}_used_voxels_T1${FinalResTrailer}.nii.gz) then
		echo "Cannot compute OM as it seems freesurfer or compute sued voxel mask did not finish completely."
		exit 0
	endif

	echo "Computing GI..."

	pushd ${ScratchFolder}/${patid}/PET_temp
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_FDG_on_T1${FinalResTrailer}_norm ${cwd}/${patid}_FDG_on_T1${FinalResTrailer}_norm
		if($status) exit 1

		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_OM_on_T1${FinalResTrailer} ${cwd}/${patid}_OM_on_T1${FinalResTrailer}
		if($status) exit 1

		niftigz_4dfp -4 ${target_path}/Masks/${target_patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz ${cwd}/used_voxels
		if($status) exit 1

		gi_4dfp ${patid}_OM_on_T1${FinalResTrailer} ${patid}_FDG_on_T1${FinalResTrailer}_norm used_voxels ${patid}_GI_on_T1${FinalResTrailer} -n1 -g0.44
		if ($status) exit 1

		niftigz_4dfp -n ${patid}_GI_on_T1${FinalResTrailer} ${SubjectHome}/PET/Volume/${patid}_GI_on_T1${FinalResTrailer}
		if($status) exit 1

	popd
popd

