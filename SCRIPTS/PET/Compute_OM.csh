#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

pushd PET/Volume
	
	if(! -e ${patid}_O2_on_orig_norm.nii.gz || ! -e ${patid}_H2O_on_orig_norm.nii.gz || ! -e ${patid}_CO_on_orig_norm.nii.gz) then
		echo "Cannot compute OM(CMRO2) as one or more of the following are missing: O2, H2O, CO"
		exit 0
	endif
	
	if(! -e ${SubjectHome}/Masks/FreesurferMasks/aparc+aseg_bin.nii.gz) then
		echo "Cannot compute OM as it seems freesurfer or compute sued voxel mask did not finish completely."
		exit 0
	endif
	
	echo "Computing OM..."
	pushd ${ScratchFolder}/${patid}/PET_temp
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_O2_on_orig_norm.nii.gz ${cwd}/${patid}_O2_on_orig_norm
		if($status) exit 1
		
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_H2O_on_orig_norm.nii.gz ${cwd}/${patid}_H2O_on_orig_norm
		if($status) exit 1
		
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_CO_on_orig_norm.nii.gz ${cwd}/${patid}_CO_on_orig_norm
		if($status) exit 1
		
		niftigz_4dfp -4 ${SubjectHome}/Masks/FreesurferMasks/aparc+aseg_bin.nii.gz ${cwd}/orig_used_voxels
		if($status) exit 1
		
		oem_4dfp ${patid}_O2_on_orig_norm ${patid}_H2O_on_orig_norm ${patid}_CO_on_orig_norm orig_used_voxels ${patid}_OM_on_orig ${patid}_OE_on_orig -n1 -g0.44
		if ($status) exit 1
		
		niftigz_4dfp -n ${patid}_OM_on_orig ${patid}_OM_on_orig
		if($status) exit 1
		
		mv ${patid}_OM_on_orig.nii.gz ${SubjectHome}/PET/Volume/
	popd
popd

