#!/bin/csh

source $1
source $2


#Figure out what registrations and methods were requested.
# put together options for combining undistorted data space to a target image.
# compute the warp from distorted data space to final target image space.

set FM_Suffix = $3
set Reg_Target = $4
set FinalResolution = $5
set peds = ($6)

set SubjectHome = $cwd

if($target == "") then
	if($Reg_Target == ${FM_Suffix}_ref) then
		set AtlasName = ${FM_Suffix}_ref
		set target_path = ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${AtlasName}
	else
		set AtlasName = ${patid}_T1
		set target_path = ${SubjectHome}/Anatomical/Volume/T1/${AtlasName}
	endif
else
	set AtlasName = $target:t
	set target_path = $target
endif

set FinalResTrailer = ""
if($FinalResolution != 0) then
	set FinalResTrailer = "_${FinalResolution}${FinalResolution}${FinalResolution}"
endif

set ref_images = ()

foreach direction($peds)
	set warp1 = ""
	set warp2 = ""
	set mid_mat = ""

	#this warp should always exist as it's the metric modality to anatomical target with distortion correction
	#the warp is the affine matrix converted to warp form
	if(-e ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}/${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz) then
		set warp1 = "--warp1=${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}/${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz"
		set out_trailer = ""
	endif

	#this is the transform to go from the initial target to the T1.
	# Only needed if the T1 is not the Reg Target and the target is
	# not itself (usually only DTI does this).
	if($Reg_Target != T1 && $Reg_Target != ${FM_Suffix}_ref && ! -e ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_to_${AtlasName}_warpfield_111.nii.gz) then
		if(! -e ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_to_${patid}_T1.mat) then
			#don't have a way to get to the T1
			echo " Need to compute registration from $Reg_Target to T1 or some other taget to complete final warp."
			exit 1
		endif
		#grab the matrix
		set mid_mat = "--midmat=${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_to_${patid}_T1.mat"
	endif

	#this is the nonlinear warp from undistorted space to the target atlas
	#this will only exist if you have NonLinear = 1
	if(-e ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_to_${AtlasName}_warpfield_111.nii.gz) then
		set warp2 = "--warp2=${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_to_${AtlasName}_warpfield_111.nii.gz"
		set out_trailer = "_fnirt"
	endif

	#combine everything we have if we have more than the warp1
	if($warp2 != "" || $mid_mat != "") then
		convertwarp -r ${target_path}${FinalResTrailer} $warp1 $mid_mat $warp2 -o ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_${direction}_to_${AtlasName}_warp
		if($status) exit 1
	else
		ln -s `echo $warp1 | cut -d= -f2` ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_${direction}_to_${AtlasName}_warp.nii.gz
	endif

	applywarp -i ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} \
			-r ${target_path}${FinalResTrailer} \
			-w ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_${direction}_to_${AtlasName}_warp \
			-o ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_${direction}${out_trailer}${FinalResTrailer}
	if($status) exit 1

	set ref_images = ($ref_images ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_${direction}${out_trailer}${FinalResTrailer})
end

fslmerge -t ${FM_Suffix}_ref_stack $ref_images
if($status) exit 1

fslmaths ${FM_Suffix}_ref_stack -Tmean ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref${out_trailer}${FinalResTrailer}.nii.gz
if ($status) exit 1

rm ${FM_Suffix}_ref_stack.nii.gz
exit 0
