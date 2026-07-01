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
	pushd ${ScratchFolder}/${patid}/PET_temp
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_O2_on_T1${FinalResTrailer}_norm.nii.gz ${cwd}/${patid}_O2_on_T1${FinalResTrailer}_norm
		if($status) exit 1

		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_H2O_on_T1${FinalResTrailer}_norm.nii.gz ${cwd}/${patid}_H2O_on_T1${FinalResTrailer}_norm
		if($status) exit 1

		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_CO_on_T1${FinalResTrailer}_norm.nii.gz ${cwd}/${patid}_CO_on_T1${FinalResTrailer}_norm
		if($status) exit 1

		niftigz_4dfp -4 ${SubjectHome}/Masks/${patid}_used_voxels_T1${FinalResTrailer}_PET.nii.gz used_voxels
		if($status) exit 1

		#recompute OM, but no smoothing on the CO after applying the coefficient before subtracting the the O2
		set Coeffs = `trio2oem_4dfp ${patid}_O2_on_T1${FinalResTrailer}_norm ${patid}_H2O_on_T1${FinalResTrailer}_norm ${patid}_CO_on_T1${FinalResTrailer}_norm used_voxels OM_temp OE_temp -u | gawk '$1=="m1" {print $NF; getline; print $NF}'`
		ftouch OM_CMRO2_OEF_Coeffs.csv
		
		echo "M1,$Coeffs[1]" >> OM_CMRO2_OEF_Coeffs.csv
		echo "M2,$Coeffs[2]" >> OM_CMRO2_OEF_Coeffs.csv
		
		oem_4dfp ${patid}_O2_on_T1${FinalResTrailer}_norm ${patid}_H2O_on_T1${FinalResTrailer}_norm ${patid}_CO_on_T1${FinalResTrailer}_norm used_voxels ${patid}_OM_on_T1${FinalResTrailer} OE_temp -n1 # -g0.44
		if ($status) exit 1
				
		rm *_temp.*
		
		niftigz_4dfp -n ${patid}_OM_on_T1${FinalResTrailer} ${patid}_OM_on_T1${FinalResTrailer}
		if($status) exit 1

		mv ${patid}_OM_on_T1${FinalResTrailer}.nii.gz ${SubjectHome}/PET/Volume/
	popd
popd

