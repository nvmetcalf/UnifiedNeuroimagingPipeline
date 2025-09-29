#!/bin/csh

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

set concroot	= $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI
set conc	= $concroot.conc

set SubjectHome = $cwd

set FinalResolution = $BOLD_FinalResolution

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if(! $?MaxNumRegressors) set MaxNumRegressors = 25


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

pushd ${SubjectHome}/Functional/Regressors
	if($ApplyWBRegressor && ${ComputeWBRegressor}) then
		set WB = ${patid}_WholeBrain_regressor_dt.dat
	else
		set WB = ""
	endif

	if($ApplyMOVERegressor && ${ComputeMOVERegressor}) then
		set MOV = ${patid}_Movement_regressors.dat
	else
		set MOV = ""
	endif

	if(${ApplyEACSFRegressor} && ${ComputeEACSFRegressor}) then
		set EACSF = ${patid}_EACSF_regressors.dat
	else
		set EACSF = ""
	endif

	if(${ApplyVENT} && ${ComputeVENT}) then
		set VENT = ${patid}_Ventricle_regressors.dat
	else
		set VENT = ""
	endif

	if(${ApplyWM} && ${ComputeWM}) then
		set WM = ${patid}_WhiteMatter_regressors.dat
	else
		set WM = ""
	endif

	rm SVD*

	#############################################
	# optional externally supplied task regressor
	#############################################
	TASK:
	if (! ${?task_regressor}) set task_regressor = ""
	if ($task_regressor != "") then
		if (! -r $task_regressor) then
			echo $task_regressor not accessible
			exit 1
		endif
		@ n = `wc $task_regressor | awk '{print $1}'`
		#test against the tmask length as you should be using the whole task timeseries for this
		#and it is agnostic to the processing done (i.e. may not have done band pass filtering)
		@ nframe = `wc ${SubjectHome}/Functional/TemporalMask/tmask.txt | awk '{print $2}'`

		if ($n != $nframe) then

			decho "tmask.txt frames and $task_regressor length mismatch" $DebugFile
			exit 1
		endif
	endif

	paste $MOV $VENT $WM $EACSF $task_regressor >! SVD_all_in.dat
	if($status) exit 1

	covariance $format SVD_all_in.dat -D200
	if($status) exit 1

	mv SVD_all_in.dat All_SVD_in.dat

	mv SVD_all_in*.dat SVD_regressors.dat

	if ($MaxNumRegressors != "" )  then
		paste $WB SVD_regressors.dat |\
			gawk '{if (MaxNumRegressors > NF) MaxNumRegressors = NF;for(i=1;i<=MaxNumRegressors;i++){ printf "%s\t", $i}; printf "\n";}' \
			MaxNumRegressors=$MaxNumRegressors >! ${patid}_all_regressors.dat

		if($status) exit 1
	else
		paste $WB SVD_regressors.dat >! ${patid}_all_regressors.dat
		if($status) exit 1
	endif

	if($status) exit 1

	##################################
	#	Clean up temp files
	##################################
	pushd ${SubjectHome}/Masks/FreesurferMasks
		rm -f *${FinalResTrailer}* *dies*
	popd

popd

exit 0
