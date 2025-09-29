#!/bin/csh

#compute the temporal mask based on the parameters requested

#source the subjects params file and the processing parameters
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

if($#argv > 2) then
	set SubjectHome = $3
else
	set SubjectHome = $cwd
endif

decho "		Generating fd vals..."

if(! $?PercentFramesRemaining) then
	set PercentFramesRemaining = 0
endif

if(! $?BOLD_Dir) then
	set BOLD_Dir  = "bold"
endif

if(! $?FD_Threshold) then
	set FD_Threshold == 0
endif

if(! $?DVAR_Threshold) then
	set DVAR_Threshold = 0
endif

if( ! -e QC) mkdir QC

if(! $?RunIndex || ! $?BOLD) then
	decho "No BOLD data available, skipping temporal mask computation."
	exit 0
endif

if( ! -e Functional/Movement) then
	echo "SCRIPT: $0 : 00003 : BOLD realignment has not occured (Functional/Movement folder missing). Unable to continue."
	exit 1
endif

if($?ME_ScanSets) then
	#grab the runs from the multiecho dataset we will consider
	@ i = 1
	set ME_RunsToUse = ()
	while($i <= $#ME_ScanSets)
		set ME_RunsToUse = ($ME_RunsToUse `echo $ME_ScanSets[$i] | cut -d, -f1`)
		@ i++
	end

	set RunIndex = ($ME_RunsToUse)

	@ i = 1
	set ME_RunsToUse = ()
	while($i <= $#FCProcIndex)
		set ME_RunsToUse = ($ME_RunsToUse `echo $ME_ScanSets[$FCProcIndex[$i]] | cut -d, -f1`)
		@ i++
	end

	set FCProcIndex = ($ME_RunsToUse)

	echo "ME BOLD Runs to use: $RunIndex"
	echo "ME Fc Runs to use: $FCProcIndex"

endif

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

#check to see if we can make a DVAR timeseries based on denoised data
if($DVAR_Threshold != 0 && ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}.nii.gz) then
	decho "	WARNING: BOLD has not been denoised yet, only able to generate FD based temporal mask. Use iterative regression to also use DVAR temporal mask."
	set DVAR_Threshold = 0
endif

#Compute the FD for the resting state and whole dataset
#this will generate a FD timeseries for every BOLD dataset.
#theoreticaly the multiecho datasets shoudld be N-echos of
#similar timeseries
decho "Generating FD values for all BOLD runs"
if($FD_Threshold != 0) then
	$PP_SCRIPTS/Utilities/compute_fd_by_run.csh $1 $2 "$RunIndex" "upck_faln_dbnd_xr3d_dc_atl" "_upck_faln_dbnd_xr3d.ddat"
	if($status) then
		echo "SCRIPT: $0 : 00004 : 	Could not compute fd on whole BOLD data set."
		exit 1
	endif
else
	decho "No FD threshold set. Skipping..."
	goto DVAR_COMP
endif

#compute Fd for non-filtered movement timeseries
$PP_SCRIPTS/Utilities/compute_fd_by_run.csh $1 $2 "$RunIndex" "upck_faln_dbnd_xr3d_dc_atl" "_upck_faln_dbnd_xr3d_nf.ddat"
if($status) then
	echo "SCRIPT: $0 : 00005 : 	Could not compute unfiltered fd on whole BOLD data set."
	exit 1
endif

#for this, we only want to produce FD timeseries for the
#resting state data. For ME data, this will be the combined
#runs.
decho "Generating FD values for resting state runs"

$PP_SCRIPTS/Utilities/compute_fd_by_run.csh $1 $2 "$FCProcIndex" "rsfMRI" "_upck_faln_dbnd_xr3d.ddat"
if($status) then
	echo "SCRIPT: $0 : 00006 : 	Could not compute fd on resting state BOLD data set."
	exit 1
endif

DVAR_COMP:
#compute dvar for resting state and whole dataset
decho "Generating DVAR values for all BOLD runs."
if($DVAR_Threshold != 0) then
	$PP_SCRIPTS/Utilities/compute_dvar_by_run.csh $1 $2 "upck_faln_dbnd_xr3d_dc_atl"
	if($status) then
		echo "SCRIPT: $0 : 00007 : 	Could not compute dvar on whole BOLD data set."
		exit 1
	endif
else
	decho "No DVAR threshold set. Skipping..."
	goto COMBINED_COMP
endif

decho "Generating DVAR values for resting state runs."
$PP_SCRIPTS/Utilities/compute_dvar_by_run.csh $1 $2 "rsfMRI_uout_bpss_${Residual_Trailer}"
if($status && $DVAR_Threshold != "0") then
	echo "SCRIPT: $0 : 00008 : 	ERROR: Could not compute dvar on resting state BOLD data set. Be sure to enable volume regression and debanding."
	exit 1
else if($status) then
	decho "WARNING: Could not compute dvar on resting state BOLD data set. Most likely due to volume regression and bandpass filtering not being computed."
endif

COMBINED_COMP:
#does nothing if formats aren't to be combined
$PP_SCRIPTS/Utilities/compute_combined_format.csh $1 $2 $SubjectHome "rsfMRI_uout_bpss_${Residual_Trailer}" "rsfMRI"
if($status) then
	echo "SCRIPT: $0 : 00009 : 	Could not compute final temporal mask on resting state BOLD data set."
	exit 1
endif

$PP_SCRIPTS/Utilities/compute_combined_format.csh $1 $2 $SubjectHome "upck_faln_dbnd_xr3d_dc_atl" "upck_faln_dbnd_xr3d_dc_atl"
if($status) then
	echo "SCRIPT: $0 : 00010 : 	Could not compute final temporal mask on whole BOLD data set."
	exit 1
endif

pushd QC
	if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
		set RunCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_dvar.format
		set RSCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}_dvar.format

	else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
		#for the pre-denoised data, using dvar is useless as all the data will be censored. So we just use the FD format.
		set RunCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_fd.format
		set RSCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format
	else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
		set RunCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_fd.format
		set RSCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}_dvar_fd.format
	else
		echo "SCRIPT: $0 : 00011 : Unknown combination of format criteria. No format Generated."
		exit 1
	endif

	echo "BOLD Format being used: $RunCondensedFormat"
	echo "fMRI Format being used: $RSCondensedFormat"

	$RELEASE/format2lst `echo $RunCondensedFormat` | awk -f $PP_SCRIPTS/Utilities/frame_count.awk >! ${SubjectHome}/QC/${patid}_BOLD_frame_count.txt

	#compute how many frames we have remaining for each run we will be processing
	@ StartingFrame = 1
	@ EndingFrame = 1

	$RELEASE/format2lst `echo $RunCondensedFormat` >! temp_expanded.format

	ftouch ${SubjectHome}/Functional/Movement/${patid}_all_bold_runs.fd

	if(! -e ${SubjectHome}/QC) then
		mkdir ${SubjectHome}/QC
	endif

	echo "Run#\t#BadFrames\t#GoodFrames\t%Remaining\tSecondsRemaing" >! ${SubjectHome}/QC/${patid}_BOLD_frame_count_by_run.txt
	foreach BOLD($RunIndex)
		@ RunLength = `wc ${SubjectHome}/Functional/Movement/bold${BOLD}_upck_faln_dbnd_xr3d.ddat.fd | cut -d" " -f2`
		@ EndingFrame = $StartingFrame + $RunLength

		head -${EndingFrame} temp_expanded.format | tail -${RunLength} | awk -v TR=$BOLD_TR -f $PP_SCRIPTS/Utilities/frame_count.awk >! frame_count.tmp

		#report the thing...
		echo "${BOLD}	"`cat frame_count.tmp` >> ${SubjectHome}/QC/${patid}_BOLD_frame_count_by_run.txt

		#prepare for next run
		@ StartingFrame = $EndingFrame + 1

		cat ${SubjectHome}/Functional/Movement/bold${BOLD}_upck_faln_dbnd_xr3d.ddat.fd >> ${SubjectHome}/Functional/Movement/${patid}_all_bold_runs.fd
	end

	rm -f temp_expanded.format frame_count.tmp
popd

##########################################################################
# write out the tmask.txt
##########################################################################
#the format that reflects the good frames and the bad after all thresholding (FD, DVAR, and Remaining Frames per run).
echo "Writing tmask.txt"
$RELEASE/format2lst $RunCondensedFormat | awk '{if($1 == "x") printf("0\t"); else printf("1\t");}' >! ${SubjectHome}/Functional/TemporalMask/tmask.txt
$RELEASE/format2lst $RSCondensedFormat | awk '{if($1 == "x") printf("0\t"); else printf("1\t");}' >! ${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt

exit 0
