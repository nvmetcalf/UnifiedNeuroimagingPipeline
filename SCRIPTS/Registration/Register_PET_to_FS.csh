#!/bin/csh

if($#argv != 2) then
	echo "SCRIPT: $0 : 00000 : incorrect number of arguments"
	exit 1
endif

if(! -e $1) then
	echo "SCRIPT: $0 : 00001 : $1 does not exist"
	exit 1
endif

if(! -e $2) then
	echo "SCRIPT: $0 : 00002 : $2 does not exist"
	exit 1
endif

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

if(! -e ${target_path}/Masks/FreesurferMasks/${target_patid}_T1${FinalResTrailer}_to_${target_patid}_orig.mat && ! -e ${target_path}/Masks/FreesurferMasks/${target_patid}_orig_to_${target_patid}_T1${FinalResTrailer}.mat) then
	echo "Cannot find registration from T1 to Orig in Masks/FreesurferMasks."
	echo "Computing UsedVoxels Masks and transforms..."
	$PP_SCRIPTS/Utilities/Generate_UsedVoxels_Masks.csh $1 $2
	if($status) exit 1

else if(! -e ${target_path}/Masks/FreesurferMasks/${target_patid}_T1${FinalResTrailer}_to_${target_patid}_orig.mat && -e ${target_path}/Masks/FreesurferMasks/${target_patid}_orig_to_${target_patid}_T1${FinalResTrailer}.mat) then
	echo "Inverting orig to T1 matrix."

	convert_xfm -omat ${target_path}/Masks/FreesurferMasks/${target_patid}_T1${FinalResTrailer}_to_${target_patid}_orig.mat -inverse ${target_path}/Masks/FreesurferMasks/${target_patid}_orig_to_${target_patid}_T1${FinalResTrailer}.mat
	if($status) exit 1
endif

set modes_available = ()

pushd PET/Volume
	echo "Registering PET modalities to freesurfer..."

	if(-e ${patid}_FDG_on_T1${FinalResTrailer}_norm.nii.gz) then
		set modes_available = ($modes_available FDG)
	endif

	if(-e ${patid}_H2O_on_T1${FinalResTrailer}_norm.nii.gz) then
		set modes_available = ($modes_available H2O)
	endif

	if(-e ${patid}_O2_on_T1${FinalResTrailer}_norm.nii.gz) then
		set modes_available = ($modes_available O2)
	endif

	if(-e ${patid}_CO_on_T1${FinalResTrailer}_norm.nii.gz) then
		set modes_available = ($modes_available CO)
	endif

	if(-e ${patid}_OM_on_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available OM)
	endif

	if(-e ${patid}_GI_on_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available GI)
	endif

	if(-e ${patid}_OEF_on_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available OEF)
	endif

	if(-e ${patid}_CMRO2_on_T1${FinalResTrailer}.nii.gz) then
		set modes_available = ($modes_available CMRO2)
	endif

	if(-e ${patid}_PIB_on_T1${FinalResTrailer}_norm.nii.gz) then
		set modes_available = ($modes_available PIB)
	endif

	if(-e ${patid}_TAU_on_T1${FinalResTrailer}_norm.nii.gz) then
		set modes_available = ($modes_available TAU)
	endif

	if(-e ${patid}_FBX_on_T1${FinalResTrailer}_norm.nii.gz) then
		set modes_available = ($modes_available FBX)
	endif

	foreach mode($modes_available)
		flirt -in ${patid}_${mode}_on_T1${FinalResTrailer}*.nii.gz -ref ${target_path}/Masks/FreesurferMasks/${target_patid}_orig -out ${patid}_${mode}_on_orig -init ${target_path}/Masks/FreesurferMasks/${target_patid}_T1${FinalResTrailer}_to_${target_patid}_orig.mat -applyxfm
		if($status) exit 1
	end
popd
