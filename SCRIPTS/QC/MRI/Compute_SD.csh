#!/bin/csh

source $1
source $2

set SubjectHome = $cwd
set Residual_Trailer = ""

set FinalResolution = $BOLD_FinalResolution
set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if($target == "") then
	set AtlasName = T1
else
	set Atlasname = $target:t
endif

if($NonLinear) then
	set reg_trailer = "${reg_trailer}"
else
	set reg_trailer = ""
endif

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

pushd QC
	#compute the sd before and after denoising
	if(! -e $ScratchFolder/${patid}/BOLD_temp) mkdir -p $ScratchFolder/${patid}/BOLD_temp

	niftigz_4dfp -4 ${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl $ScratchFolder/${patid}/BOLD_temp/${patid}_upck_faln_dbnd_xr3d_dc_atl
	if($status) exit 1
	
	var_4dfp -sf`cat ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_combined.format` $ScratchFolder/${patid}/BOLD_temp/${patid}_upck_faln_dbnd_xr3d_dc_atl
	niftigz_4dfp -n $ScratchFolder/${patid}/BOLD_temp/${patid}_upck_faln_dbnd_xr3d_dc_atl_sd1 ${patid}_pre-denoising_SD
	if($status) exit 1
	
	niftigz_4dfp -4 ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss.nii.gz $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss
	if($status) exit 1
	
	var_4dfp -sf`cat ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_combined.format` $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss
	if($status) exit 1
	
	niftigz_4dfp -n $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss_sd1 ${patid}_post-bpss_SD
	if($status) exit 1
	
	niftigz_4dfp -4 ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}.nii.gz $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}
	if($status) exit 1
	
	var_4dfp -sf`cat ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_combined.format` $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}
	if($status) exit 1
	
	echo $cwd
	niftigz_4dfp -n $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}_sd1 ${patid}_post-denoising_SD
	if($status) exit 1
	
	niftigz_4dfp -4 ${SubjectHome}/Masks/${patid}_used_voxels${reg_trailer}_${FinalResTrailer}.nii.gz ${patid}_used_voxels${reg_trailer}_${FinalResTrailer}
	if($status) exit 1
	
	ftouch fMRI_denoising.txt

	echo "Atlas Aligned resting state fMRI within brain sd: "`fslstats ${patid}_pre-denoising_SD.nii.gz -k ${SubjectHome}/Masks/${patid}_used_voxels${reg_trailer}_${FinalResTrailer} -M` >> fMRI_denoising.txt
	echo "Denoised resting state fMRI within brain sd: "`fslstats ${patid}_post-denoising_SD.nii.gz -k ../Masks/${patid}_used_voxels${reg_trailer}_${FinalResTrailer} -M` >> fMRI_denoising.txt

	$PP_SCRIPTS/Utilities/Compute_SNR.csh ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}.nii.gz
	if($status) exit 1

	rm ${patid}_used_voxels${reg_trailer}_${FinalResTrailer}.*
popd

pushd QC
	#project the SD to the surface
	$PP_SCRIPTS/Surface/volume_to_surface.csh ${patid}_post-denoising_SD.nii.gz ${SubjectHome}/Anatomical/Surface/${AtlasName}"_${LowResMesh}k" ${patid}_SD ${LowResMesh} enclosing midthickness
	$PP_SCRIPTS/Surface/volume_to_surface.csh ${SubjectHome}/Anatomical/Surface/RibbonVolumeToSurfaceMapping/cov.nii.gz ${SubjectHome}/Anatomical/Surface/${AtlasName}"_${LowResMesh}k" ${patid}_CoV ${LowResMesh} enclosing midthickness
popd
