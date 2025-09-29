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

if(! $?T1 || $#T1 == 0 ) then
	decho "Unable to find T1 image in params file, unable to continue."
	exit 1
endif

$PP_SCRIPTS/Registration/Register_T1.csh $1 $2
if($status) then
	echo "SCRIPT: $0 : 00003 : Could not register T1 to target atlas."
	exit 1
endif

if($NonLinear) then
	$PP_SCRIPTS/Registration/Register_T1_NonLinear.csh $1 $2
	if($status) then
		echo "SCRIPT: $0 : 00004 :Unable to Nonlinearly Register T1 to target."
		exit 1
	endif
else
	echo "Nonlinear registration not requested, skipping."
endif

exit 0
