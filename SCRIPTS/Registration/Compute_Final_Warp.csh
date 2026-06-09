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

#need to adjudicate between same session and multisession.
#currently does not reference the day1 target for final warp

#path to this sessions images
set Source_Path = ${SubjectHome}/Anatomical/Volume

#path to the target session images (can be the same)
if(! $?day1_path) then
	set Target_Path = ${SubjectHome}
	set Target_Patid = ${patid}
else
    set Target_Path = ${day1_path}
    set Target_Patid = $day1_path:t
endif

if($target == "") then
	if($Reg_Target == ${FM_Suffix}_ref) then
		set AtlasName = ${FM_Suffix}_ref
		set target_image = ${Target_Path}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${AtlasName}
	else
		set AtlasName = ${patid}_T1
		set target_image = ${Target_Path}/Anatomical/Volume/T1/${AtlasName}
	endif
else
	set AtlasName = $target:t
	set target_image = $target
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
	if(-e ${Source_Path}/FieldMapping_${FM_Suffix}/${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz) then
		set warp1 = "--warp1=${Source_Path}/FieldMapping_${FM_Suffix}/${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz"
		set out_trailer = ""
	endif

	#this is the transform to go from the initial target to the T1.
	# Only needed if the T1 is not the Reg Target and the target is
	# not itself (usually only DTI does this).
	#
	if($Reg_Target != T1 && $Reg_Target != ${FM_Suffix}_ref && ! -e ${Target_Path}/Anatomical/Volume/${Reg_Target}/${Target_Patid}_${Reg_Target}_to_${AtlasName}_warpfield_111.nii.gz) then
		if(! -e ${Target_Path}/Anatomical/Volume/${Reg_Target}/${Target_Patid}_${Reg_Target}_to_${Target_Patid}_T1.mat) then
			#don't have a way to get to the T1
			echo " Need to compute registration from $Reg_Target to T1 or some other taget to complete final warp."
			exit 1
		endif
		#grab the matrix
		set mid_mat = "--midmat=${Target_Path}/Anatomical/Volume/${Reg_Target}/${Target_Patid}_${Reg_Target}_to_${Target_Patid}_T1.mat"
	endif

    #this is the nonlinear warp from undistorted space to the target atlas
    #this will only exist if you have NonLinear = 1
    if(-e ${Target_Path}/Anatomical/Volume/${Reg_Target}/${Target_Patid}_${Reg_Target}_to_${AtlasName}_warpfield_111.nii.gz) then
	   set warp2 = "--warp2=${Target_Path}/Anatomical/Volume/${Reg_Target}/${Target_Patid}_${Reg_Target}_to_${AtlasName}_warpfield_111.nii.gz"
	   set out_trailer = "_fnirt"
	endif

	#combine everything we have if we have more than the warp1
	if($warp2 != "" || $mid_mat != "") then
		convertwarp -r ${target_image}${FinalResTrailer} $warp1 $mid_mat $warp2 -o ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_${direction}_to_${AtlasName}_warp
		if($status) exit 1
	else
		ln -s `echo $warp1 | cut -d= -f2` ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_${direction}_to_${AtlasName}_warp.nii.gz
	endif

	applywarp -i ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} \
			-r ${target_image}${FinalResTrailer} \
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
