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
set AtlasName = `basename $target`

if(! $?tse ) then
	decho "Warning: The tse variable does not exist in $1. It denotes a T2 image you are wanting to register, but is not required." $DebugFile
	exit 0
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

rm -r ${SubjectHome}/Anatomical/Volume/T2
mkdir -p ${SubjectHome}/Anatomical/Volume/T2
pushd ${SubjectHome}/Anatomical/Volume/T2

	if($#tse > 1) then
		#register all the T1's to the first one and average
		set Target_T2 = $tse[1]
		set T2_List = ()
		
		foreach T2($tse)
			flirt -in ${SubjectHome}/dicom/$T2 -ref ${SubjectHome}/dicom/$Target_T2 -out $T2:r:r_${Target_T2} -dof 6 -interp spline
			if($status) then
				decho "Unable to register $T2 to $Target_T2" $DebugFile
				exit 1
			endif
			
			set T2_List = ($T2_List $T2:r:r_${Target_T2})
		end
	
		fslmerge -t T2_stack $T2_List
		if($status) then
			decho "Unable to stack registered T2's" $DebugFile
			exit 1
		endif
		
		fslmaths T2_stack -Tmean $patid"_T2_temp"
		if($status) then
			decho "Unable to average registered T2 stack." $DebugFile
			exit 1
		endif
		
		rm $T2_List T2_stack.nii.gz
		
		niftigz_4dfp -4 $patid"_T2_temp" $patid"_T2_temp"
		
		if($status) exit 1
		
		rm $patid"_T2_temp"
		
	else if( -e $SubjectHome/dicom/$tse[1]) then
		if($tse[1]:e == "gz") then
			$RELEASE/niftigz_4dfp -4 $SubjectHome/dicom/$tse[1] $patid"_T2_temp"
		else
			$RELEASE/nifti_4dfp -4 $SubjectHome/dicom/$tse[1] $patid"_T2_temp"
		endif
	else
		$RELEASE/dcm_to_4dfp -b $patid"_T2_temp" $SubjectHome/dicom/$dcmroot.$tse[$#tse].*
	endif
	if ($status) exit $status

	switch(`grep orientation $patid"_T2_temp".4dfp.ifh | awk '{print$3}'`)
		case 2:
			echo "T2 already transverse"
			set InputAnat = $patid"_T2_temp"
			breaksw
		case 3:
			echo "T2 is coronal, transforming to transverse."
			$RELEASE/C2T_4dfp ${patid}_T2_temp ${patid}_T2T
			if($status) exit 1
			set InputAnat = $patid"_T2T"
			breaksw
		case 4:
			echo "T2 is sagital, transforming to transverse."
			$RELEASE/S2T_4dfp ${patid}"_T2_temp" ${patid}"_T2T"
			set InputAnat = $patid"_T2T"
			if($status) exit 1
			breaksw
		default:
			echo "ERROR: UNKNOWN T2 ORIENTATION!!!"
			exit 1
			breaksw
	endsw

	niftigz_4dfp -n $InputAnat ${patid}"_T2"
	if($status) exit 1
	
	rm *_temp.* *T.*
	
	bet ${patid}"_T2" ${patid}"_T2_brain" -m -R -f 0.3
	if($status) exit
	
	#extract the brain from the T1
 	fast -b -B -I 10 -l 10 -g -t 2 ${patid}_T2_brain.nii.gz
 	if($status) then
 		decho "Failed to complete bias correction on T2."
 		exit 1
 	endif
 	
	$FSLBIN/flirt -in ${patid}"_T2" -ref ../T1/${patid}_T1 -omat ${patid}_T2_to_${patid}_T1.mat -dof 6 -interp spline
	if($status) then
		decho "Failed to linearly register T2 to T1"
		exit 1
	endif

	#see if we want to check how far a voxel displaces
	if($MaximumRegDisplacement != 0) then
		flirt -in ../T1/${patid}_T1 -ref ${patid}"_T2" -omat ${patid}"_T2"_to_${patid}_T1_rev.mat -dof 6
		if($status) exit 1
		
		set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_T2" ../T1/${patid}_T1 ${patid}_T2_to_${patid}_T1.mat ${patid}"_T2"_to_${patid}_T1_rev.mat 0 50 0`
		
		decho "2 way registration displacement: $Displacement" registration_displacement.txt
		
		if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_T2" ../T1/${patid}_T1 ${patid}_T2_to_${patid}_T1.mat ${patid}"_T2"_to_${patid}_T1_rev.mat 0 50 0 $MaximumRegDisplacement`) then
			decho "	Error: Registration from T2 to T1 and T1 to T2 has a displacement of "$Displacement
			exit 1
		endif
	endif
	
	flirt -in ${patid}"_T2" -ref ../T1/${patid}_T1_brain_restore.nii.gz -out ${patid}_T2_to_${patid}_T1 -init ${patid}_T2_to_${patid}_T1.mat -applyxfm 
	if($status) exit 1
	
	#combine T2 -> T1 -> Atlas if we specified a target atlas
	if($target != "") then
		convert_xfm -omat ${patid}_T2_to_${AtlasName}.mat -concat ../T1/${patid}_T1_to_${AtlasName}.mat ${patid}_T2_to_${patid}_T1.mat
		if($status) exit 1
		
		flirt -in ${patid}"_T2" -ref $target -out ${patid}_T2_111 -init ${patid}_T2_to_${AtlasName}.mat -applyxfm -interp spline 
		if($status) exit 1

		flirt -in ${patid}_T2_111 -ref $target -out ${patid}_T2_${FinalResTrailer} -applyisoxfm $FinalResolution -interp spline 
		if($status) exit 1
	endif
	
popd

exit 0
