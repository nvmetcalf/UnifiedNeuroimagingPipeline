#!/bin/csh

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

#project the volumes to surfaces
decho "	Projecting volume onto surface..." ${DebugFile}


$PP_SCRIPTS/Surface/surface_projection_pipeline_V3.csh $1 $2
if($status) then
	decho "		ERROR: Surface projection failed. Consult Logs/surface_projection_pipeline.log" ${DebugFile}
	exit 1
endif
decho "		Success!" ${DebugFile}
