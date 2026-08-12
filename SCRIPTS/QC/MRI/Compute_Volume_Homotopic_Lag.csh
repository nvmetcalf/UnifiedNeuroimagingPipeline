#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

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

if($?FCProcIndex && -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}.nii.gz) then
	pushd QC
	
		set format = `cat ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_combined.format`

		pushd ${SubjectHome}/Functional/Regressors
			#paste ${patid}_Movement_regressors.dat ${patid}_Ventricle_regressors.dat ${patid}_EACSF_regressors.dat >! ${patid}_lag_regressors.dat
			paste ${patid}_Movement_regressors.dat ${patid}_Ventricle_regressors.dat ${patid}_EACSF_regressors.dat >! ${patid}_lag_regressors.dat
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
