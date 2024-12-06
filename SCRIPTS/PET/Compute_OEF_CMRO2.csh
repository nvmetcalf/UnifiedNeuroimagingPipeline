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

pushd ${ScratchFolder}/${patid}/PET_temp
	
	if(! -e ${SubjectHome}/PET/Volume/${patid}_O2_on_T1_norm.nii.gz || ! -e ${SubjectHome}/PET/Volume/${patid}_H2O_on_T1_norm.nii.gz || ! -e ${SubjectHome}/PET/Volume/${patid}_CO_on_T1_norm.nii.gz || ! -e ${target_path}/Masks/${target_patid}_used_voxels_T1.nii.gz) then
		echo "Cannot compute OEF and CMRO2 as O2, H2O, CO, or mask do not exist."
		exit 0
	endif
	
	niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_O2_on_T1_norm ${patid}_O2_on_T1_norm
	if($status) exit 1
	
	niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_H2O_on_T1_norm ${patid}_H2O_on_T1_norm
	if($status) exit 1
	
	niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_CO_on_T1_norm ${patid}_CO_on_T1_norm
	if($status) exit 1
	
	niftigz_4dfp -4 ${target_path}/Masks/${target_patid}_used_voxels_T1.nii.gz used_voxels_T1
	if($status) exit 1
	
	trio2oem_4dfp ${patid}_O2_on_T1_norm ${patid}_H2O_on_T1_norm ${patid}_CO_on_T1_norm used_voxels_T1 ${patid}_CMRO2_on_T1 ${patid}_OEF_on_T1 -u
	if ($status) exit $status
	
	niftigz_4dfp -n ${patid}_CMRO2_on_T1 ${patid}_CMRO2_on_T1
	if($status) exit 1
	
	niftigz_4dfp -n ${patid}_OEF_on_T1 ${patid}_OEF_on_T1
	if ($status) exit $status
	
	mv ${patid}_CMRO2_on_T1.nii.gz ${patid}_OEF_on_T1.nii.gz ${SubjectHome}/PET/Volume/
popd
