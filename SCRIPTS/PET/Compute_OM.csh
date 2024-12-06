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
	
	if(! -e ${patid}_O2_on_T1_norm.nii.gz || ! -e ${patid}_H2O_on_T1_norm.nii.gz || ! -e ${patid}_CO_on_T1_norm.nii.gz) then
		echo "Cannot compute OM as one or more of the following are missing: O2, H2O, CO"
		exit 0
	endif
	
	if(! -e ${target_path}/Masks/${target_patid}_used_voxels_T1.nii.gz) then
		echo "Cannot compute OM as it seems freesurfer or compute sued voxel mask did not finish completely."
		exit 0
	endif
	
	echo "Computing OM..."
	pushd ${ScratchFolder}/${patid}/PET_temp
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_O2_on_T1_norm.nii.gz ${cwd}/${patid}_O2_on_T1_norm
		if($status) exit 1
		
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_H2O_on_T1_norm.nii.gz ${cwd}/${patid}_H2O_on_T1_norm
		if($status) exit 1
		
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_CO_on_T1_norm.nii.gz ${cwd}/${patid}_CO_on_T1_norm
		if($status) exit 1
		
		niftigz_4dfp -4 ${target_path}/Masks/${target_patid}_used_voxels_T1.nii.gz used_voxels
		if($status) exit 1
		
		oem_4dfp ${patid}_O2_on_T1_norm ${patid}_H2O_on_T1_norm ${patid}_CO_on_T1_norm used_voxels ${patid}_OM_on_T1 ${patid}_OE_on_T1 -n1 -g0.44
		if ($status) exit 1
		
		niftigz_4dfp -n ${patid}_OM_on_T1 ${patid}_OM_on_T1
		if($status) exit 1
		
		niftigz_4dfp -n ${patid}_OE_on_T1 ${patid}_OE_on_T1
		if($status) exit 1
		
		mv ${patid}_OM_on_T1.nii.gz ${SubjectHome}/PET/Volume/
	popd
popd

