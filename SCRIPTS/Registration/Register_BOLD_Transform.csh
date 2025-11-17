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

if(! $?BOLD_FinalResolution) then
	set FinalResolution = 3
else
	set FinalResolution = $BOLD_FinalResolution
endif

if($FinalResolution == "0") then
	set FinalResTrailer = ""
else
	set FinalResTrailer = "_${FinalResolution}${FinalResolution}${FinalResolution}"
endif

if(! $?RegisterEcho) then
	set RegisterEcho = 1
endif

if(! $?BOLD_Reg_Target && $?tse) then
	set BOLD_Reg_Target = T2
else if(! $?BOLD_Reg_Target) then
	set BOLD_Reg_Target = T1
endif

if(! $?BOLD_fm && $?fm) then
	set BOLD_fm = ($fm)
else if(! $?BOLD_fm) then
	set BOLD_fm = ""
endif
#make out distorted bold -> T1 -> Atlas warp
set peds = (`echo $BOLD_ped | tr " " "\n" | sort | uniq`)

#goto SKIP_RESAMPLE
#compute BOLD_ref to atlas registration
pushd ${SubjectHome}/Anatomical/Volume/BOLD_ref

	foreach ped($peds)
		if(-e ${patid}_BOLD_ref_distorted_${ped}.4dfp.img) then
			$RELEASE/niftigz_4dfp -4 ${patid}_BOLD_ref_distorted_${ped} ${patid}_BOLD_ref_distorted_${ped}
			if($status) exit 1

			if(-e ${patid}_BOLD_ref_distorted_${ped}.nii.gz) then
				gunzip -f ${patid}_BOLD_ref_distorted_${ped}.nii.gz
			endif
		endif
	end

	if($day1_patid != "" || $day1_path != "") then
		#do cross day registration by registering to the first sessions BOLD reference

		rm -r ${SubjectHome}/Anatomical/Volume/FieldMapping_BOLD
		mkdir -p ${SubjectHome}/Anatomical/Volume/FieldMapping_BOLD

		foreach direction($peds)
			set BOLD_Target = $day1_path/Anatomical/Volume/BOLD_ref/${day1_patid}_BOLD_ref_distorted_${direction}

			flirt -in ${patid}_BOLD_ref_distorted_${ped}.nii.gz -ref $BOLD_Target -out ${patid}_BOLD_ref_distorted_${ped}_to_${day1_patid}_BOLD_ref_distorted_${direction} -dof 6 -interp spline -omat ${patid}_BOLD_ref_distorted_to_${day1_patid}_BOLD_ref_distorted_${direction}.mat
			if($status) exit 1

			if($target != "") then
				convertwarp -r ${target}${FinalResTrailer} --premat=${patid}_BOLD_ref_distorted_to_${day1_patid}_BOLD_ref_distorted_${direction}.mat -w ${day1_path}/Anatomical/Volume/FieldMapping_BOLD/${day1_patid}_BOLD_ref_${direction}_to_${AtlasName}_warp -o ${SubjectHome}/Anatomical/Volume/FieldMapping_BOLD/${patid}_BOLD_ref_${direction}_to_${AtlasName}_warp
				if($status) exit 1
			else
				convertwarp -r ${RegTarget}${FinalResTrailer} --premat=${patid}_BOLD_ref_distorted_to_${day1_patid}_BOLD_ref_distorted_${direction}.mat -w ${day1_path}/Anatomical/Volume/FieldMapping_BOLD/${day1_patid}_BOLD_ref_${direction}_to_${AtlasName}_warp -o ${SubjectHome}/Anatomical/Volume/FieldMapping_BOLD/${patid}_BOLD_ref_${direction}_to_${AtlasName}_warp
				if($status) exit 1
			endif

		end
#
# 		if(`ls ${day1_path}/Anatomical/Volume/T1/*fnirt*` != "") then
# 			set out_trailer = "_fnirt"
# 		else
# 			set out_trailer = ""
# 		endif
	else
		#this is a first session or a single session
		pushd $SubjectHome
			$PP_SCRIPTS/Registration/ComputeDistortionCorrection.csh $1 $2 -fm_suffix "BOLD" -dwell  "$BOLD_dwell" -ped "$BOLD_ped" -fm "$BOLD_fm" -fm_method "$BOLD_FieldMapping" -target "$BOLD_Reg_Target" -delta $BOLD_delta -images "$BOLD" -reg_method $BOLD_CostFunction -final_res $BOLD_FinalResolution
			if($status) then
				echo "SCRIPT: $0 : 00003 : unable to compute distortion corrected registration."
				exit 1
			endif
		popd
	endif

