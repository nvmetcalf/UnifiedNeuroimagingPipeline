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

pushd ${SubjectHome}/PET/Volume
	if(! -e ${SubjectHome}/PET/Volume/${patid}_O2_on_T1${FinalResTrailer}_norm.nii.gz || ! -e ${SubjectHome}/PET/Volume/${patid}_H2O_on_T1${FinalResTrailer}_norm.nii.gz || ! -e ${SubjectHome}/PET/Volume/${patid}_CO_on_T1${FinalResTrailer}_norm.nii.gz || ! -e ${target_path}/Masks/${target_patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz) then
		echo "Cannot compute OEF and CMRO2 as O2, H2O, CO, or mask do not exist."
		exit 0
	endif

# Vaishnavi SN, Herscovitch P, Mintun MA, Raichle ME. Regional aerobic glycolysis in the human brain. Proc Natl Acad Sci U S A. 2010;107(41):17757-17762

# 	trio2oem_4dfp is to create OEF and CMRO2 images based on the model
#               [OO]  := m1[HO] + m2[OC];
#               OEF   := ([OO]-m2[OC])/(m1[HO]/0.4);
#               CMRO2 := [OO] - m2[OC];
#               where [OO] := oxygen
#                     [OH] := water
#                     [OC] := carbon monoxide


	python3 $PP_SCRIPTS/python3/compute_CMRO2_OEF.py ${patid}_O2_on_T1${FinalResTrailer}_norm.nii.gz ${patid}_H2O_on_T1${FinalResTrailer}_norm.nii.gz ${patid}_CO_on_T1${FinalResTrailer}_norm.nii.gz ${SubjectHome}/Masks/${patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz ${patid}_CMRO2_on_T1${FinalResTrailer}.nii.gz ${patid}_OEF_on_T1${FinalResTrailer}.nii.gz
	if ($status) exit $status
popd
exit 0
