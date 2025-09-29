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

set FM_Suffix = $3

set AtlasName = $target:t

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
			decho "Could not create unwarp folder."
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

		#makes the field map
		bet FieldMap_Mag/fieldmap_mag.nii.gz fmap_mag_brain1.nii.gz
		if($status) exit 1

		fslmaths fmap_mag_brain1.nii.gz -ero fmap_mag_brain.nii.gz
		if($status) exit 1

		fsl_prepare_fieldmap SIEMENS FieldMap_Phase/fieldmap_phase.nii.gz fmap_mag_brain.nii.gz fmap_rads.nii.gz $delta
		if($status) exit 1

		#needed to do bbr registration with epi
		fslmaths ../${Reg_Target}/${patid}_${Reg_Target}_brain_pve_2.nii.gz -thr 0.5 -bin ../${Reg_Target}/${patid}_${Reg_Target}_wmseg.nii.gz
		if($status) exit 1

		set Target_Path = ${SubjectHome}/Anatomical/Volume
		set Target_Patid = ${patid}
	else
		set Target_Path = ${day1_path}/Anatomical/Volume
		set Target_Patid = ${day1_patid}
	endif

	set peds = (`echo $ped | tr " " "\n" | sort | uniq`)

	foreach direction($peds)
		#cp ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}.nii* .
		epi_reg --echospacing=$dwell[1] --fmap=${Target_Path}/FieldMapping_${FM_Suffix}/fmap_rads.nii.gz --fmapmag=${Target_Path}/FieldMapping_${FM_Suffix}/FieldMap_Mag/fieldmap_mag.nii.gz --fmapmagbrain=${Target_Path}/FieldMapping_${FM_Suffix}/fmap_mag_brain.nii.gz --pedir=${direction} --epi=${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} --t1=${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} --t1brain=${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target}_brain_restore.nii.gz --out=${patid}_${FM_Suffix}_ref_unwarped_${direction} --noclean
		if($status) exit 1

		#see if we want to check how far a voxel displaces
		if($MaximumRegDisplacement == 0) then
			set MaximumRegDisplacement = `fslinfo ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}.nii.gz | grep pixdim | awk '{print $2 * 1.25}' | sort -u | tail -1`
		endif

		flirt -in ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -ref ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -omat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat -dof 6
		if($status) exit 1

		set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat 0 50 0`

		decho "2 way registration displacement: $Displacement" registration_displacement.txt

		if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_distorted_${direction}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
			decho "	Error: Registration from $FM_Suffix $direction to $Reg_Target and $Reg_Target to $FM_Suffix $direction has a displacement of "$Displacement
			exit 1
		endif
	end
popd
exit 0