# 	set dirs_to_merge = ()
# 	#create a test of the BOLD_ref warp for QC
# 	foreach direction($peds)
# 		applywarp -i ${patid}_BOLD_ref_distorted_${direction} -r ${RegTarget}${FinalResTrailer} -w ${SubjectHome}/Anatomical/Volume/FieldMapping_BOLD/${patid}_BOLD_ref_${direction}_to_${AtlasName}_warp -o ${patid}_BOLD_ref_${direction}${FinalResTrailer} --interp=spline
# 		if ($status) then
# 			echo "SCRIPT: $0 : 00004 : unable to transform $direction."
# 			exit $status
# 		endif
# 		set dirs_to_merge = ($dirs_to_merge ${patid}_BOLD_ref_${direction}${FinalResTrailer})
# 	end
#
# 	if($#dirs_to_merge) then
# 		fslmerge -t all_dirs ${dirs_to_merge}
# 		if ($status) exit $status
#
# 		fslmaths all_dirs -Tmean ${patid}_BOLD_ref${FinalResTrailer}.nii.gz
# 		if ($status) exit $status
# 	else
# 		cp $dirs_to_merge ${patid}_BOLD_ref${FinalResTrailer}.nii.gz
# 		if ($status) exit $status
# 	endif

	#clean up files
	rm -f ${patid}_*.4dfp.* all_dirs*
popd

if( ! $?BOLD || ! $?RunIndex) then
	echo "No BOLD scans detected, skipping."
	exit 0
endif

#################################
# one step resample unwarped fMRI
#################################

