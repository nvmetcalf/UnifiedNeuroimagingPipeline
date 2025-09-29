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

if(! $?SWI ) then
	decho "Warning: The SWI variable does not exist in $1. It denotes a SWI image you are wanting to register, but is not required."
	exit 0
endif

if(! $?SWI_Target) then
	set SWI_Target = T1
endif

set FinalResolutions = (`grep _FinalResolution $1 | awk '{print $4}' | sort -u`)

echo "Detected the following final resolutions: $FinalResolutions"

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
			echo "SCRIPT: $0 : 00003 : ERROR: UNKNOWN SWI ORIENTATION!!!"
			exit 1
			breaksw
	endsw

	rm *_temp.* *T.*

	#need to determine if there are multiple echo's or if these are just repeats
	if($#SWI > 1) then
		set TEs = ()

		foreach image($SWI)
			set TEs = ($TEs `$PP_SCRIPTS/Utilities/GetJSON_Value ${SubjectHome}/dicom/$image:r:r".json" EchoTime | awk '{if($1 < 1) print($1*1000); else print($1);}'`)
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
					echo "SCRIPT: $0 : 00004 : Unable to register $SWI to $Target_SWI"
					exit 1
				endif

				set SWI_List = ($SWI_List $SWI:r:r_${Target_SWI})
			end

			fslmerge -t SWI_stack $SWI_List
			if($status) then
				echo "SCRIPT: $0 : 00005 : Unable to stack registered SWI's"
				exit 1
			endif

			fslmaths SWI_stack -Tmean $patid"_SWI"
			if($status) then
				echo "SCRIPT: $0 : 00006 : Unable to average registered SWI stack."
				exit 1
			endif

			rm $SWI_List SWI_stack.nii.gz

	endif

	bet ${patid}_SWI ${patid}_SWI_brain -m -R -f 0.01
	if($status) exit 1

	#extract the brain from the SWI
 	fast -b -B -I 10 -l 10 -g -t 2 ${patid}_SWI_brain.nii.gz
 	if($status) then
 		echo "SCRIPT: $0 : 00007 : Failed to complete bias correction on SWI."
 		exit 1
 	endif

	set FoundReg = 0
	foreach image(" " "_brain")
		flirt -in ${patid}"_SWI"${image} -ref ../$SWI_Target/${patid}_${SWI_Target}${image} -omat ${patid}_SWI_to_${patid}_${SWI_Target}.mat -dof 6 -interp spline -cost $SWI_CostFunction -searchcost $SWI_CostFunction
		if($status) then
			echo "SCRIPT: $0 : 00008 : Failed to linearly register SWI to ${SWI_Target}"
			exit 1
		endif

		#see if we want to check how far a voxel displaces
		if($MaximumRegDisplacement == 0) then
			set MaximumRegDisplacement = `fslinfo ${patid}"_SWI"${image}.nii.gz | grep pixdim | awk '{print $2 * 1.25}' | sort -u | tail -1`
		endif

		flirt -in ../${SWI_Target}/${patid}_${SWI_Target}${image} -ref ${patid}"_SWI"${image} -omat ${patid}"_SWI"_to_${patid}_${SWI_Target}_rev.mat -dof 6 -cost $SWI_CostFunction -searchcost $SWI_CostFunction
		if($status) exit 1

		set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_SWI" ../${SWI_Target}/${patid}_${SWI_Target} ${patid}_SWI_to_${patid}_${SWI_Target}.mat ${patid}"_SWI"_to_${patid}_${SWI_Target}_rev.mat 0 50 0`

		decho "2 way registration displacement: $Displacement" registration_displacement.txt

		if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}"_SWI" ../${SWI_Target}/${patid}_${SWI_Target} ${patid}_SWI_to_${patid}_${SWI_Target}.mat ${patid}"_SWI"_to_${patid}_${SWI_Target}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
			decho "	Error: Registration from SWI to ${SWI_Target} and ${SWI_Target} to SWI has a displacement of "$Displacement
		else
			set FoundReg = 1
		endif

		if($FoundReg) then
			break
		endif
	end

	if(! $FoundReg) then
		echo "SCRIPT: $0 : 00009 : Could not register SWI to ${SWI_Target} well enough."
		exit 1
	endif

	flirt -in ${patid}"_SWI" -ref ../${SWI_Target}/${patid}_${SWI_Target}_brain_restore.nii.gz -out ${patid}_SWI_to_${patid}_${SWI_Target} -init ${patid}_SWI_to_${patid}_${SWI_Target}.mat -applyxfm
	if($status) exit 1

	#combine SWI -> T1 -> Atlas if we specified a target atlas
	if($target != "") then
		convert_xfm -omat ${patid}_SWI_to_${AtlasName}.mat -concat ../${SWI_Target}/${patid}_${SWI_Target}_to_${AtlasName}.mat ${patid}_SWI_to_${patid}_${SWI_Target}.mat
		if($status) exit 1

		flirt -in ${patid}"_SWI" -ref $target -out ${patid}_SWI_111 -init ${patid}_SWI_to_${AtlasName}.mat -applyxfm -interp spline
		if($status) exit 1

		foreach res($FinalResolutions)
			if($res == 0) then
				continue
			endif
			flirt -in ${patid}_SWI_111 -ref $target -out ${patid}_SWI_${res}${res}${res} -applyisoxfm ${res} -interp spline
			if($status) exit 1
		end
	else
		foreach res($FinalResolutions)
			if($res == 0) then
				continue
			endif
			flirt -in ${patid}"_SWI" -ref ../$SWI_Target/${patid}_${SWI_Target} -init ${patid}_SWI_to_${patid}_${SWI_Target}.mat -interp spline -applyisoxfm $res -out ${patid}"_SWI_"${res}${res}${res}
			if($status) exit 1
		end
	endif

popd

exit 0
