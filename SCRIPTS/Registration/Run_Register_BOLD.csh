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

$PP_SCRIPTS/Registration/Register_BOLD_FrameAlign.csh $1 $2
if($status) then
	echo "SCRIPT: $0 : 00003 : Unable to perform BOLD frame alignment and normalization."
	exit 1
endif

$PP_SCRIPTS/Registration/Register_BOLD_Transform.csh $1 $2
if($status) then
	echo "SCRIPT: $0 : 00004 : Unable to perform BOLD atlas transformations."
	exit 1
endif

exit 0
