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

if(! $?FLAIR ) then
	decho "Warning: The FLAIR variable does not exist in $1. It denotes a FLAIR image you are wanting to register, but is not required."
	exit 0
endif

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

echo "Detected the following final resolutions: $FinalResolutions"

rm -r $SubjectHome/Anatomical/Volume/FLAIR
mkdir -p $SubjectHome/Anatomical/Volume/FLAIR
pushd $SubjectHome/Anatomical/Volume/FLAIR

	if($#FLAIR > 1) then
		#register all the FLAIR's to the first one and average
		set Target_FLAIR = $FLAIR[1]
		set FLAIR_List = ()

		foreach FLAIR($FLAIR)
			flirt -in ${SubjectHome}/dicom/$FLAIR -ref ${SubjectHome}/dicom/$Target_FLAIR -out $FLAIR:r:r_${Target_FLAIR} -dof 6 -interp spline
			if($status) then
				echo "SCRIPT: $0 : 00003 : Unable to register $FLAIR to $Target_T1"
				exit 1
			endif

			set FLAIR_List = ($FLAIR_List $FLAIR:r:r_${Target_FLAIR})
		end

		fslmerge -t FLAIR_stack $FLAIR_List
		if($status) then
			echo "SCRIPT: $0 : 00004 : Unable to stack registered FLAIR's"
			exit 1
		endif

		fslmaths FLAIR_stack -Tmean $patid"_FLAIR_temp"
		if($status) then
			echo "SCRIPT: $0 : 00005 : Unable to average registered FLAIR stack."
			exit 1
		endif

		rm $FLAIR_List FLAIR_stack.nii.gz

		niftigz_4dfp -4 $patid"_FLAIR_temp" $patid"_FLAIR_temp"

		if($status) exit 1

		rm $patid"_FLAIR_temp"

	else if( -e $SubjectHome/dicom/$FLAIR[1]) then
		if($FLAIR[1]:e == "gz") then
			$RELEASE/niftigz_4dfp -4 $SubjectHome/dicom/$FLAIR[1] $patid"_FLAIR_temp"
		else
			$RELEASE/nifti_4dfp -4 $SubjectHome/dicom/$FLAIR[1] $patid"_FLAIR_temp"
		endif
	else
		$RELEASE/dcm_to_4dfp -b $patid"_FLAIR_temp" $SubjectHome/dicom/$dcmroot.$FLAIR.*
	endif
	if ($status) exit $status

	switch(`grep orientation $patid"_FLAIR_temp".4dfp.ifh | awk '{print$3}'`)
		case 2:
			echo "FLAIR already transverse"
			set InputAnat = $patid"_FLAIR_temp"
			breaksw
		case 3:
			echo "FLAIR is coronal, transforming to transverse."
			$RELEASE/C2T_4dfp ${patid}_FLAIR_temp ${patid}_FLAIRT
			if($status) exit 1
			set InputAnat = $patid"_FLAIRT"
			breaksw
		case 4:
			echo "FLAIR is sagital, transforming to transverse."
			$RELEASE/S2T_4dfp ${patid}"_FLAIR_temp" ${patid}"_FLAIRT"
			set InputAnat = $patid"_FLAIRT"
			if($status) exit 1
			breaksw
		default:
			echo "SCRIPT: $0 : 00005 : ERROR: UNKNOWN FLAIR ORIENTATION"
			exit 1
			breaksw
	endsw

	niftigz_4dfp -n $InputAnat ${patid}"_FLAIR"
	if($status) exit 1

	rm *_temp.* *T.*

	bet ${patid}"_FLAIR" ${patid}"_FLAIR_brain" -R -f 0.3
	if($status) exit

	cp ${patid}_FLAIR.nii.gz ${patid}_FLAIR_native.nii.gz
 	if($status) exit 1

 	#extract the brain from the T1
 	fast -b -B -I 10 -l 10 -g -t 2 ${patid}_FLAIR_brain.nii.gz
 	if($status) then
 		echo "SCRIPT: $0 : 00006 : Failed to complete bias correction on FLAIR."
 		exit 1
 	endif

	niftigz_4dfp -4 ${patid}_FLAIR ${patid}_FLAIR
	if($status) exit 1

	niftigz_4dfp -4 ${patid}_FLAIR_brain_restore ${patid}_FLAIR_brain_restore
	if($status) exit 1

	extend_fast_4dfp -G ${patid}_FLAIR ${patid}_FLAIR_brain_restore ${patid}_FLAIR_bias
	if($status) exit 1

	niftigz_4dfp -n ${patid}_FLAIR_bias ${patid}_FLAIR_bias
	if($status) exit 1

 	fslmaths ${patid}_FLAIR.nii.gz -mul ${patid}_FLAIR_bias.nii.gz ${patid}_FLAIR.nii.gz
 	if($status) exit 1

	rm *.4dfp.*

 	fslmaths ${patid}"_FLAIR" -div ${patid}_FLAIR_brain_bias ${patid}"_FLAIR"
 	if($status) exit 1

	set FoundReg = 0
	foreach image(" " "_brain")
		flirt -in ${patid}"_FLAIR"${image} -ref ../T1/${patid}_T1${image} -omat ${patid}_FLAIR_to_${patid}_T1.mat -dof 6 -interp spline
		if($status) then
			echo "SCRIPT: $0 : 00007 : Failed to linearly register FLAIR to T1"
			exit 1
		endif

		#see if we want to check how far a voxel displaces
		if($MaximumRegDisplacement == 0) then
			set MaximumRegDisplacement = `fslinfo ${patid}_FLAIR.nii.gz | grep pixdim | awk '{print $2 * 1.25}' | sort -u | tail -1`
		endif

		flirt -in ../T1/${patid}_T1${image} -ref ${patid}"_FLAIR"${image} -omat ${patid}"_FLAIR"_to_${patid}_T1_rev.mat -dof 6
		if($status) exit 1

		set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_FLAIR" ../T1/${patid}_T1 ${patid}_FLAIR_to_${patid}_T1.mat ${patid}"_FLAIR"_to_${patid}_T1_rev.mat 0 50 0`

		decho "2 way registration displacement: $Displacement" registration_displacement.txt

		if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_FLAIR" ../T1/${patid}_T1 ${patid}_FLAIR_to_${patid}_T1.mat ${patid}"_FLAIR"_to_${patid}_T1_rev.mat 0 50 0 $MaximumRegDisplacement`) then
			decho "	Error: Registration from FLAIR to T1 and T1 to FLAIR has a displacement of "$Displacement
		else
			set FoundReg = 1
		endif

		if($FoundReg) then
			break
		endif
	end

	if(! $FoundReg) then
		echo "SCRIPT: $0 : 00008 : Could not register FLAIR to T1 well enough."
		exit 1
	endif

	#combine FLAIR -> T1 -> Atlas if we specified an atlas target
	if($target != "") then
		convert_xfm -omat ${patid}_FLAIR_to_${AtlasName}.mat -concat ../T1/${patid}_T1_to_${AtlasName}.mat ${patid}_FLAIR_to_${patid}_T1.mat
		if($status) exit 1

		flirt -in ${patid}_FLAIR -ref $target -out ${patid}_FLAIR_111 -init ${patid}_FLAIR_to_${AtlasName}.mat -applyxfm -interp spline
		if($status) exit 1

		foreach res($FinalResolutions)
			if($res == 0) then
				continue
			endif
			flirt -in ${patid}_FLAIR_111 -ref $target -out ${patid}_FLAIR_${res}${res}${res} -applyisoxfm ${res} -interp spline
			if($status) exit 1
		end
	else
		foreach res($FinalResolutions)
			if($res == 0) then
				continue
			endif
			flirt -in ${patid}"_FLAIR" -ref ../T1/${patid}_T1 -init ${patid}_FLAIR_to_${patid}_T1.mat -interp spline -applyisoxfm $res -out ${patid}"_FLAIR_"${res}${res}${res}
			if($status) exit 1
		end
	endif
exit 0
