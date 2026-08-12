#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

set Residual_Trailer = ""
if(${ComputeMOVERegressor}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_mov`
	else
		set Residual_Trailer = "mov"
	endif
endif

if(${ComputeEACSFRegressor}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_eacsf`
	else
		set Residual_Trailer = "eacsf"
	endif
endif

if(${ComputeVENT}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_vent`
	else
		set Residual_Trailer = "vent"
	endif
endif

if(${ComputeWM}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_wm`
	else
		set Residual_Trailer = "wm"
	endif
endif

if(${ComputeWBRegressor}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_gs`
	else
		set Residual_Trailer = "gs"
	endif
endif

if($Residual_Trailer != "") then
	set Residual_Trailer = `echo ${Residual_Trailer}_resid`
else
	set Residual_Trailer = "resid"
endif

if( -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.R.${LowResMesh}k.func.gii && ! -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.R.${LowResMesh}k.func.gii) then
	set RightMask = "'${SubjectHome}/Masks/${patid}_${MaskTrailer}.R.${LowResMesh}k.func.gii'"
else if(-e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.R.${LowResMesh}k.func.gii && -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}_fnirt.R.${LowResMesh}k.func.gii) then
	set RightMask = "'${SubjectHome}/Masks/${patid}_${MaskTrailer}_fnirt.R.${LowResMesh}k.func.gii'"
else
	set RightMask = "[]"
endif

if( -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.L.${LowResMesh}k.func.gii && ! -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.L.${LowResMesh}k.func.gii) then
	set LeftMask = "'${SubjectHome}/Masks/${patid}_${MaskTrailer}.L.${LowResMesh}k.func.gii'"
else if(-e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.L.${LowResMesh}k.func.gii && -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}_fnirt.L.${LowResMesh}k.func.gii) then
	set LeftMask = "'${SubjectHome}/Masks/${patid}_${MaskTrailer}_fnirt.L.${LowResMesh}k.func.gii'"
else
	set LeftMask = "[]"
endif

if( $?FCProcIndex && -e ${SubjectHome}/Functional/Surface/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}.ctx.dtseries.nii) then
	matlab -nodesktop -softwareopengl -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));HomotopicFC_surf( '${SubjectHome}/Functional/Surface/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}.ctx.dtseries.nii' ,'${SubjectHome}/QC/${patid}_homotopic_fc.ctx.dtseries.nii', '${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt',$LeftMask,$RightMask);end;exit"
	
	if(! -e ${SubjectHome}/QC/${patid}_homotopic_fc.ctx.dtseries.nii) then
		exit 1
	endif
endif
