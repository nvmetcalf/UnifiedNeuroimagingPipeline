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

if(! -e ${target_path}/Masks/FreesurferMasks/aparc+aseg_bin.nii.gz) then
	echo "Cannot find registration from T1 to Orig in Masks/FreesurferMasks."
	exit 1
endif

echo "Computing and applying normalization to PET"

pushd PET/Volume

	set modes_available = ()
		
	if($?FDG && -e ${SubjectHome}/Anatomical/Volume/FDG/${patid}_FDG_to_${target_patid}_T1.nii.gz) then
		set modes_available = ($modes_available FDG)
	endif
		
	if($?O2 && -e ${SubjectHome}/Anatomical/Volume/O2/${patid}_O2_to_${target_patid}_T1.nii.gz) then
		set modes_available = ($modes_available O2)
	endif
		
	if($?CO && -e ${SubjectHome}/Anatomical/Volume/CO/${patid}_CO_to_${target_patid}_T1.nii.gz) then
		set modes_available = ($modes_available CO)
	endif
		
	if($?H2O && -e ${SubjectHome}/Anatomical/Volume/H2O/${patid}_H2O_to_${target_patid}_T1.nii.gz) then
		set modes_available = ($modes_available H2O)
	endif
	
	if($?PIB && -e ${SubjectHome}/Anatomical/Volume/PIB/${patid}_PIB_to_${target_patid}_T1.nii.gz) then
		set modes_available = ($modes_available PIB)
	endif
	
	if($?TAU && -e ${SubjectHome}/Anatomical/Volume/TAU/${patid}_TAU_to_${target_patid}_T1.nii.gz) then
		set modes_available = ($modes_available TAU)
	endif
	
	if($?FBX && -e ${SubjectHome}/Anatomical/Volume/FBX/${patid}_FBX_to_${target_patid}_T1.nii.gz) then
		set modes_available = ($modes_available FBX)
	endif
	
	foreach mode ($modes_available)
		set norm = `fslstats ${SubjectHome}/Anatomical/Volume/${mode}/${patid}_${mode}_to_${target_patid}_T1 -k ${target_path}/Masks/${target_patid}_used_voxels_T1.nii.gz -M`
		if ($status) exit $status
		
		fslmaths ${SubjectHome}/Anatomical/Volume/${mode}/${patid}_${mode}_to_${target_patid}_T1 -div $norm ${patid}_${mode}_on_T1_norm
		if ($status) exit $status
	end
popd
