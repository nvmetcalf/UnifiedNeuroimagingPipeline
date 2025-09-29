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

if(! $?T1 && -e dicom/${patid}_T1.nii.gz) then
	set T1 = ${patid}_T1.nii.gz
else if(! $?T1) then
	echo "SCRIPT: $0 : 00003 : variable T1 does not exist in $1. This variable is needed to denote the t1 image to use for registration."
	exit 1
endif

if(! $?bet_f ) then
	set bet_f = 0.3
endif

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

echo "Detected the following final resolutions: $FinalResolutions"

rm -r ${SubjectHome}/Anatomical/Volume/T1
mkdir -p ${SubjectHome}/Anatomical/Volume/T1
pushd ${SubjectHome}/Anatomical/Volume/T1
	if($#T1 > 1) then
		#register all the T1's to the first one and average
		set Target_T1 = $T1[1]
		set T1_List = ()

		foreach T1($T1)
			flirt -in ${SubjectHome}/dicom/$T1 -ref ${SubjectHome}/dicom/$Target_T1 -out $T1:r:r_${Target_T1} -dof 6 -interp spline
			if($status) then
				echo "SCRIPT: $0 : 00004 : Unable to register $T1 to $Target_T1"
				exit 1
			endif

			set T1_List = ($T1_List $T1:r:r_${Target_T1})
		end

		fslmerge -t T1_stack $T1_List
		if($status) then
			echo "SCRIPT: $0 : 00004 : Unable to stack registered T1's"
			exit 1
		endif

		fslmaths T1_stack -Tmean $patid"_T1_temp"
		if($status) then
			echo "SCRIPT: $0 : 00005 : Unable to average registered T1 stack."
			exit 1
		endif

		rm $T1_List T1_stack.nii.gz

		niftigz_4dfp -4 $patid"_T1_temp" $patid"_T1_temp"

		if($status) exit 1

		rm $patid"_T1_temp"

	else if( -e $SubjectHome/dicom/$T1[1]) then
		if($T1[1]:e == "gz") then
			$RELEASE/niftigz_4dfp -4 $SubjectHome/dicom/$T1[1] $patid"_T1_temp"
		else
			$RELEASE/nifti_4dfp -4 $SubjectHome/dicom/$T1[1] $patid"_T1_temp"
		endif
	else
		$RELEASE/dcm_to_4dfp -b $patid"_T1_temp" $SubjectHome/dicom/$dcmroot.$T1[$#T1].*
	endif
	if ($status) exit $status

	switch(`grep orientation ${patid}_T1_temp.4dfp.ifh | awk '{print$3}'`)
		case 2:
			echo "T1 already transverse"
			set InputAnat = $patid"_T1_temp"
			breaksw
		case 3:
			echo "T1 is coronal, transforming to transverse."
			$RELEASE/C2T_4dfp ${patid}_T1_temp ${patid}_T1T
			if($status) exit 1
			set InputAnat = $patid"_T1T"
			breaksw
		case 4:
			echo "T1 is sagital, transforming to transverse."
			$RELEASE/S2T_4dfp ${patid}_T1_temp ${patid}_T1T
			if($status) exit 1
			set InputAnat = $patid"_T1T"
			breaksw
		default:
			echo "SCRIPT: $0 : 00006 : ERROR: UNKNOWN T1 ORIENTATION"
			exit 1
			breaksw
	endsw

	#convert 4dfp to nifti
	$RELEASE/niftigz_4dfp -n $InputAnat ${patid}_T1
	if($status) exit 1

	rm *_temp.* *T.*

	bet ${patid}"_T1" ${patid}"_T1_brain" -R -B -f $bet_f
	if($status) then
		echo "SCRIPT: $0 : 00007 : Failed to extract T1 brain from T1 anatomy."
		exit 1
	endif

 	#extract the brain from the T1
 	fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -g -b -B ${patid}_T1_brain.nii.gz
 	if($status) then
 		echo "SCRIPT: $0 : 00008 : Failed to complete bias correction on T1."
 		exit 1
 	endif

 	cp ${patid}_T1.nii.gz ${patid}_T1_native.nii.gz
 	if($status) exit 1

	niftigz_4dfp -4 ${patid}_T1 ${patid}_T1
	if($status) exit 1

	niftigz_4dfp -4 ${patid}_T1_brain_restore ${patid}_T1_brain_restore
	if($status) exit 1

	extend_fast_4dfp -G ${patid}_T1 ${patid}_T1_brain_restore ${patid}_T1_bias
	if($status) exit 1

	niftigz_4dfp -n ${patid}_T1_bias ${patid}_T1_bias
	if($status) exit 1

 	fslmaths ${patid}_T1.nii.gz -mul ${patid}_T1_bias.nii.gz ${patid}_T1.nii.gz
 	if($status) exit 1

	rm *.4dfp.*

 	set BC_min_max = (`fslstats ${patid}_T1_brain_restore.nii.gz -n -R`)
 	if($BC_min_max[2] == 0) then
		decho "Bias correction on T1 failed to compute a proper field. Using masked T1."
		cp ${patid}_T1_brain.nii.gz ${patid}_T1_brain_restore.nii.gz
 	endif

 	if($target != "") then
		@ i = 1
		set CostFunctions = (corratio mutualinfo)
		while($i <= $#CostFunctions)

			set costfunction = $CostFunctions[$i]

			if(`diff ${patid}_T1.nii.gz ${target}.nii.gz` != "") then
				#register the T1 brain to the atlas brain
				flirt -in ${patid}_T1_brain_restore.nii.gz -ref ${target}_brain -omat ${patid}_T1_to_${AtlasName}.mat -out ${patid}_T1_111.nii -interp spline -cost $costfunction -searchcost $costfunction
				if($status) then
					echo "SCRIPT: $0 : 00009 : Failed to linearly register T1 to atlas."
					exit 1
				endif
			else
				cp $PP_SCRIPTS/Registration/identity.mat ${patid}_T1_to_${AtlasName}.mat
				flirt -in ${patid}_T1_brain_restore.nii.gz -ref ${target}_brain -out ${patid}_T1_111.nii -interp spline -init ${patid}_T1_to_${AtlasName}.mat -applyxfm
				if($status) exit 1
			endif

			flirt -in ${patid}_T1_brain_mask.nii.gz -ref ${target}_brain -init ${patid}_T1_to_${AtlasName}.mat -out ${patid}_used_voxels -interp nearestneighbour -applyxfm
			if($status) exit 1

			if(-e ${target}.nii) then
				set target_extension = "nii"
			else
				set target_extension = "nii.gz"
			endif

			rm -f temp.txt ${SubjectHome}/Anatomical/Volume/T1/${patid}_used_voxels.nii.gz

			#see if we want to check how far a voxel displaces
			if($MaximumRegDisplacement == 0) then
				set MaximumRegDisplacement = `fslinfo ${patid}_T1.nii.gz | grep pixdim | awk '{print $2 * 1.25}' | sort -u | tail -1`
			endif

			flirt -in ${target}_brain -ref ${patid}_T1_brain_restore.nii.gz -omat ${AtlasName}_to_${patid}_T1_rev.mat  -cost $costfunction -searchcost $costfunction
			if($status) exit 1

			set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_T1_brain_restore ${target} ${patid}_T1_to_${AtlasName}.mat ${AtlasName}_to_${patid}_T1_rev.mat 0 50 0`
			decho "2 way registration displacement: $Displacement" registration_displacement.txt

			if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_T1_brain_restore ${target} ${patid}_T1_to_${AtlasName}.mat ${AtlasName}_to_${patid}_T1_rev.mat 0 50 0 $MaximumRegDisplacement`) then
				if($i <= $#CostFunctions) then
					echo "SCRIPT: $0 : 00010 : 	Warning: Registration from T1 to $AtlasName and $AtlasName to T1 has a displacement of "$Displacement". Trying next cost function."
					@ i++
					continue
				else
					echo "SCRIPT: $0 : 00010 : 	Error: Registration from T1 to $AtlasName and $AtlasName to T1 has a displacement of "$Displacement
					exit 1
				endif
			endif
			break
		end
		
		flirt -in ${patid}_T1.nii.gz -ref ${target} -init ${patid}_T1_to_${AtlasName}.mat -applyxfm -out ${patid}_T1_111.nii -interp spline
		if($status) exit 1

		foreach res($FinalResolutions)
			if($res == 1) then
				continue
			endif
			flirt -in ${patid}_T1_111 -ref ${patid}_T1_111 -out ${patid}_T1_${res}${res}${res} -applyisoxfm $res -interp spline
			if($status) exit 1
		end

	else
		#just resample the T1 to our final resolutions

		decho "No Atlas target specified. All data will be left in register with the T1 and in $FinalResolutions mm iso."

		foreach res($FinalResolutions)
			if($res == 0) then
				continue
			endif
			flirt -in ${patid}_T1.nii.gz -ref ${patid}_T1.nii.gz -out ${patid}_T1_${res}${res}${res} -applyisoxfm $res -interp spline
			if($status) exit 1
		end

	endif

popd

exit 0
