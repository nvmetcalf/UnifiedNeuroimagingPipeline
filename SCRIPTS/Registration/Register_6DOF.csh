#!/bin/csh


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

if(! $?DebugFile) then
	set DebugFile = ${cwd}/$0:t
	ftouch $DebugFile
endif

set FM_Suffix = $3

set AtlasName = $target:t

set ped = ($4)

set Reg_Target = $5

if($#argv > 5) then
	set CostFunction = $6
else
	set CostFunction = corratio
endif

set SubjectHome = $cwd

rm -rf ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
mkdir ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
pushd ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}

	set peds = (`echo $ped | tr " " "\n" | sort | uniq`)

	if(! $?day1_path || ! $?day1_patid) then
		set Target_Path = ${SubjectHome}/Anatomical/Volume
		set Target_Patid = ${patid}
	else
		set Target_Path = ${day1_path}/Anatomical/Volume
		set Target_Patid = ${day1_patid}
	endif

	#make the reference image
	set Ref_STACK = ()

	foreach direction($peds)
		set Ref_STACK = ($Ref_STACK ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction})
	end

	fslmerge -t Ref_STACK $Ref_STACK
	if($status) exit 1

	fslmaths Ref_STACK -Tmean ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref
	if($status) exit 1

	rm Ref_STACK.*

	#do registrations
	foreach direction($peds)
		cp ../${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}.nii.gz .
		if($status) exit 1

		bet ${patid}_${FM_Suffix}_ref_distorted_${direction} ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain -R -f 0.3
		if($status) exit 1

		set HasGoodReg = 0

		foreach image("" _brain)
			flirt -in ${patid}_${FM_Suffix}_ref_distorted_${direction}${image} -ref ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target}${image} -out ${patid}_${FM_Suffix}_ref_distorted_on_${Reg_Target} -omat ${patid}_${FM_Suffix}_ref_unwarped_${direction}.mat -interp spline -dof 6 -cost $CostFunction -searchcost $CostFunction

			#see if we want to check how far a voxel displaces
			if($MaximumRegDisplacement == 0) then
				set MaximumRegDisplacement = `fslinfo ${patid}_${FM_Suffix}_ref_distorted_${direction}${image}.nii.gz | grep pixdim | awk '{print $2 * 1.25}' | sort -u | tail -1`
			endif

			flirt -in ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target}${image} -ref ${patid}_${FM_Suffix}_ref_distorted_${direction}${image} -omat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat -dof 6 -cost $CostFunction -searchcost $CostFunction
			if($status) exit 1

			set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_distorted_${direction}${image} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat 0 50 0`

			decho "2 way registration displacement: $Displacement" registration_displacement.txt

			if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_distorted_${direction}${image} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
				decho "	Error: Registration from $FM_Suffix $direction to $Reg_Target and $Reg_Target to $FM_Suffix $direction has a displacement of "$Displacement $DebugFile
			else
				decho "	Found stable registration." $DebugFile
				set HasGoodReg = 1
				break
			endif
		end
		if($HasGoodReg == 0) then
			decho "Couldn't find a stable registration." $DebugFile
			exit 1
		endif

		#for convention purposes, treat the naming as if distortion correction happened. Though this is just a 6dof warp from the image to the target.
		convertwarp -r ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} --midmat=${patid}_${FM_Suffix}_ref_unwarped_${direction}.mat -o ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}/${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz
		if($status) exit 1
	end
popd
exit 0
