#!/bin/csh

source $1
source $2

set FM_Suffix = $3

set AtlasName = `basename $target`

set dwell = ($4)
set ped = ($5)

set Reg_Target = $6

set SubjectHome = $cwd

set SynthB0_Path = ${PP_SCRIPTS}/Synb0-DISCO

set MNI_T1_1_MM_FILE = ${PP_SCRIPTS}/Synb0-DISCO/atlases/mni_icbm152_t1_tal_nlin_asym_09c.nii.gz

pip install torch 
if($status) exit 1

pushd $SynthB0_Path
	pip install torchvision-0.18.1-cp311-cp311-manylinux1_x86_64.whl
	if($status) exit 1
popd

if(! $?day1_path || ! $?day1_patid) then
	set Target_Path = ${SubjectHome}/Anatomical/Volume
	set Target_Patid = ${patid}
else
	set Target_Path = ${day1_path}/Anatomical/Volume
	set Target_Patid = ${day1_patid}
endif
	
rm -rf ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
mkdir ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
pushd ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}

#copy over the distorted ref image
set peds = (`echo $ped | tr " " "\n" | sort | uniq`)

foreach direction($peds)
	
	cp ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}.nii.gz .
	if($status) exit 1
	
	mkdir OUTPUTS_${direction}
	if($status) exit 1
	
	# Prepare input
	$SynthB0_Path/data_processing/prepare_input.sh $cwd/${patid}_${FM_Suffix}_ref_distorted_${direction}.nii.gz ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}.nii.gz ${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_brain.nii.gz $MNI_T1_1_MM_FILE $SynthB0_Path/atlases/mni_icbm152_t1_tal_nlin_asym_09c_2_5.nii.gz $cwd/OUTPUTS_${direction}

	# Run inference
	foreach fold (`seq 1 5`)
		echo Performing inference on FOLD: $fold
		python $SynthB0_Path/src/inference.py $cwd/OUTPUTS_${direction}/T1_norm_lin_atlas_2_5.nii.gz $cwd/OUTPUTS_${direction}/b0_d_lin_atlas_2_5.nii.gz $cwd/OUTPUTS_${direction}/b0_u_lin_atlas_2_5_FOLD_${fold}.nii.gz $SynthB0_Path/src/train_lin/num_fold_${fold}_total_folds_5_seed_1_num_epochs_100_lr_0.0001_betas_\(0.9\,\ 0.999\)_weight_decay_1e-05_num_epoch_*.pth
		if($status) exit 1
	end

	# Take mean
	echo Taking ensemble average
	fslmerge -t $cwd/OUTPUTS_${direction}/b0_u_lin_atlas_2_5_merged.nii.gz $cwd/OUTPUTS_${direction}/b0_u_lin_atlas_2_5_FOLD_*.nii.gz
	if($status) exit 1
	
	fslmaths $cwd/OUTPUTS_${direction}/b0_u_lin_atlas_2_5_merged.nii.gz -Tmean $cwd/OUTPUTS_${direction}/b0_u_lin_atlas_2_5.nii.gz
	if($status) exit 1
	
	# Apply inverse xform to undistorted b0
	echo Applying inverse xform to undistorted b0
	echo "antsApplyTransforms -d 3 -i $cwd/OUTPUTS_${direction}/b0_u_lin_atlas_2_5.nii.gz -r $cwd/${patid}_${FM_Suffix}_ref_distorted_${direction}.nii.gz -n BSpline -t [$cwd/OUTPUTS_${direction}/epi_reg_d_ANTS.txt,1] -t [$cwd/OUTPUTS_${direction}/ANTS0GenericAffine.mat,1] -o $cwd/OUTPUTS_${direction}/b0_u.nii.gz"
	antsApplyTransforms -d 3 -i $cwd/OUTPUTS_${direction}/b0_u_lin_atlas_2_5.nii.gz -r $cwd/${patid}_${FM_Suffix}_ref_distorted_${direction}.nii.gz -n BSpline -t "[$cwd/OUTPUTS_${direction}/epi_reg_d_ANTS.txt,1]" -t "[$cwd/OUTPUTS_${direction}/ANTS0GenericAffine.mat,1]" -o $cwd/OUTPUTS_${direction}/b0_u.nii.gz
	if($status) exit 1
	
	# Smooth image
	echo Applying slight smoothing to distorted b0
	fslmaths ${patid}_${FM_Suffix}_ref_distorted_${direction}.nii.gz -s 1.15 $cwd/OUTPUTS_${direction}/b0_d_smooth.nii.gz
	if($status) exit 1
	
	# Merge results and run through topup
	echo Running topup
	fslmerge -t $cwd/OUTPUTS_${direction}/b0_all.nii.gz $cwd/OUTPUTS_${direction}/b0_d_smooth.nii.gz $cwd/OUTPUTS_${direction}/b0_u.nii.gz
	if($status) exit 1
	
	#put together the acquisition parameters for this direction
	@ i = 1
	ftouch acqparams_${direction}.txt
	while($i <= $#ped)
		if($ped[$i] == $direction) then
			set TotalReadout = `cat ${SubjectHome}/dicom/$BOLD[$i]:r:r".json" | grep TotalReadoutTime | cut -d":" -f2 | cut -d"," -f1`
			if($direction == "-y") then
				echo "0 -1 0 $TotalReadout" >> "acqparams_${direction}.txt"
				echo "0 1 0 $TotalReadout" >> "acqparams_${direction}.txt"
			else if($direction == "y") then
				echo "0 1 0 $TotalReadout" >> "acqparams_${direction}.txt"
				echo "0 -1 0 $TotalReadout" >> "acqparams_${direction}.txt"
			else if($direction == "-x") then
				echo "-1 0 0 $TotalReadout" >> "acqparams_${direction}.txt"
				echo "1 0 0 $TotalReadout" >> "acqparams_${direction}.txt"
			else if($direction == "x") then
				echo "1 0 0 $TotalReadout" >> "acqparams_${direction}.txt"
				echo "-1 0 0 $TotalReadout" ">> acqparams_${direction}.txt"
			endif
			break
		endif
		@ i++
	end
	
	topup -v --imain=$cwd/OUTPUTS_${direction}/b0_all.nii.gz --datain=acqparams_${direction}.txt --config=$SynthB0_Path/src/synb0.cnf --out=$cwd/OUTPUTS_${direction}/topup --fout=${patid}_${FM_Suffix}_ref_unwarped_warpcoef_${direction}.nii.gz --iout=imain_dc_${direction}.nii.gz
	if($status) exit 1
	
	#create the magnitude image by averaging the images used in topup
	fslmaths imain_dc_${direction}.nii.gz -Tmean ImageStack_mag_${direction}
	if($status) exit 1
		
	#convert the HZ field map to a rad/s field map by multiplying by 2pi
	fslmaths ${patid}_${FM_Suffix}_ref_unwarped_warpcoef_${direction}.nii.gz -mul 6.2831853 ImageStack_rads_${direction}.nii.gz
	if($status) exit 1
		
	#extact the brain from the magnitude image
	bet ImageStack_mag_${direction} ImageStack_mag_${direction}_brain -f 0.2
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
		
	fugue --loadfmap=ImageStack_rads_${direction} --dwell=$dwell[1] --unwarpdir=$fugue_dir --saveshift=${patid}_${FM_Suffix}_ref_distorted_shiftmap_${direction} --unwarp=${patid}_${FM_Suffix}_ref_distorted_${direction}_unwarped_fugue --in=${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}
	if($status) exit 1
		
	convertwarp -r ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -o ${patid}_${FM_Suffix}_ref_unwarp_${direction}.nii.gz -s ${patid}_${FM_Suffix}_ref_distorted_shiftmap_${direction} -d $fugue_dir # --postmat=${patid}_${FM_Suffix}_ref_distorted_to_${patid}_T1.mat
	if($status) exit 1
	
	applywarp -i ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -r ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -w ${patid}_${FM_Suffix}_ref_unwarp_${direction}.nii.gz -o ${patid}_${FM_Suffix}_ref_unwarped_${direction} --interp=spline
	if($status) exit 1
		
	bet ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_brain -R -f 0.35
	if($status) exit 1
		
	flirt -in ${patid}_${FM_Suffix}_ref_unwarped_${direction} -ref ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -omat ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat -out ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target} -dof 6 #-cost mutualinfo -searchcost mutualinfo
	if($status) exit 1
	
	#see if we want to check how far a voxel displaces
	if($MaximumRegDisplacement != 0) then
		flirt -in ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -ref ${patid}_${FM_Suffix}_ref_unwarped_${direction} -omat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat -dof 6 #-cost mutualinfo -searchcost mutualinfo
		if($status) exit 1
		
		set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat 0 50 0`
		
		decho "2 way registration displacement: $Displacement" registration_displacement.txt
		
		if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
			decho "	Error: Registration from $FM_Suffix $direction to $Reg_Target and $Reg_Target to $FM_Suffix $direction has a displacement of "$Displacement
			decho "		Trying with masking..."
			set try_mask = 1
		endif
	endif
		
	if($?try_mask) then
		unset try_mask
		flirt -in ${patid}_${FM_Suffix}_ref_unwarped_${direction}_brain -ref ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target}_brain -omat ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat -out ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target} -dof 6 #-cost mutualinfo -searchcost mutualinfo
		if($status) exit 1
		
		#see if we want to check how far a voxel displaces
		if($MaximumRegDisplacement != 0) then
			flirt -in ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target}_brain -ref ${patid}_${FM_Suffix}_ref_unwarped_${direction}_brain -omat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat -dof 6 #-cost mutualinfo -searchcost mutualinfo
			if($status) exit 1
			
			set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_unwarped_${direction}_brain ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target}_brain ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat 0 50 0`
			
			decho "2 way registration displacement: $Displacement" registration_displacement.txt
			
			if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
				decho "	Error: Registration from $FM_Suffix $direction to $Reg_Target and $Reg_Target to $FM_Suffix $direction has a displacement of "$Displacement
				exit 1
			endif
		endif
	endif
	
	convertwarp -r ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -w ${patid}_${FM_Suffix}_ref_unwarp_${direction}.nii.gz --midmat=${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat -o ${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz
	if($status) exit 1
end

popd

exit 0
