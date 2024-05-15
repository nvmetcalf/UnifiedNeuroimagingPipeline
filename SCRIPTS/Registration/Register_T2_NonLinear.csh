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

if(! $?tse ) then
	decho "Warning: The tse variable does not exist in $1. It denotes a T2 image you are wanting to register, but is not required." $DebugFile
	exit 0
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

pushd ${SubjectHome}/Anatomical/Volume/T2

	if($NonLinear) then
		convertwarp -r $target -o ${patid}_T2_warpfield_111 -m ${patid}_T2_to_${patid}_T1.mat -w ../T1/${patid}_T1_warpfield_111
		if($status) exit 1
		
		applywarp -i ${patid}"_T2" -r $target -o ${patid}_T2_111_fnirt -w ${patid}_T2_warpfield_111 --interp=spline
		if($status) exit 1
		
		applywarp -i ${patid}_T2 -r ${target}_${FinalResTrailer} -o ${patid}"_T2_${FinalResTrailer}_fnirt.nii.gz" -w ${patid}_T2_warpfield_111 --interp=spline
		if($status) exit 1
	else
		decho "Non linear registration not requested for T1. Nothing to do."
	endif
	
popd

exit 0
