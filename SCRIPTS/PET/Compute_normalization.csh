#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

if($?day1_path) then
	set target = $day1_path:t
	set target_path = $day1_path
	set target_patid = $day1_path:t
else
	set target = $patid
	set target_path = $SubjectHome
	set target_patid = $patid
endif

if(! -e ${target_path}/Masks/FreesurferMasks/aparc+aseg_bin.nii.gz) then
	echo "Cannot find registration from T1 to Orig in Masks/FreesurferMasks."
	exit 1
endif

if($PET_FinalResolution == 0) then
	set FinalResTrailer = ""
else
	set FinalResTrailer = _${PET_FinalResolution}${PET_FinalResolution}${PET_FinalResolution}
endif

echo "Computing and applying normalization to PET"

pushd PET/Volume

	set modes_available = ()

	if($?FDG && -e ${SubjectHome}/Anatomical/Volume/FDG/${patid}_FDG_to_${target_patid}_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available FDG)
	endif

	if($?O2 && -e ${SubjectHome}/Anatomical/Volume/O2/${patid}_O2_to_${target_patid}_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available O2)
	endif

	if($?CO && -e ${SubjectHome}/Anatomical/Volume/CO/${patid}_CO_to_${target_patid}_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available CO)
	endif

	if($?H2O && -e ${SubjectHome}/Anatomical/Volume/H2O/${patid}_H2O_to_${target_patid}_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available H2O)
	endif

	if($?PIB && -e ${SubjectHome}/Anatomical/Volume/PIB/${patid}_PIB_to_${target_patid}_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available PIB)
	endif

	if($?TAU && -e ${SubjectHome}/Anatomical/Volume/TAU/${patid}_TAU_to_${target_patid}_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available TAU)
	endif

	if($?FBX && -e ${SubjectHome}/Anatomical/Volume/FBX/${patid}_FBX_to_${target_patid}_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available FBX)
	endif

	foreach mode ($modes_available)
		set norm = `fslstats ${SubjectHome}/Anatomical/Volume/${mode}/${patid}_${mode}_to_${target_patid}_T1${FinalResTrailer} -k ${target_path}/Masks/${target_patid}_used_voxels_T1${FinalResTrailer}.nii.gz -M`
		if ($status) exit $status

		fslmaths ${SubjectHome}/Anatomical/Volume/${mode}/${patid}_${mode}_to_${target_patid}_T1${FinalResTrailer} -div $norm ${patid}_${mode}_on_T1${FinalResTrailer}_norm
		if ($status) exit $status

		if($?PET_Smoothing) then
			set SmoothingSigma = `echo $PET_Smoothing | awk '{print($1/2.3548);}'`

			if(-e ${patid}_${mode}_on_T1${FinalResTrailer}_norm_nosm.nii.gz) then
				cp ${patid}_${mode}_on_T1${FinalResTrailer}_norm_nosm.nii.gz ${patid}_${mode}_on_T1${FinalResTrailer}_norm.nii.gz
			endif

			if(! -e ${patid}_${mode}_on_T1${FinalResTrailer}_norm_nosm.nii.gz) then
				cp ${patid}_${mode}_on_T1${FinalResTrailer}_norm.nii.gz ${patid}_${mode}_on_T1${FinalResTrailer}_norm_nosm.nii.gz
			endif

			fslmaths ${patid}_${mode}_on_T1${FinalResTrailer}_norm -kernel gauss $SmoothingSigma -fmean ${patid}_${mode}_on_T1${FinalResTrailer}_norm
			if($status) exit 1
		endif
	end
popd
