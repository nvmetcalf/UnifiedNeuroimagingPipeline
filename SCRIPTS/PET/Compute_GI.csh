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

pushd PET/Volume
	
	if(! -e ${patid}_FDG_on_T1_norm.nii.gz || ! -e ${patid}_OM_on_T1.nii.gz) then
		echo "Cannot comput GI as FDG and or OM do not exist."
		exit 0
	endif
	
	if(! -e ${target_path}/Masks/${target_patid}_used_voxels_T1.nii.gz) then
		echo "Cannot compute OM as it seems freesurfer or compute sued voxel mask did not finish completely."
		exit 0
	endif
	
	echo "Computing GI..."
	
	pushd ${ScratchFolder}/${patid}/PET_temp
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_FDG_on_T1_norm ${cwd}/${patid}_FDG_on_T1_norm
		if($status) exit 1
		
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_OM_on_T1 ${cwd}/${patid}_OM_on_T1
		if($status) exit 1
		
		niftigz_4dfp -4 ${target_path}/Masks/${target_patid}_used_voxels_T1.nii.gz ${cwd}/used_voxels
		if($status) exit 1
		
		gi_4dfp ${patid}_OM_on_T1 ${patid}_FDG_on_T1_norm used_voxels ${patid}_GI_on_T1 -n1 -g0.44
		if ($status) exit 1
		
		niftigz_4dfp -n ${patid}_GI_on_T1 ${SubjectHome}/PET/Volume/${patid}_GI_on_T1
		if($status) exit 1
		
	popd
popd

