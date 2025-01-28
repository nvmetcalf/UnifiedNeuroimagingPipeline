#!/bin/csh

set Params = $1
set ProcessingParameters = $2

source $Params

source $ProcessingParameters

if(! -e QC) mkdir QC

set SubjectHome = $cwd

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

#set the temporal mask folder
if($?FD_Threshold && $FD_Threshold != 0) then
	set FD_File = "'${SubjectHome}/Functional/Movement/${patid}_all_bold_runs.fd'"
else
	set FD_File = "[]"
endif

if($?DVAR_Threshold && $DVAR_Threshold != 0) then
	set DVAR_File = "'${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_resid.dvar'"
else
	set DVAR_File = "[]"
endif

if($target != "") then
	set AtlasName = `basename $target`
else
	set AtlasName = T1
endif

#goto NOISE

#do movement QC
if( $?RunIndex) then
	pushd ${SubjectHome}/Functional/Movement
		matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));DoMovementQC;end;exit"
		mv *.pdf ${SubjectHome}/QC
	popd
	
	if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
		set RunCondensedFormat = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_dvar.format`
		set RSCondensedFormat = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_bpss_resid_dvar.format`

	else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
		set RunCondensedFormat = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_fd.format`
		set RSCondensedFormat = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format`
	else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
		set RunCondensedFormat = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_dvar_fd.format`
		set RSCondensedFormat = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_bpss_resid_dvar_fd.format`
	else
		decho "Unknown combination of format criteria. No format Generated." ${DebugFile}
		exit 1
	endif
	
	$RELEASE/format2lst `echo $RunCondensedFormat` | awk -f $PP_SCRIPTS/frame_count.awk >! ${SubjectHome}/QC/${patid}_BOLD_frame_count.txt

	#compute how many frames we have remaining for each run we will be processing
	@ StartingFrame = 1
	@ EndingFrame = 1

	$RELEASE/format2lst `echo $RunCondensedFormat` >! temp_expanded.format

	echo "Run#\t#BadFrames\t#GoodFrames\t%Remaining\tSecondsRemaining" >! ${SubjectHome}/QC/${patid}_BOLD_frame_count_by_run.txt
	foreach Run($RunIndex)
		@ RunLength = `wc ${SubjectHome}/Functional/Movement/bold${Run}_upck_faln_dbnd_xr3d.ddat.fd | cut -d" " -f2`
		@ EndingFrame = $StartingFrame + $RunLength
		
		head -${EndingFrame} temp_expanded.format | tail -${RunLength} | awk -v TR=$BOLD_TR -f $PP_SCRIPTS/Utilities/frame_count.awk >! frame_count.tmp

		#report the thing...
		echo "${Run}	"`cat frame_count.tmp` >> ${SubjectHome}/QC/${patid}_BOLD_frame_count_by_run.txt

		#prepare for next run
		@ StartingFrame = $EndingFrame + 1
	end
	
	#extract rms movement
	ftouch ${SubjectHome}/QC/RMS_movements.txt
	@ i = 1
	while($i <= $#RunIndex)
		tail -1 ${SubjectHome}/Functional/Movement/bold${i}_upck_faln_dbnd_xr3d.ddat >> ${SubjectHome}/QC/RMS_movements.txt
		@ i++
	end
	
else
	echo "BOLD realignment not computed. Skipping movement plots."
endif

#Volume QC
$PP_SCRIPTS/QC/VolumeRegQC/ComputeVolumeRegQC.csh $Params $ProcessingParameters

#generate gray plots
if($?FCProcIndex && -e ${SubjectHome}/Anatomical/Surface/RibbonVolumeToSurfaceMapping/ribbon_only.nii.gz) then
	pushd QC
		matlab -nodesktop -softwareopengl -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));VolumeGrayPlotQC('$patid','${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt','${SubjectHome}/Functional/TemporalMask/run_boundaries_tmask.txt','${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz','${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz','${SubjectHome}/Anatomical/Surface/RibbonVolumeToSurfaceMapping/ribbon_only.nii.gz',${BOLD_TR},$FD_File,$DVAR_File);end;exit"
	popd
else if($?FCProcIndex && $?FC_Parcellation) then
	pushd QC
		matlab -nodesktop -softwareopengl -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));VolumeGrayPlotQC('$patid','${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt','${SubjectHome}/Functional/TemporalMask/run_boundaries_tmask.txt','${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz','${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz','${FC_Parcellation}',${BOLD_TR},$FD_File,$DVAR_File);end;exit"
	popd
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

#generate homotopic fc qc
#goto SKIP_LAG
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

if( $?FCProcIndex && -e ${SubjectHome}/Functional/Surface/${patid}_rsfMRI_uout_resid_bpss.ctx.dtseries.nii) then
	matlab -nodesktop -softwareopengl -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));HomotopicFC_surf( '${SubjectHome}/Functional/Surface/${patid}_rsfMRI_uout_resid_bpss.ctx.dtseries.nii' ,'${SubjectHome}/QC/${patid}_homotopic_fc.ctx.dtseries.nii', '${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt',$LeftMask,$RightMask);end;exit"
else if( $?FCProcIndex && -e ${SubjectHome}/Functional/Surface/${patid}_rsfMRI_sr_bpss.ctx.dtseries.nii) then
	matlab -nodesktop -softwareopengl -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));HomotopicFC_surf( '${SubjectHome}/Functional/Surface/${patid}_rsfMRI_sr_bpss.ctx.dtseries.nii' ,'${SubjectHome}/QC/${patid}_homotopic_fc.ctx.dtseries.nii', '${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt',$LeftMask,$RightMask);end;exit"
