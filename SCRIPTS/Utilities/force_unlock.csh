#!/bin/csh

source $1
source $2

if(-e .inprocess) then
	rm -f .inprocess
	if($status) then
		echo "Unable to unlock ${patid} for processing. You may not have permissions to operate on this participant."
		exit 1
	endif
else
	echo "$patid is not currently locked."
endif
exit 0
