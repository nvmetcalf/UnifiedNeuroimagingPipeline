#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

pushd PET/Volume
	
	if(! -e ${patid}_FDG_on_orig_norm.nii.gz || ! -e ${patid}_OM_on_orig.nii.gz) then
		echo "Cannot comput GI as FDG and or OM do not exist."
		exit 0
	endif
	
	if(! -e ${SubjectHome}/Masks/FreesurferMasks/aparc+aseg_bin.nii.gz) then
		echo "Cannot compute OM as it seems freesurfer or compute sued voxel mask did not finish completely."
		exit 0
	endif
	
	echo "Computing GI..."
	
	pushd ${ScratchFolder}/${patid}/PET_temp
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_FDG_on_orig_norm ${cwd}/${patid}_FDG_on_orig_norm
		if($status) exit 1
		
		niftigz_4dfp -4 ${SubjectHome}/PET/Volume/${patid}_OM_on_orig ${cwd}/${patid}_OM_on_orig
		if($status) exit 1
		
		niftigz_4dfp -4 ${SubjectHome}/Masks/FreesurferMasks/aparc+aseg_bin.nii.gz ${cwd}/orig_used_voxels
		if($status) exit 1
		
		gi_4dfp ${patid}_OM_on_orig ${patid}_FDG_on_orig_norm orig_used_voxels ${patid}_GI_on_orig -n1 -g0.44
		if ($status) exit 1
		
		niftigz_4dfp -n ${patid}_GI_on_orig ${SubjectHome}/PET/Volume/${patid}_GI_on_orig
		if($status) exit 1
		
	popd
popd