endif

#compute lag maps
#goto SKIP_LAG
if($?FCProcIndex && -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_resid_bpss.nii.gz) then
	pushd QC
		if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
			set format = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_dvar.format`

		else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
			set format = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format`
		else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
			set format = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_dvar_fd.format`
		else
			decho "Unknown combination of format criteria. No format Generated." ${DebugFile}
			exit 1
		endif

		pushd ${SubjectHome}/Functional/Regressors
			#paste ${patid}_Movement_regressors.dat ${patid}_Ventricle_regressors.dat ${patid}_EACSF_regressors.dat >! ${patid}_lag_regressors.dat
			paste ${patid}_Movement_regressors.dat ${patid}_Ventricle_regressors.dat >! ${patid}_lag_regressors.dat
			if($status) then
				decho "Could not make lag regressors! (EACSF, Venticle, Movement)" $DebugFile
				exit 1
			endif
		popd

		niftigz_4dfp -4 ${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz ${patid}_upck_faln_dbnd_xr3d_dc_atl
		if($status) exit 1

		glm_4dfp $format ${SubjectHome}/Functional/Regressors/${patid}_lag_regressors.dat ${patid}_upck_faln_dbnd_xr3d_dc_atl -rresid -o

		if ($status) then
			decho "Failed to perform linear regression of nuissance regressors!" $DebugFile
			exit $status
		endif

		decho "		Performing temporal bandpass filtering..." $DebugFile

		bandpass_4dfp ${patid}_upck_faln_dbnd_xr3d_dc_atl_resid $BOLD_TR -bl${LowFrequency} -bh${HighFrequency} -oh2 -E -f$format
		if ($status) then
			decho "			FAILED! bandpass_4dfp could not filter signal from ${concroot}_uout_resid_bpss.conc using a BOLD_TR of $BOLD_TR : $status" $DebugFile
			exit $status
		endif

		niftigz_4dfp -n ${patid}_upck_faln_dbnd_xr3d_dc_atl_resid_bpss ${patid}_upck_faln_dbnd_xr3d_dc_atl_resid_lag_bpss
		if($status) exit 1

		matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));MapLag_v2('${cwd}/${patid}_rsfMRI_resid_lag_bpss.nii.gz','${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt',${BOLD_TR},4,0);end;exit"

		rm -f ${patid}_upck_faln_dbnd_xr3d_dc_atl*
	popd
endif

SKIP_LAG:
pushd QC
	#project the SD to the surface
	$PP_SCRIPTS/Surface/volume_to_surface.csh ${SubjectHome}/Anatomical/Surface/RibbonVolumeToSurfaceMapping/std.nii.gz ${SubjectHome}/Anatomical/Surface/`basename ${target}`_${LowResMesh}k ${patid}_SD ${LowResMesh} enclosing midthickness
	$PP_SCRIPTS/Surface/volume_to_surface.csh ${SubjectHome}/Anatomical/Surface/RibbonVolumeToSurfaceMapping/cov.nii.gz ${SubjectHome}/Anatomical/Surface/`basename ${target}`_${LowResMesh}k ${patid}_CoV ${LowResMesh} enclosing midthickness
popd
NOISE:
pushd QC
	#compute the sd before and after denoising
	if(! -e $ScratchFolder/${patid}/BOLD_temp) mkdir -p $ScratchFolder/${patid}/BOLD_temp
	
	niftigz_4dfp -4 ${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl $ScratchFolder/${patid}/BOLD_temp/${patid}_upck_faln_dbnd_xr3d_dc_atl
	
	var_4dfp -sf`cat ../Functional/TemporalMask/${patid}_rsfMRI_fd.format` $ScratchFolder/${patid}/BOLD_temp/${patid}_upck_faln_dbnd_xr3d_dc_atl
	niftigz_4dfp -n $ScratchFolder/${patid}/BOLD_temp/${patid}_upck_faln_dbnd_xr3d_dc_atl_sd1 ${patid}_rsfMRI_sd
	
	niftigz_4dfp -4 ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss_resid
	
	var_4dfp -sf`cat ../Functional/TemporalMask/${patid}_rsfMRI_fd.format` $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss_resid
	niftigz_4dfp -n $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI_uout_bpss_resid_sd1 ${patid}_rsfMRI_uout_bpss_resid_sd
	
	niftigz_4dfp -4 ../Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz ${patid}_used_voxels_fnirt_${FinalResTrailer}
	ftouch fMRI_denoising.txt
	
	echo "Atlas Aligned resting state fMRI within brain sd: "`fslstats ${patid}_rsfMRI_sd -k ../Masks/${patid}_used_voxels_fnirt_${FinalResTrailer} -m` >> fMRI_denoising.txt
	echo "Denoised resting state fMRI within brain sd: "`fslstats ${patid}_rsfMRI_uout_bpss_resid_sd -k ../Masks/${patid}_used_voxels_fnirt_${FinalResTrailer} -m` >> fMRI_denoising.txt

	$PP_SCRIPTS/Utilities/Compute_SNR.csh ${patid}_rsfMRI.nii.gz
	
	rm ${patid}_used_voxels_fnirt_${FinalResTrailer}.*
popd

SCENES:
#create surface registration qc
$PP_SCRIPTS/QC/SurfRegQC/SurfRegQC.csh $patid $cwd `basename $target` $LowResMesh $MaskTrailer
echo `ls *.png`

#file cleanup
mv *.png QC/
mv *.jpg QC/

exit 0
