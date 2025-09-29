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

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set SubjectHome = $cwd

#link up to the first sessions freesurfer
if(! -e ${day1_path}/Freesurfer) then
	echo "SCRIPT: $0 : 00003 : $day1_patid does not seem to have a Freesurfer folder."
	exit 1
endif

rm -f Freesurfer
ln -sf ${day1_path}/Freesurfer .

#generate all the masks we will need to start things off
$PP_SCRIPTS/Utilities/Generate_UsedVoxels_Masks.csh $1 $2 $SubjectHome
if($status) then
	echo "SCRIPT: $0 : 00004 : Unable to generate UsedVoxels Masks for for current session."
	exit 1
endif

exit 0
