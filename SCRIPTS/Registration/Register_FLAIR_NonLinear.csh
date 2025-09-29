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

if(! $?FLAIR ) then
	decho "Warning: The flair variable does not exist in $1. It denotes a FLAIR image you are wanting to register, but is not required."
	exit 0
endif

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

echo "Detected the following final resolutions: $FinalResolutions"

pushd $SubjectHome/Anatomical/Volume/FLAIR

	if($NonLinear) then
		convertwarp -r $target -o ${patid}_FLAIR_warpfield_111 -m ${patid}_FLAIR_to_${patid}_T1.mat -w ../T1/${patid}_T1_warpfield_111
		if($status) exit 1

		applywarp -i ${patid}_FLAIR -r $target -o ${patid}_FLAIR_111_fnirt -w  ${patid}_FLAIR_warpfield_111 --interp=spline
		if($status) exit 1

		foreach res($FinalResolutions)
			applywarp -i ${patid}_FLAIR -r ${target}_${res}${res}${res} -o ${patid}"_FLAIR_${res}${res}${res}_fnirt.nii.gz" -w ${patid}_FLAIR_warpfield_111 --interp=spline
			if($status) exit 1
		end
	else
		decho "Non Linear registration not requested for FLAIR. Nothing to do."
	endif

exit 0
