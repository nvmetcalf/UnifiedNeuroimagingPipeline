#!/bin/csh

if($#argv < 2) then
	echo "surface_projection_pipeline <Subject.params> <ProcessingParemeters.params>"
	exit 1
endif

setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

set SubjectHome = $cwd #Path to patients folder

setenv FSOUT ""

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

if(! $?UseCurrentSurfs) then
	set UseCurrentSurfs = 0
endif

if($target != "") then
	set AtlasName = $target:t
else
	set AtlasName = T1
endif
#Create and register surfaces unless the user wants to use what
#has already been created
if(! $UseCurrentSurfs) then
	$PP_SCRIPTS/Surface/Generate_Surfaces.csh $1 $2
	if($status) then
		echo "SCRIPT: $0 : 00003 : failed to generate surfaces."
		exit 1
	endif
endif

RIBBON_MAPPING:
$PP_SCRIPTS/Surface/CorticalRibbonMapping.csh $1 $2
if($status) then
	echo "SCRIPT: $0 : 00004 : failed to generate cortical ribbon."
	exit 1
endif

SURF_BOLD:
$PP_SCRIPTS/Surface/Sample_rsfMRI_to_cifti.csh $1 $2
if($status) then
	echo "SCRIPT: $0 : 00005 : failed to sample resting state to the surface."
	exit 1
endif

#project the mask in the masks folder

pushd Masks
	if($NonLinear && -e ${patid}_${MaskTrailer}_fnirt.nii.gz) then
		$PP_SCRIPTS/Surface/volume_to_surface.csh ${patid}_${MaskTrailer}_fnirt.nii.gz ${SubjectHome}/Anatomical/Surface/${AtlasName}_${LowResMesh}k ${patid}_${MaskTrailer}_fnirt ${LowResMesh}
	else if( -e ${patid}_${MaskTrailer}.nii.gz) then
		$PP_SCRIPTS/Surface/volume_to_surface.csh ${patid}_${MaskTrailer}.nii.gz ${SubjectHome}/Anatomical/Surface/${AtlasName}_${LowResMesh}k ${patid}_${MaskTrailer} ${LowResMesh}
	endif
popd

#compute and project Myelin
$PP_SCRIPTS/HCP/PostFreeSurfer/scripts/CreateMyelinMaps_v3.csh $1 $2

exit 0
