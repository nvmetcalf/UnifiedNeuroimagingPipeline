#!/bin/csh

source $1
source $2

set SubjectHome = $cwd
if(! -e ${SubjectHome}/Masks/FreesurferMasks/aparc+aseg_bin.nii.gz) then
	echo "Cannot find registration from T1 to Orig in Masks/FreesurferMasks."
	exit 1
endif

echo "Computing and applying normalization to PET"

pushd PET/Volume

	set modes_available = ()
		
	if($?FDG && -e ${patid}_FDG_on_orig.nii.gz) then
		set modes_available = ($modes_available FDG)
	endif
		
	if($?O2 && -e ${patid}_O2_on_orig.nii.gz) then
		set modes_available = ($modes_available O2)
	endif
		
	if($?CO && -e ${patid}_CO_on_orig.nii.gz) then
		set modes_available = ($modes_available CO)
	endif
		
	if($?H2O && -e ${patid}_H2O_on_orig.nii.gz) then
		set modes_available = ($modes_available H2O)
	endif
	
	if($?PIB && -e ${patid}_PIB_on_orig.nii.gz) then
		set modes_available = ($modes_available PIB)
	endif
	
	if($?TAU && -e ${patid}_TAU_on_orig.nii.gz) then
		set modes_available = ($modes_available TAU)
	endif
	
	if($?FBX && -e ${patid}_FBX_on_orig.nii.gz) then
		set modes_available = ($modes_available FBX)
	endif
	
	foreach mode ($modes_available)
		set norm = `fslstats ${patid}_${mode}_on_orig -k ${SubjectHome}/Masks/FreesurferMasks/aparc+aseg_bin.nii.gz -M`
		if ($status) exit $status
		
		fslmaths ${patid}_${mode}_on_orig -div $norm ${patid}_${mode}_on_orig_norm
		if ($status) exit $status
	end
popd
