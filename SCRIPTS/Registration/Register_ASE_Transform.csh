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

if(! $?ASE_FinalResolution) then
	set FinalResolution = 3
else
	set FinalResolution = $ASE_FinalResolution
endif

if(! $?ASE_Reg_Target && $?tse) then
	set ASE_Reg_Target = T2
else if(! $?ASE_Reg_Target) then
	set ASE_Reg_Target = T1
endif

if(! $?ASE_fm && $?fm) then
	set ASE_fm = $fm
else if(! $?ASE_fm) then
	set ASE_fm = ""
endif

if($FinalResolution == "0") then
	set FinalResTrailer = ""
else
	set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"
endif

ASE_REGISTER:

if(! -e ${SubjectHome}/ASE/Movement) then
	echo "SCRIPT: $0 : 00003 : Unable to perform ASE registration as frame alignment failed."
	exit 1
endif

rm -rf ${SubjectHome}/Anatomical/Volume/ASE_ref
mkdir ${SubjectHome}/Anatomical/Volume/ASE_ref
pushd ${SubjectHome}/Anatomical/Volume/ASE_ref

#compute ASE to atlas registration
#ASE is multi echo, so we only need to make a single registration. Average the first frame of each echo and compute the registration

	@ Run = 1
	while($Run <= $#ASE)
		#extract the first frame of the ASE run to act as the ASE reference
		extract_frame_4dfp ${ScratchFolder}/${patid}/ASE_temp/ase${Run}/ase${Run}_upck_xr3d 1 -oecho_${Run}
		if($status) exit 1

		niftigz_4dfp -n echo_${Run} echo_${Run}
		if($status) exit 1
		@ Run++
	end

	@ Run = $#ASE

	rm *4dfp*

	fslmerge -t ASE_STACK echo_*.nii.gz
	if($status) exit 1

	$PP_SCRIPTS/Utilities/Compute_B0_Corrections.csh ASE_STACK.nii.gz
	if($status) then
		echo "SCRIPT: $0 : 00004 : 	Could not bias correct ASE_STACK."
		exit 1
	endif

	fslmaths ASE_STACK -Tmean ${patid}_ASE_ref_distorted_${ASE_ped[$Run]}
	if($status) exit 1

	#this script computes the registration from epi/ase -> T1 as well as doing the field map generation and distortion correction
	pushd $SubjectHome
		$PP_SCRIPTS/Registration/ComputeDistortionCorrection.csh $1 $2 -fm_suffix "ASL" -dwell "$ASE_dwell" -ped "$ASE_ped" -fm "$ASE_fm" -fm_method "$ASE_FieldMapping" -target "$ASE_Reg_Target" -delta "$ASE_delta" -images "$ASE" -reg_method $ASE_CostFunction -final_res $ASE_FinalResolution
		if($status) then
			echo "SCRIPT: $0 : 00005 : cannot compute distortion corrected registration."
			exit 1
		endif
	popd

	echo $cwd

	set Warpfield = ${SubjectHome}/Anatomical/Volume/FieldMapping_ASE/${patid}_ASE_ref_distorted_${ASE_ped[$Run]}_to_${AtlasName}_warp
	set WarpReference = ${RegTarget}_${FinalResTrailer}
	applywarp -i ${patid}_ASE_ref_distorted_${ASE_ped[$Run]} -r ${WarpReference} -w ${Warpfield} -o ${patid}_ASE_ref_${ASE_ped[${Run}]}_${FinalResTrailer}${out_trailer} --interp=spline
	if($status) then
		echo "SCRIPT: $0 : 00006 : failed to apply warp to reference image."
		exit 1
	endif
	#clean up files
	rm ${patid}_*.4dfp.* `basename $ASE_Reg_Target`
popd

#ASE MODULE
ASE_RESAMPLE:
mkdir ${SubjectHome}/ASE/Volume

pushd $ScratchFolder/${patid}/ASE_temp
	@ Run = 1
	while($Run <= $#ASE)

		set Warpfield = ${SubjectHome}/Anatomical/Volume/ASE/${patid}_ASE_ref_distorted_${ASE_ped[$Run]}_to_${AtlasName}_warp

		pushd ase${Run}

			######################################################################
			# get a nifti volume for each frame post frame alignment and debanding
			######################################################################
			set epi = ase${Run}_upck
			$RELEASE/niftigz_4dfp -n $epi $epi
			if ($status) exit $status

			$FSLDIR/bin/fslsplit $epi $epi -t

			set FrameOrder = ()

			@ i = 0;
			echo | awk '{printf ("Resampling frame:")}'
			@ NumVols = `fslval $epi dim4`
			while ( $i <  $NumVols)
				set padded = `printf "%04i" ${i}`
				@ j = $i + 1
				echo $j | awk '{printf (" %d", $1)}'
				#######################
				# extract xr3d.mat file
				#######################
				grep -x -A4 "t4 frame $j" ${SubjectHome}/ASE/Movement/${epi}_xr3d.mat | tail -4 >! ${epi}_tmp_t4
				grep -x -A6 "t4 frame $j" ${SubjectHome}/ASE/Movement/${epi}_xr3d.mat | tail -1 >> ${epi}_tmp_t4
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

				applywarp --ref=${WarpReference} --premat=${epi}_tmp.mat --warp=${Warpfield} --in=${epi}${padded} --out=${epi}_on_${RegTarget:t}${padded}${FinalResolution} #--interp=spline
				if($status) then
					echo "SCRIPT: $0 : 00007 : failed to apply frame wise onestep resample warp to $epi."
					exit 1
				endif
				set FrameOrder = ($FrameOrder ${epi}_on_${RegTarget:t}${padded}${FinalResolution})
				@ i++		# next frame
			end
		################################################################
		# merge the split volumes and then do bias correction
		################################################################
			fslmerge -t ${epi}_xr3d_dc_atl $FrameOrder
			if ($status) exit $status

			$PP_SCRIPTS/Utilities/Compute_B0_Corrections.csh ${epi}_xr3d_dc_atl.nii.gz
			if($status) then
				echo "SCRIPT: $0 : 00008 : 	Could not bias correct ASE_STACK."
				exit 1
			endif

		#####################################################
		# convert final result back to 4dfp and then clean up
		#####################################################
			$RELEASE/niftigz_4dfp -4 ${epi}_xr3d_dc_atl ${epi}_xr3d_dc_atl
			if ($status) exit $status

			$RELEASE/ifh2hdr -r2000 ${epi}_xr3d_dc_atl
			if ($status) exit $status

			$RELEASE/set_undefined_4dfp ${epi}_xr3d_dc_atl # set undefined voxels (lost by passage through NIfTI) to 1.e-37
			if ($status) exit $status

			rm -f ${epi}.nii* ${epi}????.nii* ${epi}_on_${RegTarget:t}????.nii* ${epi}_tmp.mat* ${epi}_tmp_t4* ase${Run}.4dfp.* # ase${Run}_upck.4dfp.* #  ase${Run}_upck_faln.4dfp.* ase${Run}_upck_faln.4dfp.*

		popd
		@ Run++
	end
	echo "Finished one_step_resample"
	####################################################################
	# remake single resampled target space ASE volumetric timeseries
	####################################################################

	@ Run = 1
	while($Run <= $#ASE)
		niftigz_4dfp -n ase${Run}/ase${Run}_upck_xr3d_dc_atl ${SubjectHome}/ASE/Volume/${patid}_ase${Run}_upck_xr3d_dc_atl
		if($status) then
			echo "SCRIPT: $0 : 00009 : failed to convert and move final timeseries to final destination."
			exit 1
		endif
		@ Run++
	end

popd

exit 0