pushd $ScratchFolder/${patid}/BOLD_temp

	foreach Run($RunIndex)
		pushd bold${Run}

			set FrameOrder = ()

			if($?ME_ScanSets) then
				#find the first echo (used for xr3d)
				# then set it as the xr3d target.
				@ k = 1
				set ME_echo = ()
				while ($k <= $#ME_ScanSets)

					set ME_set = (`echo $ME_ScanSets[$k] | sed -r 's/,/ /g'`)

					#search the current multi-echo set for the bold run we are on
					foreach Echo($ME_set)
						if($Echo == $Run) then	#found it, so use the first echo's xr3d
							set ME_echo = $k
							break
						endif
					end

					if($#ME_echo > 0) then
						break
					endif

					@ k++
				end
				set target_epi = bold${ME_set[$RegisterEcho]}_upck_faln_dbnd
			else
				#non-multiecho
				set target_epi = bold${Run}_upck_faln_dbnd
			endif
			######################################################################
			# get a nifti volume for each frame post frame alignment and debanding
			######################################################################
			set epi = bold${Run}_upck_faln_dbnd
			$RELEASE/niftigz_4dfp -n $epi $epi
			if ($status) exit $status

			$FSLDIR/bin/fslsplit $epi $epi -t

			@ i = 0; echo | awk '{printf ("Resampling frame:")}'
			while ( $i < `fslval $epi dim4` )
				set padded = `printf "%04i" ${i}`
				@ j = $i + 1
				echo $j | awk '{printf (" %d", $1)}'
				#######################
				# extract xr3d.mat file
				#######################
				grep -x -A4 "t4 frame $j" ${SubjectHome}/Functional/Movement/${target_epi}_xr3d.mat | tail -4 >! ${epi}_tmp_t4
				grep -x -A6 "t4 frame $j" ${SubjectHome}/Functional/Movement/${target_epi}_xr3d.mat | tail -1 >> ${epi}_tmp_t4
				########################################
				# run affine convert on extracted matrix
				########################################
				gunzip -f ${epi}$padded.nii.gz

				$RELEASE/aff_conv xf $epi $epi ${epi}_tmp_t4 ${epi}$padded ${epi}$padded ${epi}_tmp.mat
				if ($status) then
					echo "SCRIPT: $0 : 00005 : unable to convert t4 matrix to fsl matrix."
					exit $status
				endif
				#######################################
				# apply all transformations in one step
				#######################################

				#premat is the xr3d -> boldref -> t1
				#warp is the t1 -> nonlinear atlas warp
				applywarp --ref=${RegTarget}${FinalResTrailer} --premat=${epi}_tmp.mat --warp=${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${BOLD_ped[$Run]}_to_${AtlasName}_warp --in=${epi}$padded --out=${epi}_on_${RegTarget:t}${padded}_${FinalResolution} #--interp=spline
				if ($status) exit $status

				set FrameOrder = ($FrameOrder ${epi}_on_${RegTarget:t}${padded}_${FinalResolution})

				rm -f movement_dist_linatl_nonlin_warp.nii*

				@ i++		# next frame
			end
		################################################################
		# merge the split volumes and then do 4d intensity normalization
		################################################################
			fslmerge -t ${epi}_xr3d_dc_atl.nii.gz $FrameOrder
			if ($status) exit $status

			niftigz_4dfp -4 ${epi}_xr3d_dc_atl ${epi}_xr3d_dc_atl
			if($status) exit 1

			rm -f ${epi}*.nii* ${epi}_on_${RegTarget:t}*_${FinalResolution}.nii* ${epi}????.nii* ${epi}_on_${RegTarget:t}????.nii* ${epi}_tmp.mat* ${epi}_tmp_t4* bold${Run}_upck_faln.4dfp.* bold${Run}_upck.4dfp.* bold${Run}.4dfp.* #bold${Run}_upck_faln_dbnd.4dfp.*

		popd
	end
	echo "Finished one_step_resample"

	SKIP_RESAMPLE:
	#pushd $ScratchFolder/${patid}/BOLD_temp

	#if we have multiecho data, we need to make a new combined bold run for
	# each echo set
	if($?ME_ScanSets) then
		if (! ${?ME_reg}) @ ME_reg = 0

		rm -r me_source_bold
		mkdir me_source_bold

		#need to reset the runs we will be fully processing to the multiecho timeseries
		set RunIndex = ()

		#need to remake this list
		rm $patid"_func_vols.lst"
		touch $patid"_func_vols.lst"

		@ k = 1
		while ($k <= $#ME_ScanSets)
			rm -r me_$k
			mkdir me_$k

			pushd me_$k
				#put together the runs for the current multiecho
				set curr_me_indices = (`echo $ME_ScanSets[$k] | sed -r 's/,/ /g'`)

				set ScanList = ()
				foreach Index($curr_me_indices)
					set ScanList = ($ScanList $ScratchFolder/${patid}/BOLD_temp/bold${Index}/bold${Index}"_upck_faln_dbnd_xr3d_dc_atl.4dfp.img")
				end

				echo	MEfmri_4dfp -E$#BOLD_TE -T $BOLD_TE $ScanList -r$ME_reg -obold${k}_upck_faln_dbnd_xr3d_dc_atl -e30
					MEfmri_4dfp -E$#BOLD_TE -T $BOLD_TE $ScanList -r$ME_reg -obold${k}_upck_faln_dbnd_xr3d_dc_atl -e30
					if ($status) exit $status

				normalize_4dfp.csh bold${k}_upck_faln_dbnd_xr3d_dc_atl_Swgt -n4
				if ($status) exit $status

				niftigz_4dfp -n bold${k}_upck_faln_dbnd_xr3d_dc_atl_Swgt_norm bold${k}_upck_faln_dbnd_xr3d_dc_atl
				if($status) exit 1

				niftigz_4dfp -4 bold${k}_upck_faln_dbnd_xr3d_dc_atl bold${k}_upck_faln_dbnd_xr3d_dc_atl
				if($status) exit 1
			popd

			#move the bolds used to make the single ME timeseries out of the way
			foreach Index($curr_me_indices)
				mv bold${Index} me_source_bold/
			end

			mv me_$k bold$k

			set RunIndex = ($RunIndex $k)
			@ k++
		end
	else
		foreach Run($RunIndex)
			cd bold$Run
				$RELEASE/normalize_4dfp.csh bold${Run}_upck_faln_dbnd_xr3d_dc_atl -n4
				if ($status) exit $status

				niftigz_4dfp -n bold${Run}_upck_faln_dbnd_xr3d_dc_atl_norm bold${Run}_upck_faln_dbnd_xr3d_dc_atl
				if($status) exit 1

				niftigz_4dfp -4 bold${Run}_upck_faln_dbnd_xr3d_dc_atl bold${Run}_upck_faln_dbnd_xr3d_dc_atl
				if($status) exit 1
			cd ..
		end
	endif

	####################################################################
	# remake single resampled atlas space fMRI volumetric timeseries
	####################################################################

	if (-e ${patid}_upck_faln_dbnd_xr3d_dc_atl.lst) rm -f ${patid}_upck_faln_dbnd_xr3d_dc_atl.lst
	touch ${patid}_upck_faln_dbnd_xr3d_dc_atl.lst

	set FileList = ()
	foreach Run ($RunIndex)
		echo bold${Run}/bold${Run}_upck_faln_dbnd_xr3d_dc_atl.4dfp.img >> ${patid}_upck_faln_dbnd_xr3d_dc_atl.lst
		set FileList = ($FileList bold${Run}/bold${Run}_upck_faln_dbnd_xr3d_dc_atl.nii.gz)
	end

	if(! -e ${SubjectHome}/Functional/Volume) mkdir ${SubjectHome}/Functional/Volume

	fslmerge -t ${SubjectHome}/Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz $FileList
	if($status) then
		echo "SCRIPT: $0 : 00006 : unable to merge runs."
		exit 1
	endif
	$RELEASE/conc_4dfp ${patid}_upck_faln_dbnd_xr3d_dc_atl.conc -l${patid}_upck_faln_dbnd_xr3d_dc_atl.lst
	if ($status) exit $status

	if(! -e ${SubjectHome}/Functional/TemporalMask) mkdir ${SubjectHome}/Functional/TemporalMask

	echo `conc2format ${patid}_upck_faln_dbnd_xr3d_dc_atl.conc $skip` >! ${SubjectHome}/Functional/TemporalMask/${patid}_AllVolumes.format
	if ($status) exit $status

	find . -name "*_upck.4dfp.*" -exec rm {} \;
	find . -name "*_upck_faln.4dfp.*" -exec rm {} \;
	find . -name "*_upck_faln_dbnd.4dfp.*" -exec rm {} \;
	find . -name "*_upck_faln_dbnd_xr3d.4dfp.*" -exec rm {} \;
	find . -name "*_upck_faln_dbnd_xr3d_dc_atl_norm.4dfp.*" -exec rm {} \;
popd

exit 0
