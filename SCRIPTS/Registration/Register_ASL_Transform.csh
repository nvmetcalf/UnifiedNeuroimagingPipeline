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

if(! $?day1_path) then
	set day1_path = ""
	set day1_patid = ""
else
	set day1_patid = $day1_path:t
endif

if($target != "") then
	set AtlasName = $target:t
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

if(! $?ASL_FinalResolution) then
	set FinalResolution = 3
else
	set FinalResolution = $ASL_FinalResolution
endif

if($FinalResolution == "0") then
	set FinalResTrailer = ""
else
	set FinalResTrailer = "_${FinalResolution}${FinalResolution}${FinalResolution}"
endif
ASL_REGISTER:

if(! -e ${SubjectHome}/ASL/Movement) then
	echo "SCRIPT: $0 : 00003 : Unable to perform ASL registration as frame alignment failed."
	exit 1
endif

#this script computes the registration from epi/asl -> T1 as well as doing the field map generation and distortion correction
pushd $SubjectHome
	$PP_SCRIPTS/Registration/ComputeDistortionCorrection.csh $1 $2 -fm_suffix "ASL" -dwell "$ASL_dwell" -ped "$ASL_ped" -fm "$ASL_fm" -fm_method "$ASL_FieldMapping" -target "$ASL_Reg_Target" -delta "$ASL_delta" -images "$ASL" -reg_method $ASL_CostFunction -final_res $ASL_FinalResolution
	if($status) then
		echo "SCRIPT: $0 : 00004 : unable to compute distortion corrected registration."
		exit 1
	endif
popd


#ASL MODULE
ASL_RESAMPLE:
mkdir ${SubjectHome}/ASL/Volume

pushd $ScratchFolder/${patid}/ASL_temp
	@ Run = 0
	while($#ASL > $Run)
		@ Run++
		set Warpfield = ${SubjectHome}/Anatomical/Volume/ASL_ref/${patid}_ASL_ref_${ASL_ped[$Run]}_to_${AtlasName}_warp

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

				applywarp --ref=${RegTarget}${FinalResTrailer} --premat=${epi}_tmp.mat --warp=${Warpfield} --in=${epi}${padded} --out=${epi}_on_${AtlasName}${padded}_${FinalResolution} #--interp=spline
				if ($status) exit $status
				set FrameOrder = ($FrameOrder ${epi}_on_${AtlasName}${padded}_${FinalResolution})

				rm -f movement_dist_linatl_nonlin_warp.nii*

				#smooth the M0/PD image by 5mm
				if($j == 1) then
					#sigma is 2.12332257516562 for 5mm
#
					fslmaths ${epi}_on_${AtlasName}${padded}_${FinalResolution} -kernel gauss 2.12332257516562 -fmean ${epi}_on_${AtlasName}${padded}_${FinalResolution}
					if($status) exit 1

				endif
				@ i++		# next frame
			end
		################################################################
		# merge the split volumes and then do 4d intensity normalization
		################################################################
			fslmerge -t ${epi}_xr3d_dc_atl $FrameOrder
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

			rm -f ${epi}.nii* ${epi}????.nii* ${epi}_on_${AtlasName}????.nii* ${epi}_tmp.mat* ${epi}_tmp_t4* asl${Run}.4dfp.* # asl${Run}_upck.4dfp.* #  asl${Run}_upck_faln.4dfp.* asl${Run}_upck_faln.4dfp.*

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

$PP_SCRIPTS/ASL/Compute_CBF_Tyler.csh $1 $2 $cwd
exit 0
