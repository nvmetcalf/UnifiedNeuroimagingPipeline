#!/bin/csh

source $1
source $2
set SubjectHome = $cwd

if($target == "") then
	set AtlasName = T1
else
	set Atlasname = $target:t
endif
#generate TSNR map for the BOLD
pushd ${SubjectHome}/QC
	if(-e ${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz) then
		fslmaths ${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz -Tmean ${SubjectHome}/QC/tmean
		if($status) exit 1

		fslmaths ${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz -Tstd ${SubjectHome}/QC/tstd
		if($status) exit 1

		fslmaths ${SubjectHome}/QC/tmean -div ${SubjectHome}/QC/tstd ${SubjectHome}/QC/tSNR
		if($status) exit 1

		if($NonLinear && -e ${SubjectHome}/Anatomical/Surface/${AtlasName}_${LowResMesh}k) then
			$PP_SCRIPTS/Surface/volume_to_surface.csh tSNR.nii.gz ${SubjectHome}/Anatomical/Surface/${AtlasName}_${LowResMesh}k tSNR_fnirt ${LowResMesh} enclosing midthickness
		else if( -e ${SubjectHome}/Anatomical/Surface/${AtlasName}_${LowResMesh}k) then
			$PP_SCRIPTS/Surface/volume_to_surface.csh tSNR.nii.gz ${SubjectHome}/Anatomical/Surface/${AtlasName}_${LowResMesh}k tSNR ${LowResMesh} enclosing midthickness
		endif
	endif
popd
