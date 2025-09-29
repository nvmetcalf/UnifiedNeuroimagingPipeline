#!/bin/csh

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

set RunsToUse = ($3)
set Trailer = $4
set ddat_Trailer = $5

if($ddat_Trailer == "") then
	set ddat_Trailer = "_upck_faln_dbnd_xr3d.ddat"
endif

set SubjectHome = $cwd

decho "		Generating fd vals..."

if(! $?PercentFramesRemaining) then
	set PercentFramesRemaining = 0
endif

if(! $?BOLD_Dir) then
	set BOLD_Dir  = "bold"
endif

if(! $?FD_Threshold) then
	decho "No FD threshold set. Skipping..."
	exit 0
endif

if($FD_Threshold == 0) then
	decho "FD threshold set to 0. Skipping..."
	exit 0
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

			set DDATList = `echo ${DDATList}" "bold${DDAT}${ddat_Trailer}`

			$PP_SCRIPTS/Utilities/compute_fd.csh ${cwd}/bold${DDAT}${ddat_Trailer} $BrainRadius $skip 1 $FD_Threshold
			if($status) then
				echo "SCRIPT: $0 : 00004 : failed to compute fd."
				exit 1
			endif
			set FormatList = ($FormatList bold${DDAT}${ddat_Trailer}.format_expanded)

			cat bold${DDAT}${ddat_Trailer}.fd >> ${patid}_all_bold_runs.fd
		end

		if($#FormatList > 1) then
			paste -d" " $FormatList | sed 's/ //g' >! ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded
		else
			cat $FormatList >! ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded
		endif

		cat ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded

		$RELEASE/condense `cat ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded` >! ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format
		if(`wc ${SubjectHome}/Functional/TemporalMask/${patid}_${Trailer}_fd.format_expanded | awk '{print $3}'` < 10) then
			echo "SCRIPT: $0 : 00005 : 				FAILED! ${patid}.dvals in the movement folder is not long enough."
			exit 1
		endif

	popd
endif

exit 0
