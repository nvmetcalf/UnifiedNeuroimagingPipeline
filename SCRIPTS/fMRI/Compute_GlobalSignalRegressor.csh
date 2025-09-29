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


pushd ${SubjectHome}/Functional/Regressors
	#############################################################
	# make the whole brain regressor including the 1st derivative
	#############################################################

	niftigz_4dfp -n ${SubjectHome}/Masks/FreesurferMasks/${patid}_WholeBrain_mask ${SubjectHome}/Functional/Regressors/${patid}_WholeBrain_mask
	if($status) exit 1

	qnt_4dfp -s -d -F$format ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_WholeBrain_mask \
		| awk '$1!~/#/{printf("%10.4f%10.4f\n", $2, $3)}' >! ${patid}_WholeBrain_regressor_dt.dat
	@ n = `wc ${patid}_WholeBrain_regressor_dt.dat | awk '{print $1}'`
	if ($n != $nframe) then
		decho "${patid}_mov_regressors.dat ${patid}_WB_regressor_dt.dat length mismatch" $DebugFile
		exit 1
	endif
popd

exit 0
