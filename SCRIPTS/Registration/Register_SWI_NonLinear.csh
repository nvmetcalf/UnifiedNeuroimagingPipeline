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

set SubjectHome = $cwd
set AtlasName = $target:t

if(! $?SWI ) then
	decho "Warning: The SWI variable does not exist in $1. It denotes a SWI image you are wanting to register, but is not required."
	exit 0
endif

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

pushd ${SubjectHome}/Anatomical/Volume/SWI

	if($NonLinear) then
		convertwarp -r $target -o ${patid}_SWI_to_${AtlasName}_warpfield_111.nii.gz -m ${patid}_SWI_to_${patid}_T1.mat -w ../T1/${patid}_T1_to_${AtlasName}_warpfield_111.nii.gz
		if($status) exit 1

		foreach res($FinalResolutions)
			applywarp -i ${patid}_SWI -r ${target}_${res}${res}${res} -o ${patid}_SWI_fnirt_${res}${res}${res}.nii.gz -w ${patid}_SWI_to_${AtlasName}_warpfield_111.nii.gz #--interp=spline
			if($status) exit 1
		end
	else
		decho "Non linear registration not requested for T1. Nothing to do."
	endif

popd

exit 0
