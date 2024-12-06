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
set AtlasName = $target:t

if(! $?DebugFile) then
	set DebugFile = ${cwd}/$0:t
	ftouch $DebugFile
endif

#FinalResolution of the non linear warpfield for other modalities
if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

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
		echo "Unable to perform non-linear alignment as the target (${target}) does not exist in nifti format." $DebugFile
		exit 1
	endif

	$FSLBIN/fnirt --in=${patid}"_T1" --ref=${target} --inmask=${patid}"_T1_brain_mask" --jout=${cwd}/$patid"_jacobiantransform.nii.gz" --fout=${cwd}/$patid"_T1_warpfield_111.nii.gz" --aff=${patid}_T1_to_${AtlasName}.mat --cout=${cwd}/$patid"_T1_coeffield_111.nii.gz" --config=${target}.cnf
	if($status) then
		decho "Failed to compute non-linear transform for linearly aligned T1 to atlas." $DebugFile
		exit 1
	endif

	applywarp -i ${patid}"_T1.nii.gz" -r $target -o ${patid}"_T1_111_fnirt.nii.gz" -w $patid"_T1_warpfield_111.nii.gz" --interp=spline
	if($status) exit 1
	
	applywarp -i ${patid}"_T1.nii.gz" -r ${target}_${FinalResTrailer} -o ${patid}"_T1_${FinalResTrailer}_fnirt.nii.gz" -w $patid"_T1_warpfield_111.nii.gz" --interp=spline
	if($status) exit 1
	
	#fnirt the pathology mask
	if(-e $SubjectHome/Masks/${patid}_${MaskTrailer}.nii.gz || -e $SubjectHome/Masks/${patid}_${MaskTrailer}.nii) then
		$FSLBIN/applywarp -i $SubjectHome/Masks/${patid}_${MaskTrailer} -r $target -w $patid"_T1_warpfield_111" -o $SubjectHome/Masks/${patid}_${MaskTrailer}"_fnirt.nii.gz" --interp=nn
		if($status) exit 1
	endif

	$FSLBIN/invwarp -w $patid"_T1_warpfield_111.nii.gz" -o ${patid}"_T1_invwarpfield_111.nii.gz" -r ${patid}"_T1"
	if($status) exit 1

	$FSLBIN/invwarp -w ${cwd}/$patid"_T1_coeffield_111.nii.gz"  -o ${patid}"_T1_invcoeffield_111.nii.gz" -r ${patid}"_T1"
	if($status) exit 1
	
	rm -f *.4dfp.*
popd

exit 0
