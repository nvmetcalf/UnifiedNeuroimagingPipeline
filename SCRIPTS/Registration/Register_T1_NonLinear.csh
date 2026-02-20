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

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

echo "Detected the following final resolutions: $FinalResolutions"

pushd ${SubjectHome}/Anatomical/Volume/T1

	if( -e $SubjectHome/Masks/${patid}_${MaskTrailer}.nii.gz) then
		echo "Found Mask! Setting mask to ${SubjectHome}/Masks/${patid}_${MaskTrailer}"
		#make the compliment
		fslmaths $SubjectHome/Masks/${patid}_${MaskTrailer}.nii.gz -mul -1 -add 1 $SubjectHome/Masks/${patid}_${MaskTrailer}_comp.nii.gz
		if($status) exit 1

		fslmaths ${patid}"_T1_brain" -mul $SubjectHome/Masks/${patid}_${MaskTrailer}_comp.nii.gz ${patid}"_T1_brain"
		if($status) exit 1

		rm ${SubjectHome}/Masks/${patid}_${MaskTrailer}_comp.*
	endif

	#check to make sure we have the atlas in nifti form so we can generate a warpfield
	if(! -e ${target}.nii && ! -e ${target}.nii.gz) then
		echo "SCRIPT: $0 : 00003 : Unable to perform non-linear alignment as the target (${target}) does not exist in nifti format."
		exit 1
	endif
	#--refmask=${target}_brain_mask --inmask=${patid}"_T1_brain_mask"
	fnirt --in=${patid}"_T1" --ref=${target} --jout=${cwd}/$patid"_jacobiantransform.nii.gz" --fout=${cwd}/$patid"_T1_to_${AtlasName}_warpfield_111.nii.gz" --aff=${patid}_T1_to_${AtlasName}.mat --cout=${cwd}/$patid"_T1_to_${AtlasName}_coeffield_111.nii.gz" --config=${target}.cnf
	if($status) then
		echo "SCRIPT: $0 : 00004 : Failed to compute non-linear transform for linearly aligned T1 to atlas."
		exit 1
	endif

	foreach res($FinalResolutions)
		applywarp -i ${patid}"_T1.nii.gz" -r ${target}_${res}${res}${res} -o ${patid}"_T1_fnirt_${res}${res}${res}.nii.gz" -w $patid"_T1_to_${AtlasName}_warpfield_111.nii.gz" --interp=spline
		if($status) exit 1
	end

	#fnirt the pathology mask
	if(-e $SubjectHome/Masks/${patid}_${MaskTrailer}.nii.gz || -e $SubjectHome/Masks/${patid}_${MaskTrailer}.nii) then
		applywarp -i $SubjectHome/Masks/${patid}_${MaskTrailer} -r $target -w $patid"_T1_to_${AtlasName}_warpfield_111.nii.gz" -o $SubjectHome/Masks/${patid}_fnirt_${MaskTrailer}".nii.gz" --interp=nn
		if($status) exit 1
	endif

	invwarp -w $patid"_T1_to_${AtlasName}_warpfield_111.nii.gz" -o ${patid}"_T1_to_${AtlasName}_invwarpfield_111.nii.gz" -r ${patid}"_T1"
	if($status) exit 1

	invwarp -w ${cwd}/$patid"_T1_to_${AtlasName}_coeffield_111.nii.gz"  -o ${patid}"_T1_to_${AtlasName}_invcoeffield_111.nii.gz" -r ${patid}"_T1"
	if($status) exit 1

	rm -f *.4dfp.*
popd

exit 0
