#!/bin/csh

source $1
source $2

if(! $?DebugFile) then
	set DebugFile = ${cwd}/$0:t
	ftouch $DebugFile
endif

set FM_Suffix = $3

set dwell = ($4)
set ped = ($5)

set fm = ($6)

set Reg_Target = $7

set delta = $8

set SubjectHome = $cwd

rm -rf ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
mkdir ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
pushd ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}

	#use measured field maps
	
	if(! $?day1_path || ! $?day1_patid) then
		rm -rf unwarp
		if($status) then
			decho "Could not create unwarp folder." $DebugFile
			exit 1
		endif

		if ($#fm < 3) then
			echo "ERROR: required measured field map correction variables not set"
			exit 1
		endif

		mkdir FieldMap_Mag
		mkdir FieldMap_Phase

		cd FieldMap_Mag

			$FSLBIN/fslmerge -t fieldmap_mag.nii.gz ${SubjectHome}/dicom/$fm[1] ${SubjectHome}/dicom/$fm[2]
			if($status) exit 1
		cd ..

		cd FieldMap_Phase
			cp ${SubjectHome}/dicom/$fm[3] fieldmap_phase.nii.gz
		cd ..
			
		fslmaths FieldMap_Mag/fieldmap_mag.nii.gz -Tmean fmap_mag.nii.gz
		if($status) exit 1
		
		#makes the field map
		bet fmap_mag.nii.gz fmap_mag_brain.nii.gz -m -R -B -f 0.2
		if($status) exit 1
				
		fsl_prepare_fieldmap SIEMENS FieldMap_Phase/fieldmap_phase.nii.gz fmap_mag_brain.nii.gz fmap_rads.nii.gz $delta
		if($status) exit 1
	
		set Target_Path = ${SubjectHome}/Anatomical/Volume
		set Target_Patid = ${patid}
	else
		set Target_Path = ${day1_path}/Anatomical/Volume
		set Target_Patid = ${day1_patid}
		
		ln -s ${Target_Path}/FieldMapping_${FM_Suffix}/FieldMap_Mag/fmap_mag_brain.nii.gz .
	endif

	set peds = (`echo $ped | tr " " "\n" | sort | uniq`)
	
	foreach direction($peds)
	
		unset try_masking
		
		flirt -in fmap_mag.nii.gz -ref ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -out ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction} -dof 6 -omat ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction}.mat
		if($status) exit 1
		
		#see if we want to check how far a voxel displaces
		if($MaximumRegDisplacement != 0) then
			
			flirt -in ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -ref fmap_mag.nii.gz -omat ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain_to_fmap_mag_brain_rev.mat -dof 6
			if($status) exit 1
				
			set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} fmap_mag ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction}.mat ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain_to_fmap_mag_brain_rev.mat 0 50 0`
				
			decho "2 way registration displacement: $Displacement" registration_displacement.txt
				
			if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} fmap_mag ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction}.mat ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain_to_fmap_mag_brain_rev.mat 0 50 0 $MaximumRegDisplacement`) then
				decho "	Error: Registration from $FM_Suffix $direction to field map and field map to $FM_Suffix $direction has a displacement of "$Displacement
				decho "			Trying with masking..."
				set try_masking = 1
			endif
		endif
		
		if($?try_masking) then
			
			bet ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain -f 0.3
			if($status) exit 1
				
			flirt -in fmap_mag_brain.nii.gz -ref ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain -out ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction} -dof 6 -omat ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction}.mat
			if($status) exit 1
			
			#see if we want to check how far a voxel displaces
			if($MaximumRegDisplacement != 0) then
				
				flirt -in ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -ref fmap_mag.nii.gz -omat ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain_to_fmap_mag_brain_rev.mat -dof 6
				if($status) exit 1
					
				set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} fmap_mag ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction}.mat ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain_to_fmap_mag_brain_rev.mat 0 50 0`
					
				decho "2 way registration displacement: $Displacement" registration_displacement.txt
					
				if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain fmap_mag_brain ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction}.mat ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain_to_fmap_mag_brain_rev.mat 0 50 0 $MaximumRegDisplacement`) then
					decho "	Error: Registration from $FM_Suffix $direction to field map and field map to $FM_Suffix $direction has a displacement of "$Displacement
					exit 1
				endif
			endif
		endif
		flirt -in ${Target_Path}/FieldMapping_${FM_Suffix}/fmap_rads.nii.gz -ref ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -out fmap_rads_on_${patid}_${FM_Suffix}_ref_distorted_${direction} -init ${patid}_fmap_mag_anat_on_${patid}_${FM_Suffix}_ref_distorted_${direction}.mat -applyxfm
		if($status) exit 1
		
		if($direction == "-y") then
			set fugue_dir = "y-"
		else if($direction == "y") then
			set fugue_dir = "y"
		else if($direction == "-x") then
			set fugue_dir = "x-"
		else if($direction == "x") then
			set fugue_dir = "x"
		endif
		
		fugue -i ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} --loadfmap=fmap_rads_on_${patid}_${FM_Suffix}_ref_distorted_${direction} --dwell=$dwell[1] --unwarpdir=$fugue_dir --saveshift=${patid}_${FM_Suffix}_ref_distorted_shiftmap_${direction} -u ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp
		if($status) exit 1
		
		flirt -in ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp -ref ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target} -out ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp_to_${patid}_${Reg_Target} -omat ${patid}_${FM_Suffix}_ref_distorted_${direction}_to_${patid}_${Reg_Target}.mat -dof 6
		if($status) exit 1
			
		#see if we want to check how far a voxel displaces
		if($MaximumRegDisplacement != 0) then
			unset try_masking
			
			flirt -in ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target} -ref ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp -omat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat -dof 6
			if($status) exit 1
				
			set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_distorted_${direction}_to_${patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat 0 50 0`
				
			decho "2 way registration displacement: $Displacement" registration_displacement.txt
				
			if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_distorted_${direction}_to_${patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
				decho "	Error: Registration from $FM_Suffix $direction to $Reg_Target and $Reg_Target to $FM_Suffix $direction has a displacement of "$Displacement
				set try_masking = 1
			endif
			
			if($?try_masking) then
				unset try_masking
				bet ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp_brain -f 0.3
				if($status) exit 1
				
				flirt -in ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp_brain -ref ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_brain -out ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp_to_${patid}_${Reg_Target} -omat ${patid}_${FM_Suffix}_ref_distorted_${direction}_to_${patid}_${Reg_Target}.mat -dof 6
				if($status) exit 1
		
				flirt -in ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_brain -ref ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp_brain -omat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat -dof 6 #-cost mutualinfo
				if($status) exit 1
					
				set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp_brain ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_brain ${patid}_${FM_Suffix}_ref_distorted_${direction}_to_${patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat 0 50 0`
					
				decho "2 way registration displacement: $Displacement" registration_displacement.txt
					
				if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp_brain ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_brain ${patid}_${FM_Suffix}_ref_distorted_${direction}_to_${patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
					decho "	Error: Registration from $FM_Suffix $direction to $Reg_Target and $Reg_Target to $FM_Suffix $direction has a displacement of "$Displacement
					exit 1
				endif
			endif
		endif
		
		convertwarp -r ${Target_Path}/${Reg_Target}/${patid}_${Reg_Target} -o ${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz -s ${patid}_${FM_Suffix}_ref_distorted_shiftmap_${direction} -d $fugue_dir --postmat=${patid}_${FM_Suffix}_ref_distorted_${direction}_to_${patid}_${Reg_Target}.mat
		if($status) exit 1
			
		applywarp -r ${Target_Path}/${Reg_Target}/${patid}_${Reg_Target} -i ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -w ${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz -o ${patid}_${FM_Suffix}_ref_distorted_${direction}_uwrp_to_${patid}_${Reg_Target}
		if($status) exit 1
	
	end
popd	
exit 0
