#!/bin/csh

#compute the temporal mask based on the parameters requested

#source the subjects params file and the processing parameters
source $1
source $2

if (! -e $1) then
	echo "$1 not found!"
	exit 1
endif

if (! -e $2) then
	echo "$2 not found!"
	exit 1
endif

if($#argv > 2) then
	set SubjectHome = $3
else
	set SubjectHome = $cwd
endif

decho "		Generating fd vals..." ${DebugFile}

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
	decho "No BOLD data available, skipping temporal mask computation." ${DebugFile}
	exit 0
endif

if( ! -e Functional/Movement) then
	decho "BOLD realignment has not occured (Functional/Movement folder missing). Unable to continue." ${DebugFile}
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

#check to see if we can make a DVAR timeseries based on denoised data
if($DVAR_Threshold != 0 && ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz) then
	decho "	WARNING: BOLD has not been denoised yet, only able to generate FD based temporal mask. Use iterative regression to also use DVAR temporal mask."
	set DVAR_Threshold = 0
endif

#Compute the FD for the resting state and whole dataset
#this will generate a FD timeseries for every BOLD dataset.
#theoreticaly the multiecho datasets shoudld be N-echos of
#similar timeseries
decho "Generating FD values for all BOLD runs" $DebugFile
if($FD_Threshold != 0) then
	$PP_SCRIPTS/Utilities/compute_fd_by_run.csh $1 $2 "$RunIndex" "upck_faln_dbnd_xr3d_dc_atl" $?ME_ScanSets
	if($status) then
		decho "	Could not compute fd on whole BOLD data set." $DebugFile
		exit 1
	endif
else
	decho "No FD threshold set. Skipping..." $DebugFile
	goto DVAR_COMP
endif

#for this, we only want to produce FD timeseries for the
#resting state data. For ME data, this will be the combined
#runs.
decho "Generating FD values for resting state runs"

#if we have ME data, figure out which runs we will use as the exemplars

$PP_SCRIPTS/Utilities/compute_fd_by_run.csh $1 $2 "$FCProcIndex" "rsfMRI" $?ME_ScanSets
if($status) then
	decho "	Could not compute fd on resting state BOLD data set." $DebugFile
	exit 1
endif

DVAR_COMP:
#compute dvar for resting state and whole dataset
decho "Generating DVAR values for all BOLD runs." $DebugFile
if($DVAR_Threshold != 0) then
	$PP_SCRIPTS/Utilities/compute_dvar_by_run.csh $1 $2 "upck_faln_dbnd_xr3d_dc_atl"
	if($status) then
		decho "	Could not compute dvar on whole BOLD data set." $DebugFile
		exit 1
	endif
else
	decho "No DVAR threshold set. Skipping..." $DebugFile
	goto COMBINED_COMP
endif

decho "Generating DVAR values for resting state runs." $DebugFile
$PP_SCRIPTS/Utilities/compute_dvar_by_run.csh $1 $2 "rsfMRI_uout_bpss_resid"
if($status && $DVAR_Threshold != "0") then
	decho "	ERROR: Could not compute dvar on resting state BOLD data set. Be sure to enable volume regression and debanding." $DebugFile
	exit 1
else if($status) then
	decho "WARNING: Could not compute dvar on resting state BOLD data set. Most likely due to volume regression and bandpass filtering not being computed." $DebugFile
endif

COMBINED_COMP:
#does nothing if formats aren't to be combined
$PP_SCRIPTS/Utilities/compute_combined_format.csh $1 $2 $SubjectHome "rsfMRI_uout_bpss_resid" "rsfMRI"
if($status) then
	decho "	Could not compute final temporal mask on resting state BOLD data set." $DebugFile
	exit 1
endif

$PP_SCRIPTS/Utilities/compute_combined_format.csh $1 $2 $SubjectHome "upck_faln_dbnd_xr3d_dc_atl" "upck_faln_dbnd_xr3d_dc_atl"
if($status) then
	decho "	Could not compute final temporal mask on whole BOLD data set." $DebugFile
	exit 1
endif

pushd QC
	if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
		set RunCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_dvar.format
		set RSCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_resid_dvar.format

	else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
		set RunCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_fd.format
		set RSCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format
	else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
		set RunCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_upck_faln_dbnd_xr3d_dc_atl_dvar_fd.format
		set RSCondensedFormat = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_resid_dvar_fd.format
	else
		decho "Unknown combination of format criteria. No format Generated." ${DebugFile}
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
