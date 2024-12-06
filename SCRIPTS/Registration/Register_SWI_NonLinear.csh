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

if(! $?DebugFile) then
	set DebugFile = ${cwd}/$0:t
	ftouch $DebugFile
endif

set SubjectHome = $cwd
set AtlasName = $target:t

if(! $?SWI ) then
	decho "Warning: The SWI variable does not exist in $1. It denotes a SWI image you are wanting to register, but is not required." $DebugFile
	exit 0
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

pushd ${SubjectHome}/Anatomical/Volume/SWI

	if($NonLinear) then
		convertwarp -r $target -o ${patid}_SWI_warpfield_111 -m ${patid}_SWI_to_${patid}_T1.mat -w ../T1/${patid}_T1_warpfield_111
		if($status) exit 1
		
		applywarp -i ${patid}"_SWI" -r $target -o ${patid}_SWI_111_fnirt -w ${patid}_SWI_warpfield_111 --interp=spline
		if($status) exit 1
		
		applywarp -i ${patid}_SWI -r ${target}_${FinalResTrailer} -o ${patid}"_SWI_${FinalResTrailer}_fnirt.nii.gz" -w ${patid}_SWI_warpfield_111 --interp=spline
		if($status) exit 1
	else
		decho "Non linear registration not requested for T1. Nothing to do."
	endif
	
popd

exit 0
