#!/bin/csh

source $1
source $2

#take the results from the pipeline and put them into a data structure in matlab
#want the temporal mask
#pre bandpassed data
#post bandpassed data
#seed correlation matrix using some parcellation (GL324)
#surface masj used
#midthickness surface

set RegionsToUse = "$PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered_w_SubCortical.32k.dlabel.nii"

if(-e Masks/${patid}_${MaskTrailer}_fnirt.L.${LowResMesh}k.func.gii) then
	set SurfaceMask_LeftHemisphere = "'Masks/${patid}_${MaskTrailer}_fnirt.L.${LowResMesh}k.func.gii'"
else
	set SurfaceMask_LeftHemisphere = "[]"
endif

if(-e Masks/${patid}_${MaskTrailer}_fnirt.R.${LowResMesh}k.func.gii) then
	set SurfaceMask_RightHemisphere = "'Masks/${patid}_${MaskTrailer}_fnirt.R.${LowResMesh}k.func.gii'"
else
	set SurfaceMask_RightHemisphere = "[]"
endif

set OutputFolder = "../../Analysis/Results"

set SubjectID = $patid

set FCMapsFolder = ${cwd}/Functional

set AtlasName = `basename $target`

matlab -nodesktop -nosplash -r "addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));RunResults('$OutputFolder', '$SubjectID', '$FCMapsFolder', $SurfaceMask_LeftHemisphere, $SurfaceMask_RightHemisphere, {'$RegionsToUse'},'$AtlasName','$LowResMesh');exit;"
