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

if(! $?SWI ) then
	decho "Warning: The SWI variable does not exist in $1. It denotes a SWI image you are wanting to register, but is not required." $DebugFile
	exit 0
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

rm -r ${SubjectHome}/Anatomical/Volume/SWI
mkdir -p ${SubjectHome}/Anatomical/Volume/SWI
pushd ${SubjectHome}/Anatomical/Volume/SWI

	if( -e $SubjectHome/dicom/$SWI[1]) then
		if($SWI[1]:e == "gz") then
			$RELEASE/niftigz_4dfp -4 $SubjectHome/dicom/$SWI[1] $patid"_SWI_temp"
		else
			$RELEASE/nifti_4dfp -4 $SubjectHome/dicom/$SWI[1] $patid"_SWI_temp"
		endif
	else
		$RELEASE/dcm_to_4dfp -b $patid"_SWI_temp" $SubjectHome/dicom/$dcmroot.$SWI[$#SWI].*
	endif
	if ($status) exit $status

	switch(`grep orientation $patid"_SWI_temp".4dfp.ifh | awk '{print$3}'`)
		case 2:
			echo "SWI already transverse"
			set InputAnat = $patid"_SWI_temp"
			breaksw
		case 3:
			echo "SWI is coronal, transforming to transverse."
			$RELEASE/C2T_4dfp ${patid}_SWI_temp ${patid}_SWIT
			if($status) exit 1
			set InputAnat = $patid"_SWIT"
			breaksw
		case 4:
			echo "SWI is sagital, transforming to transverse."
			$RELEASE/S2T_4dfp ${patid}"_SWI_temp" ${patid}"_SWIT"
			set InputAnat = $patid"_SWIT"
			if($status) exit 1
			breaksw
		default:
			echo "ERROR: UNKNOWN SWI ORIENTATION!!!"
			exit 1
			breaksw
	endsw
	
	rm *_temp.* *T.*
	
	#need to determine if there are multiple echo's or if these are just repeats
	if($#SWI > 1) then
		set TEs = ()
		
		foreach image($SWI)
			set TEs = ($TEs `grep EchoTime $SubjectHome/dicom/$image:r:r".json" | cut -d":" -f2 | cut -d, -f1`)
		end
		
		set UniqTEs = (`echo $TEs | tr ' ' '\n' | uniq`)
		
		#are there multiple unique TE's?
		if($#UniqTEs > 1) then
			#make a stack of the SWI images
			
			set SWI_images = ()
			foreach image($SWI)
				set SWI_images = ($SWI_images ${SubjectHome}/dicom/$image)
			end
			
			fslmerge -t SWI_stack $SWI_images
			if($status) exit 1
			
			#compute r2s SWI image
			matlab -nodesktop -nosplash -r "addpath(genpath('${PP_SCRIPTS}/matlab_scripts/r2s_mapping'));R2starMacroIOWrapper_v2('SWI_stack.nii.gz',[$TEs],'$cwd',[],'$patid','arlo','weighted');exit" || exit $status
			
			mv ${patid}_r2s.nii.gz ${patid}_SWI.nii.gz
			if($status) exit 1
			
			rm SWI_stack.nii.gz
			if($status) exit 1
		else
			#register all the T1's to the first one and average
			set Target_SWI = $SWI[1]
			set SWI_List = ()
			
			foreach SWI($SWI)
				flirt -in ${SubjectHome}/dicom/$SWI -ref ${SubjectHome}/dicom/$Target_SWI -out $SWI:r:r_${Target_SWI} -dof 6 -interp spline -cost mutualinfo -searchcost mutualinfo
				if($status) then
					decho "Unable to register $SWI to $Target_SWI" $DebugFile
					exit 1
				endif
				
				set SWI_List = ($SWI_List $SWI:r:r_${Target_SWI})
			end
		
			fslmerge -t SWI_stack $SWI_List
			if($status) then
				decho "Unable to stack registered SWI's" $DebugFile
				exit 1
			endif
			
			fslmaths SWI_stack -Tmean $patid"_SWI"
			if($status) then
				decho "Unable to average registered SWI stack." $DebugFile
				exit 1
			endif
			
			rm $SWI_List SWI_stack.nii.gz

	endif
		
	bet ${patid}_SWI ${patid}_SWI_brain -m -R -f 0.01
	if($status) exit 1
	
	#extract the brain from the T1
 	fast -b -B -I 10 -l 10 -g -t 2 ${patid}_SWI_brain.nii.gz
 	if($status) then
 		decho "Failed to complete bias correction on SWI."
 		exit 1
 	endif
 	
	$FSLBIN/flirt -in ${patid}"_SWI_brain" -ref ../T1/${patid}_T1_brain_restore -omat ${patid}_SWI_to_${patid}_T1.mat -dof 6 # -cost mutualinfo -searchcost mutualinfo
	if($status) then
		decho "Failed to linearly register SWI to T1"
		exit 1
	endif

	#see if we want to check how far a voxel displaces
	if($MaximumRegDisplacement != 0) then
		flirt -in ../T1/${patid}_T1_brain_restore -ref ${patid}"_SWI_brain" -omat ${patid}"_SWI"_to_${patid}_T1_rev.mat -dof 6 # -cost mutualinfo -searchcost mutualinfo
		if($status) exit 1
		
		set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_SWI" ../T1/${patid}_T1 ${patid}_SWI_to_${patid}_T1.mat ${patid}"_SWI"_to_${patid}_T1_rev.mat 0 50 0`
		
		decho "2 way registration displacement: $Displacement" registration_displacement.txt
		
		if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_SWI" ../T1/${patid}_T1 ${patid}_SWI_to_${patid}_T1.mat ${patid}"_SWI"_to_${patid}_T1_rev.mat 0 50 0 $MaximumRegDisplacement`) then
			decho "	Error: Registration from SWI to $AtlasName and $AtlasName to SWI has a displacement of "$Displacement
			exit 0
		endif
	endif
	
	flirt -in ${patid}"_SWI" -ref ../T1/${patid}_T1_brain_restore.nii.gz -out ${patid}_SWI_to_${patid}_T1 -init ${patid}_SWI_to_${patid}_T1.mat -applyxfm 
	if($status) exit 1
	
	#combine SWI -> T1 -> Atlas if we specified a target atlas
	if($target != "") then
		convert_xfm -omat ${patid}_SWI_to_${AtlasName}.mat -concat ../T1/${patid}_T1_to_${AtlasName}.mat ${patid}_SWI_to_${patid}_T1.mat
		if($status) exit 1
		
		flirt -in ${patid}"_SWI" -ref $target -out ${patid}_SWI_111 -init ${patid}_SWI_to_${AtlasName}.mat -applyxfm -interp spline 
		if($status) exit 1

		flirt -in ${patid}_SWI_111 -ref $target -out ${patid}_SWI_${FinalResTrailer} -applyisoxfm $FinalResolution -interp spline 
		if($status) exit 1
	endif
	
popd

exit 0
