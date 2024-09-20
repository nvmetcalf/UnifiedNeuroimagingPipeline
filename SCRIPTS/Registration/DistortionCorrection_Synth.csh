#!/bin/csh

source $1
source $2

set FM_Suffix = $3

set AtlasName = `basename $target`

set dwell = ($4)
set ped = ($5)

set Reg_Target = $6

set SubjectHome = $cwd

if($NonLinear == 0) then
	decho "Cannot perform synthetic distortion correction without nonlinear registration to MNI target."
	exit 1
endif
rm -rf ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
mkdir ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
pushd ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}

		if(! $?day1_path || ! $?day1_patid) then
			set Target_Path = ${SubjectHome}/Anatomical/Volume
			set Target_Patid = ${patid}
		else
			set Target_Path = ${day1_path}/Anatomical/Volume
			set Target_Patid = ${day1_patid}
		endif
		
		set peds = (`echo $ped | tr " " "\n" | sort | uniq`)
		
		foreach direction($peds)
		
			set anat = ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}	# first frame of first BOLD run in group
			
			bet $anat ${anat}_brain -f 0.2 -m
			if($status) exit 1
			
			niftigz_4dfp -4 ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}
			if($status) exit 1
			
			niftigz_4dfp -4 ${anat}_brain_mask ${anat}_brain_mask
			if($status) exit 1
						
			niftigz_4dfp -4 ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target}_brain_mask ${patid}_${Reg_Target}_brain_mask
			if($status) exit 1
			
			niftigz_4dfp -4 ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${Reg_Target}
			if($status) exit 1
			
			set struct = $cwd/${patid}_${Reg_Target}
			
			set warp   = ${Target_Path}/${Reg_Target}/$patid"_${Reg_Target}_coeffield_111.nii.gz"
			
			set bases	= $REFDIR/FMAPBases/FNIRT_474_all_basis.4dfp.img	# I would not touch this
			set mean	= $REFDIR/FMAPBases/FNIRT_474_all_mean.4dfp.img	# I would not touch this
			@ nbases	= 5		# number of bases to use
			@ niter		= 5		# number of synthetic field map iterations

			set synthstr = "-bases $bases $niter $nbases"
				
			if($direction == "-y") then
				set fugue_dir = "y-"
			else if($direction == "y") then
				set fugue_dir = "y"
			else if($direction == "-x") then
				set fugue_dir = "x-"
			else if($direction == "x") then
				set fugue_dir = "x"
			endif
		
			synthetic_FMAP.csh ${anat} ${anat}_brain_mask $struct ${struct}_brain_mask $warp \
				${mean} $dwell[1] $fugue_dir ${patid}_synthFMAP $synthstr -dir $cwd || exit $status
			#set PHA_on_EPI = ${patid}_synthFMAP_on_${anat}_uwrp
			if($status) exit 1
		
			niftigz_4dfp -n ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}
			if($status) exit 1
						
			fugue --loadfmap=${patid}_synthFMAP_on_${patid}_${FM_Suffix}_ref_distorted_${direction} --dwell=$dwell[1] --unwarpdir=$fugue_dir --saveshift=${patid}_${FM_Suffix}_ref_distorted_shiftmap_${direction}
			if($status) exit 1
		
			convertwarp -r $struct -o ${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz -s ${patid}_${FM_Suffix}_ref_distorted_shiftmap_${direction} -d $fugue_dir --postmat=${patid}_${FM_Suffix}_ref_distorted_${direction}_to_${patid}_${Reg_Target}.mat
			if($status) exit 1
			
 			#see if we want to check how far a voxel displaces
 			if($MaximumRegDisplacement != 0) then
 				flirt -in ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -ref ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp -omat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat -dof 6 # -cost mutualinfo -searchcost mutualinfo
 				if($status) exit 1
 				
				set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh $anat ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat 0 50 0`
 				
 				decho "2 way registration displacement: $Displacement" registration_displacement.txt
 				
 				if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh $anat ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
 					decho "	Error: Registration from $FM_Suffix $direction to $Reg_Target and $Reg_Target to $FM_Suffix $direction has a displacement of "$Displacement
 					exit 1
 				endif
 			endif
			
		end
popd

exit 0
