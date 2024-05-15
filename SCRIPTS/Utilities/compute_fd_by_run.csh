#!/bin/csh

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

set RunsToUse = ($3)
set Trailer = $4
set Do_MultiEcho = $5

set SubjectHome = $cwd

decho "		Generating fd vals..." ${DebugFile}

if(! $?PercentFramesRemaining) then
	set PercentFramesRemaining = 0
endif

if(! $?BOLD_Dir) then
	set BOLD_Dir  = "bold"
endif

if(! $?FD_Threshold) then
	decho "No FD threshold set. Skipping..." $DebugFile
	exit 0
endif

if($FD_Threshold == 0) then
	decho "FD threshold set to 0. Skipping..." $DebugFile
	exit 0
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

if(! $?RegisterEcho) then
	set RegisterEcho = 1
endif

if(! $?BrainRadius) then
	set BrainRadius = 50
endif

if(! $?FD_Echo_Threshold) set FD_Echo_Threshold = 0.1

#compute the FD for each run
if (-e Functional/Movement) then
	pushd Functional/Movement	#into movement
		ftouch ${patid}_all_bold_runs.fd
		set DDATList = ()
		set FormatList = ()
		#compute the FD for all runs
		foreach DDAT($RunsToUse)
			
			set DDATList = `echo ${DDATList}" "bold${DDAT}_upck_faln_dbnd_xr3d.ddat`
			
			$PP_SCRIPTS/Utilities/compute_fd.csh ${cwd}/bold${DDAT}_upck_faln_dbnd_xr3d.ddat $BrainRadius $skip 1 $FD_Threshold
			if($status) exit 1
			
			set FormatList = ($FormatList bold${DDAT}_upck_faln_dbnd_xr3d.ddat.format_expanded)
			
			cat bold${DDAT}_upck_faln_dbnd_xr3d.ddat.fd >> ${patid}_all_bold_runs.fd
		end

# 		#if this is a multiecho dataset, then we need to combine the echo's from each set
# 		if($Do_MultiEcho) then
# 			set n_echo = $#BOLD_TE
# 			
# 			rm -f ${patid}_${Trailer}_all_me_fd_results.txt
# 			touch ${patid}_${Trailer}_all_me_fd_results.txt
# 			
# 			#for each multiecho set, we want to make a file with all the FD for each echo
# 			#then compute the average FD, flag if the FD is too large, flag if there
# 			#was too much movement across echo's, and finally flag if either of those are bad.
# 			#then concatonate the runs we want to use going forward
# 			@ k = 1
# 			set FormatList = ()
# 			set DDATList = ()
# 			while($k <= $#ME_ScanSets)
# 				set ME_set = (`echo $ME_ScanSets[$k] | sed -e 's/,/ /g'`)
# 				set FormatList = ( $FormatList bold${ME_set[$RegisterEcho]}_upck_faln_dbnd_xr3d.ddat.format_expanded )
# 				set DDATList = (${DDATList} "bold${ME_set[$RegisterEcho]}_upck_faln_dbnd_xr3d.ddat")
# 				@ k++
# 			end
# 		endif
		
		if($#FormatList > 1) then
			paste -d" " $FormatList | sed 's/ //g' >! ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded
		else
			cat $FormatList >! ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded
		endif
			
		cat ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded
		
		$RELEASE/condense `cat ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded` >! ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format
		if(`wc ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded | awk '{print $3}'` < 10) then
			decho "				FAILED! ${patid}.dvals in the movement folder is not long enough." ${DebugFile}
			exit 1
		endif
		
	popd
endif

exit 0
