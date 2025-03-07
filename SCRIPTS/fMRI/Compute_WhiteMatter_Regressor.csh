#!/bin/csh

source $1
source $2

set concroot	= $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI
set conc	= $concroot.conc
set SubjectHome = $cwd

if (! ${?day1_patid}) set day1_patid = ""
if (! ${?day1_path}) set day1_path = ""

if($target != "") then
	set AtlasName = `basename $target`
else
	if($day1_path == "") then
		set AtlasName = ${patid}_T1
	else
		set AtlasName = ${day1_patid}_T1
	endif
endif

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"
@ nframe  = `wc ${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt | awk '{print $2}'`

if( ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz) then
	set DVAR_Threshold = 0
	decho "WARNING: Disabling DVAR threshold as denoised timeseries does not exist!"
endif

if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
	set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_dvar.format
else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
	set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format
else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
	set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_resid_dvar_fd.format
else
	decho "Unknown combination of format criteria. Iterative rsfMRI processing not possible." ${DebugFile}
	exit 1
endif

####################
# make WhiteMatter regressors
####################
pushd ${SubjectHome}/Masks/FreesurferMasks
	fslmaths ${patid}_WM_on_${AtlasName}_${FinalResTrailer} -ero ${SubjectHome}/Masks/FreesurferMasks/${patid}_WM_on_${AtlasName}_${FinalResTrailer}
	if($status) exit 1
	
	niftigz_4dfp -4 ${patid}_WM_on_${AtlasName}_${FinalResTrailer} temp
	if($status) exit 1
	
	cluster_4dfp temp -n100
	if($status) exit 1
	
	maskimg_4dfp temp_clus ${concroot}_dfnd ${patid}_WhiteMatter_mask
	if ($status) exit $status
	
	niftigz_4dfp -n ${patid}_WhiteMatter_mask ${patid}_WhiteMatter_mask
	if($status) exit 1
	
	rm temp*
popd

pushd ${SubjectHome}/Functional/Regressors
	@ n = `echo $WM_lcube | awk '{print int($1^3/2)}'`
	qntv_4dfp ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_WhiteMatter_mask -F$format -l$WM_lcube -t$WM_svdt -n$n -O4 -D -o${patid}_WhiteMatter_regressors.dat

	@ n = `wc ${patid}_WhiteMatter_regressors.dat | awk '{print $1}'`

	if ($status || $n != $nframe) then
		decho "Freesurfer generated white matter region failed, using minimal white matter region." $DebugFile
		pushd ${SubjectHome}/Masks/FreesurferMasks
			rm ${patid}_WhiteMatter_mask.4dfp.*
			niftigz_4dfp -4 ${target}_small_WM_${FinalResTrailer} small_WM_${FinalResTrailer}
			if($status) exit 1
			
			maskimg_4dfp small_WM_${FinalResTrailer} ${concroot}_dfnd ${patid}_WhiteMatter_mask
			if ($status) exit $status
		popd

		qntv_4dfp ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_WhiteMatter_mask -F$format -l$WM_lcube -t$WM_svdt -n1 -D -O4 -o${patid}_WhiteMatter_regressors.dat
		if($status) exit 1
	endif

	@ n = `wc ${patid}_WhiteMatter_regressors.dat | awk '{print $1}'`
	if ($n != $nframe) then
		decho "${patid}_mov_regressors.dat ${patid}_WhiteMatter_regressors.dat length mismatch" $DebugFile
		exit 1
	endif
popd

exit 0
