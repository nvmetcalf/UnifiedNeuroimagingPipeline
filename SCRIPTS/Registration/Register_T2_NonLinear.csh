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

if(! $?T2 ) then
	decho "Warning: The T2 variable does not exist in $1. It denotes a T2 image you are wanting to register, but is not required."
	exit 0
endif

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

echo "Detected the following final resolutions: $FinalResolutions"


pushd ${SubjectHome}/Anatomical/Volume/T2

	if($NonLinear) then
		convertwarp -r $target -o ${patid}_T2_warpfield_111 -m ${patid}_T2_to_${patid}_T1.mat -w ../T1/${patid}_T1_warpfield_111
		if($status) then
			echo "SCRIPT: $0 : 00003 : unable to combine T1 to target warp with T2 -> t1 transform."
			exit 1
		endif

		applywarp -i ${patid}"_T2" -r $target -o ${patid}_T2_111_fnirt -w ${patid}_T2_warpfield_111 --interp=spline
		if($status) then
			echo "SCRIPT: $0 : 00004 : unable to warp T2 to target."
			exit 1
		endif
		foreach res($FinalResolutions)
			applywarp -i ${patid}_T2 -r ${target}_${res}${res}${res} -o ${patid}"_T2_${res}${res}${res}_fnirt.nii.gz" -w ${patid}_T2_warpfield_111 --interp=spline
			if($status) then
				echo "SCRIPT: $0 : 00005 : unable to warp and resample T2 to target."
				exit 1
			endif
		end
	else
		decho "Non linear registration not requested for T2. Nothing to do."
	endif

popd

exit 0
