#!/bin/csh

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

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

#see if the freesurfer segmentation has been run, if so, extract the mask
set InMask = ""

if(! $?day1_path) then
	set day1_path = ""
	set day1_patid = ""
	set FSdir = ${SubjectHome}/Freesurfer/${FreesurferVersionToUse}
else
	set day1_patid = $day1_path:t
	set FSdir = ${day1_path}/Freesurfer/${FreesurferVersionToUse}
endif

if(! -e ${FSdir}/mri/aparc+aseg.mgz ) then
	echo "SCRIPT: $0 : 00003 : Freesurfer failed to create aparc+aseg. Rerun freesurfer manually."
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

	echo "Converting orig.mgz to nifti and generating initial used voxels mask."
	$FREESURFER_HOME/bin/mri_convert -it mgz -ot nii ${FSdir}/mri/orig.mgz ${patid}_orig.nii
	if ($status) then
		echo "SCRIPT: $0 : 00004 : could not convert orig from mgz to nifti."
		exit $status
	endif

	flirt -in ${patid}_orig.nii -ref $T1 -omat ${patid}_orig_to_${patid}_T1.mat -out ${patid}_orig_to_${patid}_T1.nii.gz -interp spline -dof 6
	if ($status) then
		echo "SCRIPT: $0 : 00005 : could not register orig to T1."
		exit $status
	endif

	$FREESURFER_HOME/bin/mri_convert ${FSdir}/mri/"aparc+aseg.mgz" "aparc+aseg.nii.gz"
	if($status) then
		echo "SCRIPT: $0 : 00006 : could not convert aparc+aseg.mgz to nifti"
		exit 1
	endif

	fslmaths "aparc+aseg.nii.gz" -bin -dilD -dilD -ero -fillh "aparc+aseg_bin.nii.gz"
	if($status) then
		echo "SCRIPT: $0 : 00007 : could not prepare aparc+aseg a a mask."
		exit 1
	endif

	flirt -in "aparc+aseg_bin.nii.gz" -ref $T1 -out ${SubjectHome}/Masks/${patid}_used_voxels_T1 -applyxfm -init ${patid}_orig_to_${patid}_T1.mat -interp nearestneighbour
	if($status) then
		echo "SCRIPT: $0 : 00008 : could not transform aparc+aseg to T1."
		exit 1
	endif

	#resampled native space used voxels mask
	foreach res($FinalResolutions)
		if($res == 0) then
			continue
		endif
		flirt -in ${SubjectHome}/Masks/${patid}_used_voxels_T1 -ref $T1 -out ${SubjectHome}/Masks/${patid}_used_voxels_T1_${res}${res}${res} -applyisoxfm ${res} -interp nearestneighbour
		if($status) then
			echo "SCRIPT: $0 : 00009 : failed to resample used voxels mask in t1 space to ${res} mm^3."
			exit 1
		endif
	end

	#if we are using a target atlas, transform the used voxel mask to atlas space
	if($target != "") then
		convert_xfm -omat ${patid}_orig_to_${AtlasName}.mat -concat $T1_to_ATL_mat ${patid}_orig_to_${patid}_T1.mat
		if($status) then
			echo "SCRIPT: $0 : 00010 : failed to combine orig -> t1 and t1 -> target transforms."
			exit 1
		endif

		flirt -in "aparc+aseg_bin.nii.gz" -ref $target -out ${SubjectHome}/Masks/${patid}_used_voxels -applyxfm -init ${patid}_orig_to_${AtlasName}.mat -interp nearestneighbour
		if($status) then
			echo "SCRIPT: $0 : 00011 : failed to transform aparc+aseg mask to target space."
			exit 1
		endif
	else
		#we aren't, so copy the T1 space used voxels mask so we can resample it to the final resolution
		rm -f ${SubjectHome}/Masks/${patid}_used_voxels.nii.gz
		pushd ${SubjectHome}/Masks
			cp -sf ${patid}_used_voxels_T1.nii.gz ${patid}_used_voxels.nii.gz
			if($status) exit 1
		popd
	endif


	foreach res($FinalResolutions)
		if($res == 0) then
			continue
		endif
		flirt -in ${SubjectHome}/Masks/${patid}_used_voxels -ref ${SubjectHome}/Masks/${patid}_used_voxels -out ${SubjectHome}/Masks/${patid}_used_voxels_${res}${res}${res} -interp nearestneighbour -applyisoxfm ${res}
		if($status) then
			echo "SCRIPT: $0 : 00012 : failed to resample used voxels mask from target space to ${res} mm^3"
			exit 1
		endif
	end

	#see if we can apply a non linear warp
	if($day1_path != "") then
		set warp = ${day1_path}/Anatomical/Volume/T1/$day1_patid"_T1_warpfield_111.nii.gz"
	else
		set warp = ${SubjectHome}/Anatomical/Volume/T1/$patid"_T1_warpfield_111.nii.gz"
	endif

	if($NonLinear && -e $warp) then
		#apply the nonlinear warp to the used voxels mask
		applywarp -i ${SubjectHome}/Masks/${patid}_used_voxels_T1.nii.gz -r $target -w $warp -o ${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz --interp=nn
		if($status) then
			echo "SCRIPT: $0 : 00013 : failed to non linearly warp T1 space used voxels mask."
			exit 1
		endif

		foreach res($FinalResolutions)
			if($res == 0) then
				continue
			endif
			applywarp -i ${SubjectHome}/Masks/${patid}_used_voxels_T1.nii.gz -r $target"_"${res}${res}${res} -w $warp -o ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${res}${res}${res}.nii.gz --interp=nn
			if($status) then
				echo "SCRIPT: $0 : 00014 : failed to non linearly warp and resample used t1 voxels mask."
				exit 1
			endif
		end
	endif

popd

exit 0
