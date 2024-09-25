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

if(! $?day1_path || ! $?day1_patid) then
	set day1_path = ""
	set day1_patid = ""
endif

if($target != "") then
	set AtlasName = `basename $target`
	set RegTarget = $target
else
	if($day1_patid != "" || $day1_path != "") then
		set AtlasName = ${day1_patid}_T1
		set RegTarget = ${day1_path}/Anatomical/Volume/T1/${day1_patid}_T1
	else
		set AtlasName = ${patid}_T1
		set RegTarget = ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1
	endif
endif
if(! $?FinalResolution) then
	set FinalResolution = 3
endif

if(! $?ASL_Reg_Target && $?tse) then
	set ASL_Reg_Target = T2
else if(! $?ASL_Reg_Target) then
	set ASL_Reg_Target = T1
endif

if(! $?ASL_fm && $?fm) then
	set ASL_fm = $fm
else if(! $?ASL_fm) then
	set ASL_fm = ""
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"
			
ASL_REGISTER:

if(! -e ${SubjectHome}/ASL/Movement) then
	decho "Unable to perform ASL registration as frame alignment failed." $DebugFile
	exit 1
endif

#compute ASL to atlas registration

@ Run = 0
while($#ASL > $Run)
	@ Run++
	rm -rf ${SubjectHome}/Anatomical/Volume/asl${Run}_ref
	mkdir ${SubjectHome}/Anatomical/Volume/asl${Run}_ref
	pushd ${SubjectHome}/Anatomical/Volume/asl${Run}_ref

		#extract the first frame of the ASL run to act as the ASL reference
		extract_frame_4dfp ${ScratchFolder}/${patid}/ASL_temp/asl${Run}/asl${Run}_upck_xr3d 1 -o${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}
		if($status) exit 1

		niftigz_4dfp -n ${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]} ${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}
		if($status) exit 1
		
		#this script computes the registration from epi/asl -> T1 as well as doing the field map generation and distortion correction
		pushd $SubjectHome
			$PP_SCRIPTS/Registration/ComputeDistortionCorrection.csh $1 $2 asl${Run} $ASL_dwell[$Run] "${ASL_ped[$Run]}" "$ASL_fm" "$ASL_FieldMapping" "$ASL_Reg_Target" $ASL_delta
			if($status) exit 1
		popd
	
		if($day1_path == "" || $day1_patid == "") then
			set Target_Path = ${SubjectHome}/Anatomical/Volume
			set Target_Patid = ${patid}
		else
			set Target_Path = ${day1_path}/Anatomical/Volume
			set Target_Patid = ${day1_patid}
		endif
		
		if($NonLinear) then	
			if($ASL_FieldMapping == "6dof" || $ASL_FieldMapping == "none" || $ASL_FieldMapping == "") then
				#just has a affine transform to the T1
				convertwarp -r ${RegTarget}_${FinalResTrailer} --premat=${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_unwarped_${ASL_ped[$Run]}.mat --warp2=${Target_Path}/${ASL_Reg_Target}/${Target_Patid}_${ASL_Reg_Target}_warpfield_111.nii.gz -o ${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}_to_${AtlasName}_warp
			else
				convertwarp -r ${RegTarget}_${FinalResTrailer} --warp1=${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_unwarped_${ASL_ped[$Run]}_warp.nii.gz --warp2=${Target_Path}/${ASL_Reg_Target}/${Target_Patid}_${ASL_Reg_Target}_warpfield_111.nii.gz -o ${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}_to_${AtlasName}_warp
			endif
			
			if($status) exit 1
			set out_trailer = "_fnirt"
			
		else if($target != "" && ! $NonLinear) then
			if($ASL_FieldMapping == "6dof" || $ASL_FieldMapping == "none" || $ASL_FieldMapping == "") then
				#just has a affine transform to the T1 -> atlas
				convertwarp -r ${RegTarget}_${FinalResTrailer} --premat=${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_unwarped_${ASL_ped[$Run]}.mat --postmat=${Target_Path}/${ASL_Reg_Target}/${Target_Patid}_${ASL_Reg_Target}_to_${AtlasName}.mat -o ${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}_to_${AtlasName}_warp
			else
				convertwarp -r ${RegTarget}_${FinalResTrailer} --warp1=${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_unwarped_${ASL_ped[$Run]}_warp.nii.gz --postmat=${Target_Path}/${ASL_Reg_Target}/${Target_Patid}_${ASL_Reg_Target}_to_${AtlasName}.mat -o ${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}_to_${AtlasName}_warp
			endif
			if($status) exit 1
			
			set out_trailer = ""
		else
			if($ASL_FieldMapping == "6dof" || $ASL_FieldMapping == "none" || $ASL_FieldMapping == "") then
				#just has a affine transform to the T1
				convertwarp -r ${RegTarget}_${FinalResTrailer} --premat=${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_unwarped_${ASL_ped[$Run]}.mat -o ${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}_to_${AtlasName}_warp
			else
				convertwarp -r ${RegTarget}_${FinalResTrailer} --warp1=${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_unwarped_${ASL_ped[$Run]}_warp.nii.gz -o ${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}_to_${AtlasName}_warp
			endif
			if($status) exit 1
			
			set out_trailer = ""
		endif

		echo $cwd
		
		set Warpfield = ${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}_to_${AtlasName}_warp
		set WarpReference = ${RegTarget}_${FinalResTrailer}
		$FSLBIN/applywarp -i ${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]} -r ${WarpReference} -w ${Warpfield} -o ${patid}_asl${Run}_ref_${ASL_ped[${Run}]}_${FinalResTrailer}${out_trailer} --interp=spline
		if ($status) exit $status
		
		#clean up files
		rm ${patid}_*.4dfp.* `basename $ASL_Reg_Target`
	popd

end

#ASL MODULE
ASL_RESAMPLE:
mkdir ${SubjectHome}/ASL/Volume

pushd $ScratchFolder/${patid}/ASL_temp
	@ Run = 0
	while($#ASL > $Run)
		@ Run++
		
		set Warpfield = ${SubjectHome}/Anatomical/Volume/FieldMapping_asl${Run}/${patid}_asl${Run}_ref_distorted_${ASL_ped[$Run]}_to_${AtlasName}_warp
		
		pushd asl${Run}

			######################################################################
			# get a nifti volume for each frame post frame alignment and debanding
			######################################################################
			set epi = asl${Run}_upck
			$RELEASE/niftigz_4dfp -n $epi $epi
			if ($status) exit $status

			$FSLDIR/bin/fslsplit $epi $epi -t

			set FrameOrder = ()
			
			@ i = 0; echo | awk '{printf ("Resampling frame:")}'
			@ NumVols = `fslval $epi dim4`
			while ( $i <  $NumVols)
				set padded = `printf "%04i" ${i}`
				@ j = $i + 1
				echo $j | awk '{printf (" %d", $1)}'
				#######################
				# extract xr3d.mat file
				#######################
				grep -x -A4 "t4 frame $j" ${SubjectHome}/ASL/Movement/${epi}_xr3d.mat | tail -4 >! ${epi}_tmp_t4
				grep -x -A6 "t4 frame $j" ${SubjectHome}/ASL/Movement/${epi}_xr3d.mat | tail -1 >> ${epi}_tmp_t4
				########################################
				# run affine convert on extracted matrix
				########################################
				gunzip -f ${epi}$padded.nii.gz

				$RELEASE/aff_conv xf $epi $epi ${epi}_tmp_t4 ${epi}$padded ${epi}$padded ${epi}_tmp.mat > /dev/null
				if ($status) exit $status
				#######################################
				# apply all transformations in one step
				#######################################

				#need to convert the distortion and nonlinear warps so they are a single warp as well as
				#apply the movement correction and linear atlas registration
				#combine the movement correction, distortion correction, and linear atlas warp

				$FSLBIN/applywarp --ref=${WarpReference} --premat=${epi}_tmp.mat --warp=${Warpfield} --in=${epi}${padded} --out=${epi}_on_${RegTarget:t}${padded}_${FinalResolution} --interp=spline
				if ($status) exit $status
				set FrameOrder = ($FrameOrder ${epi}_on_${RegTarget:t}${padded}_${FinalResolution})
				
				rm -f movement_dist_linatl_nonlin_warp.nii*

				#smooth the M0/PD image by 5mm
				if($j == 1) then
					#sigma is 2.12332257516562 for 5mm
# 					
					fslmaths ${epi}_on_${RegTarget:t}${padded}_${FinalResolution} -kernel gauss 2.12332257516562 -fmean ${epi}_on_${RegTarget:t}${padded}_${FinalResolution}
					if($status) exit 1
					
				endif
				@ i++		# next frame
			end
		################################################################
		# merge the split volumes and then do 4d intensity normalization
		################################################################
			$FSLBIN/fslmerge -t ${epi}_xr3d_dc_atl $FrameOrder
			if ($status) exit $status

		#####################################################
		# convert final result back to 4dfp and then clean up
		#####################################################
			$RELEASE/niftigz_4dfp -4 ${epi}_xr3d_dc_atl ${epi}_xr3d_dc_atl
			if ($status) exit $status

			$RELEASE/ifh2hdr -r2000 ${epi}_xr3d_dc_atl
			if ($status) exit $status

			$RELEASE/set_undefined_4dfp ${epi}_xr3d_dc_atl # set undefined voxels (lost by passage through NIfTI) to 1.e-37
			if ($status) exit $status

			rm -f ${epi}.nii* ${epi}????.nii* ${epi}_on_${RegTarget:t}????.nii* ${epi}_tmp.mat* ${epi}_tmp_t4* asl${Run}.4dfp.* # asl${Run}_upck.4dfp.* #  asl${Run}_upck_faln.4dfp.* asl${Run}_upck_faln.4dfp.*

		popd
	end
	echo "Finished one_step_resample"
	####################################################################
	# remake single resampled atlas space ASL volumetric timeseries
	####################################################################

	@ Run = 0
	while($#ASL > $Run)
		@ Run++
		niftigz_4dfp -n asl${Run}/asl${Run}_upck_xr3d_dc_atl ${SubjectHome}/ASL/Volume/${patid}_asl${Run}_upck_xr3d_dc_atl
	end

popd

#Skip for now
$PP_SCRIPTS/ASL/Compute_CBF.csh $1 $2 $cwd
exit 0
