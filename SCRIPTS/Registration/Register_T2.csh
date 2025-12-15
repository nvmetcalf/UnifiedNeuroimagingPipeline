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

if(! $?T2 ) then
	decho "Warning: The T2 variable does not exist in $1. It denotes a T2 image you are wanting to register, but is not required."
	exit 0
endif

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

echo "Detected the following final resolutions: $FinalResolutions"

rm -r ${SubjectHome}/Anatomical/Volume/T2
mkdir -p ${SubjectHome}/Anatomical/Volume/T2
pushd ${SubjectHome}/Anatomical/Volume/T2

	if($#T2 > 1) then
		#register all the T1's to the first one and average
		set Target_T2 = $T2[1]
		set T2_List = ()

		foreach T2($T2)
			flirt -in ${SubjectHome}/dicom/$T2 -ref ${SubjectHome}/dicom/$Target_T2 -out $T2:r:r_${Target_T2} -dof 6 -interp spline
			if($status) then
				echo "SCRIPT: $0 : 00003 : Unable to register $T2 to $Target_T2"
				exit 1
			endif

			set T2_List = ($T2_List $T2:r:r_${Target_T2})
		end

		fslmerge -t T2_stack $T2_List
		if($status) then
			echo "SCRIPT: $0 : 00004 : Unable to stack registered T2's"
			exit 1
		endif

		fslmaths T2_stack -Tmean $patid"_T2"
		if($status) then
			echo "SCRIPT: $0 : 00005 : Unable to average registered T2 stack."
			exit 1
		endif

		rm $T2_List T2_stack.nii.gz
		if($status) exit 1

		set T2_image = ${cwd}/$patid"_T2"

	else if( -e $SubjectHome/dicom/$T2[1]) then
		set T2_image = $SubjectHome/dicom/$T2[1]
	else
		echo "Unable to find T2 image."
		exit 1
	endif

	if ($status) then
		echo "SCRIPT: $0 : 00005 : image check failed."
		exit $status
	endif

	fslreorient2std $T2_image ${patid}_T2

	bet ${patid}"_T2" ${patid}"_T2_brain" -m -R -f 0.3
	if($status) exit

	#extract the brain from the T2
 	fast -b -B -I 10 -l 10 -g -t 2 ${patid}_T2_brain.nii.gz
 	if($status) then
 		echo "SCRIPT: $0 : 00007 : Failed to complete bias correction on T2."
 		exit 1
 	endif

 	cp ${patid}_T2.nii.gz ${patid}_T2_native.nii.gz
 	if($status) exit 1

	niftigz_4dfp -4 ${patid}_T2 ${patid}_T2
	if($status) exit 1

	niftigz_4dfp -4 ${patid}_T2_brain_restore ${patid}_T2_brain_restore
	if($status) exit 1

	extend_fast_4dfp -G ${patid}_T2 ${patid}_T2_brain_restore ${patid}_T2_bias
	if($status) exit 1

	niftigz_4dfp -n ${patid}_T2_bias ${patid}_T2_bias
	if($status) exit 1

 	fslmaths ${patid}_T2.nii.gz -mul ${patid}_T2_bias.nii.gz ${patid}_T2.nii.gz
 	if($status) exit 1

 	fslmaths ${patid}_T2.nii.gz -mul ${patid}_T2_brain_mask.nii.gz ${patid}_T2_brain.nii.gz
 	if($status) exit 1

 	if($MaximumRegDisplacement == 0) then
		set MaximumRegDisplacement = `fslinfo ${patid}_T2.nii.gz | grep pixdim | awk '{print $2 * 1.25}' | sort -u | tail -1`
	endif

	rm *.4dfp.*
	set FoundReg = 0
	foreach cost(mutualinfo corratio)

		foreach image(" " "_brain")
			flirt -in ${patid}"_T2"${image} -ref ../T1/${patid}_T1${image} -omat ${patid}_T2_to_${patid}_T1.mat -dof 6 -interp spline -cost $cost -searchcost $cost
			if($status) then
				echo "SCRIPT: $0 : 00008 : Failed to linearly register T2 to T1"
				exit 1
			endif

			#see if we want to check how far a voxel displaces
			if($MaximumRegDisplacement != 0) then
				flirt -in ../T1/${patid}_T1${image} -ref ${patid}"_T2"${image} -omat ${patid}"_T2"_to_${patid}_T1_rev.mat -dof 6 -cost $cost -searchcost $cost
				if($status) exit 1

				set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_T2" ../T1/${patid}_T1 ${patid}_T2_to_${patid}_T1.mat ${patid}"_T2"_to_${patid}_T1_rev.mat 0 50 0`

				decho "2 way registration displacement: $Displacement" registration_displacement.txt

				if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_T2" ../T1/${patid}_T1 ${patid}_T2_to_${patid}_T1.mat ${patid}"_T2"_to_${patid}_T1_rev.mat 0 50 0 $MaximumRegDisplacement`) then
					decho "	Error: Registration from T2 to T1 and T1 to T2 has a displacement of "$Displacement
				else
					set FoundReg = 1
				endif
			endif

			if($FoundReg) then
				break
			endif
		end
		if($FoundReg) then
			break
		endif
	end
	if(! $FoundReg) then
		echo "SCRIPT: $0 : 00009 : Could not register T2 to T1 well enough."
		exit 1
	endif
	flirt -in ${patid}"_T2" -ref ../T1/${patid}_T1_brain_restore.nii.gz -out ${patid}_T2_to_${patid}_T1 -init ${patid}_T2_to_${patid}_T1.mat -applyxfm
	if($status) exit 1

	#combine T2 -> T1 -> Atlas if we specified a target atlas
	if($target != "") then
		convert_xfm -omat ${patid}_T2_to_${AtlasName}.mat -concat ../T1/${patid}_T1_to_${AtlasName}.mat ${patid}_T2_to_${patid}_T1.mat
		if($status) exit 1

		flirt -in ${patid}"_T2" -ref $target -out ${patid}_T2_111 -init ${patid}_T2_to_${AtlasName}.mat -applyxfm -interp spline
		if($status) exit 1

		foreach res($FinalResolutions)
			if($res == 0) then
				continue
			endif

			flirt -in ${patid}_T2_111 -ref $target -out ${patid}_T2_${res}${res}${res} -applyisoxfm ${res} -interp spline
			if($status) exit 1
		end
	else
		foreach res($FinalResolutions)
			if($res == 0) then
				continue
			endif

			flirt -in ${patid}_T2_to_${patid}_T1 -ref ../T1/${patid}_T1_brain_restore.nii.gz -out ${patid}_T2_${res}${res}${res} -applyisoxfm $res -interp spline
			if($status) exit 1
		end
	endif

popd

exit 0
