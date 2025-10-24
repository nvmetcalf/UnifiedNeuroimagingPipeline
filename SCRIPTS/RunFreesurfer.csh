#!/bin/csh

if($#argv != 2) then
	echo "SCRIPT: $0 : 00000 : incorrect number of arguments"
	exit 1
endif

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

#need this to know what freesurfer script to run.
source $PP_SCRIPTS/Config/P2.cfg

set SubjectHome = $cwd

if(! $?skip_recon) then
	set skip_recon = 0
endif

if($skip_recon) then
	echo "-no_recon set, skipping recon all"
	exit 0
endif

if($?day1_path) then
	decho "sessions is not a first session, skipping recon-all"
	exit 0
endif

if(! $?FreesurferVersionToUse) then
	set FreesurferVersionToUse = "fs7_4_1"
endif

if(`tail -1 ${SubjectHome}/Freesurfer/${FreesurferVersionToUse}/scripts/recon-all.log | grep "without error"` != "") then
	echo "recon-all has already been completed"
	exit 0
endif

echo "recon-all WILL be run."

@ i = 1

while($i <= $#FreesurferCommands)
	if($FreesurferVersionToUse == $FreesurferCommands[$i]) then
		@ k = $i + 1

		echo "Using script: $FreesurferCommands[$k]"
		$FreesurferCommands[$k] $1 $2
		if($status) then
			echo "SCRIPT: $0 : 00003 : Freesurfer processing failed ($FreesurferCommands[$k])."
			exit 1
		endif
		break
	endif
	@ i = $i + 2
end

exit 0
