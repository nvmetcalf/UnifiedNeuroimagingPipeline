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

set SubjectHome = $cwd
set AtlasName = `basename $target`

if(! $?flair ) then
	decho "Warning: The flair variable does not exist in $1. It denotes a FLAIR image you are wanting to register, but is not required." $DebugFile
	exit 0
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

pushd $SubjectHome/Anatomical/Volume/FLAIR

	if($NonLinear) then
		convertwarp -r $target -o ${patid}_FLAIR_warpfield_111 -m ${patid}_FLAIR_to_${patid}_T1.mat -w ../T1/${patid}_T1_warpfield_111
		if($status) exit 1
		
		applywarp -i ${patid}_FLAIR -r $target -o ${patid}_FLAIR_111_fnirt -w  ${patid}_FLAIR_warpfield_111 --interp=spline
		if($status) exit 1
		
		applywarp -i ${patid}_FLAIR -r ${target}_${FinalResTrailer} -o ${patid}"_FLAIR_${FinalResTrailer}_fnirt.nii.gz" -w ${patid}_FLAIR_warpfield_111 --interp=spline
		if($status) exit 1
	else
		decho "Non Linear registration not requested for T1. Nothing to do." $DebugFile
	endif
	
exit 0
