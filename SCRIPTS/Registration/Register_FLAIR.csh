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

if(! $?DebugFile) then
	set DebugFile = ${cwd}/$0:t
	ftouch $DebugFile
endif

set SubjectHome = $cwd
set AtlasName = $target:t

if(! $?flair ) then
	decho "Warning: The flair variable does not exist in $1. It denotes a FLAIR image you are wanting to register, but is not required." $DebugFile
	exit 0
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

rm -r $SubjectHome/Anatomical/Volume/FLAIR
mkdir -p $SubjectHome/Anatomical/Volume/FLAIR
pushd $SubjectHome/Anatomical/Volume/FLAIR

	if($#flair > 1) then
		#register all the FLAIR's to the first one and average
		set Target_FLAIR = $flair[1]
		set FLAIR_List = ()

		foreach FLAIR($flair)
			flirt -in ${SubjectHome}/dicom/$FLAIR -ref ${SubjectHome}/dicom/$Target_FLAIR -out $FLAIR:r:r_${Target_FLAIR} -dof 6 -interp spline
			if($status) then
				decho "Unable to register $FLAIR to $Target_T1" $DebugFile
				exit 1
			endif

			set FLAIR_List = ($FLAIR_List $FLAIR:r:r_${Target_FLAIR})
		end

		fslmerge -t FLAIR_stack $FLAIR_List
		if($status) then
			decho "Unable to stack registered FLAIR's" $DebugFile
			exit 1
		endif

		fslmaths FLAIR_stack -Tmean $patid"_FLAIR_temp"
		if($status) then
			decho "Unable to average registered FLAIR stack." $DebugFile
			exit 1
		endif

		rm $FLAIR_List FLAIR_stack.nii.gz

		niftigz_4dfp -4 $patid"_FLAIR_temp" $patid"_FLAIR_temp"

		if($status) exit 1

		rm $patid"_FLAIR_temp"

	else if( -e $SubjectHome/dicom/$flair[1]) then
		if($flair[1]:e == "gz") then
			$RELEASE/niftigz_4dfp -4 $SubjectHome/dicom/$flair[1] $patid"_FLAIR_temp"
		else
			$RELEASE/nifti_4dfp -4 $SubjectHome/dicom/$flair[1] $patid"_FLAIR_temp"
		endif
	else
		$RELEASE/dcm_to_4dfp -b $patid"_FLAIR_temp" $SubjectHome/dicom/$dcmroot.$flair.*
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
			echo "ERROR: UNKNOWN FLAIR ORIENTATION!!!"
			exit 1
			breaksw
	endsw

	niftigz_4dfp -n $InputAnat ${patid}"_FLAIR"
	if($status) exit 1

	rm *_temp.* *T.*

	bet ${patid}"_FLAIR" ${patid}"_FLAIR_brain" -R -f 0.3
	if($status) exit

	#extract the brain from the T1
 	fast -B -b -I 10 -l 10 -g -t 2 ${patid}_FLAIR_brain.nii.gz
 	if($status) then
 		decho "Failed to complete bias correction on FLAIR."
 		exit 1
 	endif

 	fslmaths ${patid}"_FLAIR" -div ${patid}_FLAIR_brain_bias ${patid}"_FLAIR"
 	if($status) exit 1
 	
	$FSLBIN/flirt -in ${patid}"_FLAIR" -ref ../T1/${patid}_T1.nii.gz -omat ${patid}_FLAIR_to_${patid}_T1.mat -out ${patid}_FLAIR_to_${patid}_T1 -dof 6 -interp spline
	if($status) then
		decho "Failed to linearly register FLAIR to T1" $DebugFile
		exit 1
	endif

	#see if we want to check how far a voxel displaces
	if($MaximumRegDisplacement != 0) then
		flirt -in ../T1/${patid}_T1 -ref ${patid}"_FLAIR" -omat ${patid}"_FLAIR"_to_${patid}_T1_rev.mat -dof 6 -cost mutualinfo -searchcost mutualinfo
		if($status) exit 1

		set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_FLAIR" ../T1/${patid}_T1 ${patid}"_FLAIR"_to_${patid}_T1.mat ${patid}"_FLAIR"_to_${patid}_T1_rev.mat 0 50 0`
		decho "2 way registration displacement: $Displacement" registration_displacement.txt

		if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_FLAIR" ../T1/${patid}_T1 ${patid}"_FLAIR"_to_${patid}_T1.mat ${patid}"_FLAIR"_to_${patid}_T1_rev.mat 0 50 0 $MaximumRegDisplacement`) then
			decho "	Error: Registration from FLAIR to T1 and T1 to FLAIR has a displacement of "$Displacement $DebugFile
			exit 1
		endif
	endif

	#combine FLAIR -> T1 -> Atlas if we specified an atlas target
	if($target != "") then
		convert_xfm -omat ${patid}_FLAIR_to_${AtlasName}.mat -concat ../T1/${patid}_T1_to_${AtlasName}.mat ${patid}_FLAIR_to_${patid}_T1.mat
		if($status) exit 1

		flirt -in ${patid}_FLAIR -ref $target -out ${patid}_FLAIR_111 -init ${patid}_FLAIR_to_${AtlasName}.mat -applyxfm -interp spline
		if($status) exit 1

		flirt -in ${patid}_FLAIR_111 -ref $target -out ${patid}_FLAIR_${FinalResTrailer} -applyisoxfm $FinalResolution -interp spline
		if($status) exit 1
	endif
exit 0
