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

if($#argv > 2) then
	set SubjectHome = $3
else
	set SubjectHome = $cwd
endif

if($target != "") then
	set AtlasName = `basename $target`
else
	set AtlasName = ${patid}_T1
endif

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

#see if the freesurfer segmentation has been run, if so, extract the mask
set InMask = ""

if(! $?day1_path || ! $?day1_patid) then
	set day1_path = ""
	set day1_patid = ""
	set FSdir = ${SubjectHome}/Freesurfer
else
	set FSdir = ${day1_path}/Freesurfer
endif

if(! -e ${FSdir}/mri/aparc+aseg.mgz ) then
	decho "Freesurfer failed to create aparc+aseg. Rerun freesurfer manually." $DebugFile
	exit 1
endif

if($day1_path != "") then
	set T1 = ${day1_path}/Anatomical/Volume/T1/${day1_patid}_T1
	set T1_to_ATL_mat = ${day1_path}/Anatomical/Volume/T1/${day1_patid}_T1_to_${AtlasName}.mat
else
	set T1 = ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1
	set T1_to_ATL_mat = ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_to_${AtlasName}.mat
endif

if($target == "") then
	set T1_to_ATL_mat = ""
endif

rm -r ${SubjectHome}/Masks/FreesurferMasks
mkdir -p ${SubjectHome}/Masks/FreesurferMasks
pushd ${SubjectHome}/Masks/FreesurferMasks

	decho "Converting orig.mgz to nifti and generating initial used voxels mask." ${DebugFile}
	$FREESURFER_HOME/bin/mri_convert -it mgz -ot nii ${FSdir}/mri/orig.mgz ${patid}_orig.nii
	if ($status) exit $status
	
	$FSLBIN/flirt -in ${patid}_orig.nii -ref $T1 -omat ${patid}_orig_to_${patid}_T1.mat -out ${patid}_orig_to_${patid}_T1.nii.gz -interp spline -dof 6
	if ($status) exit $status

	$FREESURFER_HOME/bin/mri_convert ${FSdir}/mri/"aparc+aseg.mgz" "aparc+aseg.nii.gz"
	if($status) exit 1
 
	$FSLBIN/fslmaths "aparc+aseg.nii.gz" -bin -dilD -dilD -ero -fillh "aparc+aseg_bin.nii.gz"
	if($status) exit 1
 
	flirt -in "aparc+aseg_bin.nii.gz" -ref $T1 -out ${SubjectHome}/Masks/${patid}_used_voxels_T1 -applyxfm -init ${patid}_orig_to_${patid}_T1.mat -interp nearestneighbour
	if($status) exit 1
		
	#resampled native space used voxels mask
	flirt -in ${SubjectHome}/Masks/${patid}_used_voxels_T1 -ref $T1 -out ${SubjectHome}/Masks/${patid}_used_voxels_T1_${FinalResTrailer} -applyisoxfm $FinalResolution -interp nearestneighbour
	if($status) exit 1
	
	#if we are using a target atlas, transform the used voxel mask to atlas space
	if($target != "") then
		convert_xfm -omat ${patid}_orig_to_${AtlasName}.mat -concat $T1_to_ATL_mat ${patid}_orig_to_${patid}_T1.mat 
		if($status) exit 1
		
		flirt -in "aparc+aseg_bin.nii.gz" -ref $target -out ${SubjectHome}/Masks/${patid}_used_voxels -applyxfm -init ${patid}_orig_to_${AtlasName}.mat -interp nearestneighbour
		if($status) exit 1
	else
		#we aren't, so copy the T1 space used voxels mask so we can resample it to the final resolution
		rm -f ${SubjectHome}/Masks/${patid}_used_voxels.nii.gz
		
		cp -sf ${SubjectHome}/Masks/${patid}_used_voxels_T1.nii.gz ${SubjectHome}/Masks/${patid}_used_voxels.nii.gz
		if($status) exit 1
	endif
	
	flirt -in ${SubjectHome}/Masks/${patid}_used_voxels -ref ${SubjectHome}/Masks/${patid}_used_voxels -out ${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer} -interp nearestneighbour -applyisoxfm ${FinalResolution}
	if($status) exit 1
	
	#see if we can apply a non linear warp
	if($day1_path != "") then
		set warp = ${day1_path}/Anatomical/Volume/T1/$day1_patid"_T1_warpfield_111.nii.gz"
	else
		set warp = ${SubjectHome}/Anatomical/Volume/T1/$patid"_T1_warpfield_111.nii.gz"
	endif
	
	if($NonLinear && -e $warp) then
		#apply the nonlinear warp to the used voxels mask
		$FSLBIN/applywarp -i ${SubjectHome}/Masks/${patid}_used_voxels_T1.nii.gz -r $target -w $warp -o ${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz --interp=nn
		if($status) exit 1

		$FSLBIN/applywarp -i ${SubjectHome}/Masks/${patid}_used_voxels_T1.nii.gz -r $target"_"${FinalResTrailer} -w $warp -o ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz --interp=nn
		if($status) exit 1
	endif
	
popd

exit 0
