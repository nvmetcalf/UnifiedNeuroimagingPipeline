#!/bin/csh

if($#argv < 2) then
	echo "surface_projection_pipeline <Subject.params> <ProcessingParemeters.params>"
	exit 1
endif

setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

set SubjectHome = $cwd #Path to patients folder

setenv FSOUT ""

source $1
source $2

if (! -e $1) then
	echo "$1 not found!"
	exit 1
endif

if (! -e $2) then
	echo "$2 not found!"
	exit 1
endif

if(! $?UseCurrentSurfs) then
	set UseCurrentSurfs = 0
endif

if($target != "") then
	set AtlasName = `basename $target`
else
	set AtlasName = T1
endif
#Create and register surfaces unless the user wants to use what
#has already been created
if(! $UseCurrentSurfs) then
	$PP_SCRIPTS/Surface/Generate_Surfaces.csh $1 $2
	if($status) exit 1
endif
	
RIBBON_MAPPING:
$PP_SCRIPTS/Surface/CorticalRibbonMapping.csh $1 $2
if($status) exit 1

SURF_BOLD:	
$PP_SCRIPTS/Surface/Sample_rsfMRI_to_cifti.csh $1 $2
if($status) exit 1

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
