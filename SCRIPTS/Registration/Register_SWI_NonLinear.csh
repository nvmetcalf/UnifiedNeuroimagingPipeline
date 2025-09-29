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

pushd ${SubjectHome}/Anatomical/Volume/SWI

	if($NonLinear) then
		convertwarp -r $target -o ${patid}_SWI_warpfield_111 -m ${patid}_SWI_to_${patid}_T1.mat -w ../T1/${patid}_T1_warpfield_111
		if($status) exit 1

		foreach res(111 222 333)
			applywarp -i ${patid}_SWI -r ${target}_${res}${res}${res} -o ${patid}"_SWI_${res}${res}${res}_fnirt.nii.gz" -w ${patid}_SWI_warpfield_111 --interp=spline
			if($status) exit 1
		end
	else
		decho "Non linear registration not requested for T1. Nothing to do."
	endif

popd

exit 0
