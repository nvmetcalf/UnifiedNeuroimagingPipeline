#!/bin/csh

setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

source $1 
source $2

set SubjectHome = $cwd

set peds = (`echo $DTI_ped | tr " " "\n" | sort | uniq`)
	
if(! $?day1_path || ! $?day1_patid) then
	set day1_path = ""
	set day1_patid = ""
endif

if($target != "") then
	set AtlasName = `basename $target`
	set RegTarget = $target
else
	if($day1_patid != "" || $day1_path != "") then
		set AtlasName = ${day1_patid}_T1
		set RegTarget = ${day1_path}/Anatomical/Volume/T1/${day1_patid}_T1
	else
		set AtlasName = ${patid}_T1
		set RegTarget = ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1
	endif
endif

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if(! -e DTI) then
	mkdir DTI
endif

rm -rf ${SubjectHome}/Anatomical/Volume/DTI_ref
mkdir -p ${SubjectHome}/Anatomical/Volume/DTI_ref

rm -r $ScratchFolder/${patid}/DTI_temp
mkdir -p $ScratchFolder/${patid}/DTI_temp

#get a list of uniq phase encoding directions so we can properly register things
set peds = (`echo $DTI_ped | tr " " "\n" | sort | uniq`)

pushd $ScratchFolder/${patid}/DTI_temp
	#goto SPLIT
	foreach ped($peds)
		ftouch DTI_ped_${ped}.txt
		if($status) exit 1
	end
	
	#go through all the DTI images and apply the distortion correction
	@ i = 1
	set DTI_images = ()
		
	ftouch DTI_concat.bvec
	ftouch DTI_concat.bval
	ftouch eddy_index.txt
	ftouch eddy_datain.txt
	ftouch DTI_dir_ped.txt
	
	while($i <= $#DTI)
		switch($DTI_ped[$i])
			case "y"
				set x_ped = "0"
				set y_ped = "1"
				set z_ped = "0"
			breaksw
			case "-y"
				set x_ped = "0"
				set y_ped = "-1"
				set z_ped = "0"
			breaksw
			case "x"
				set x_ped = "1"
				set y_ped = "0"
				set z_ped = "0"
			breaksw
			case "-x"
				set x_ped = "-1"
				set y_ped = "0"
				set z_ped = "0"
			breaksw
			default
				echo "Unsupported acquisition direction: $DTI_ped[$i]"
				exit 1
			breaksw
		endsw
		#record each scan by phase encoding direction
		echo ${SubjectHome}/dicom/$DTI[$i] >> DTI_ped_${ped}.txt
		
		echo "$x_ped $y_ped $z_ped $DTI_dwell[$i]" >> "eddy_datain.txt"

		set DTI_images = ($DTI_images ${SubjectHome}/dicom/$DTI[$i])
		
		#combine the bvals and bvecs into common files
		paste DTI_concat.bvec ${SubjectHome}/dicom/$DTI[$i]:r:r.bvec >! temp.bvec
		if($status) exit 1
		mv temp.bvec DTI_concat.bvec
			
		paste DTI_concat.bval ${SubjectHome}/dicom/$DTI[$i]:r:r.bval >! temp.bval
		if($status) exit 1
		mv temp.bval DTI_concat.bval
		
		#enter the scan each volume belongs to for eddy correction
		set dwi_vols = `fslinfo ${SubjectHome}/dicom/$DTI[$i] | grep dim4 | head -1 | awk '{print $2}'`
		@ j = 1
		while($j <= $dwi_vols)
			echo $i >> eddy_index.txt
			#record the directions phase encoding direction for later
			echo $DTI_ped[$i] >> DTI_dir_ped.txt
			@ j++
		end
		@ i++
	end
	
	decho "Moving bval, bvecs, and peds to ${SubjectHome}/DTI" $DebugFile
	mv DTI_concat.bval DTI_concat.bvec DTI_dir_ped.txt ${SubjectHome}/DTI/
	
	#Concatenate the DTI dc sets
	fslmerge -t DTI_concat $DTI_images
	if($status) exit 1
		
	#compute eddy correction of DTI
	eddy_correct DTI_concat.nii.gz DTI_concat_ec.nii.gz 0 trilinear
	if($status) exit 1
	
	#computer movement correction
	mcflirt -in DTI_concat_ec.nii.gz -cost normmi -refvol 0 -mats -report
	if($status) exit 1
	
	#eddy_openmp --imain=DTI_STACK.nii.gz --mask=b0_brain_mask.nii.gz --bvecs=DTI_STACK.bvec --bvals=DTI_STACK.bvals --out=DTI_STACK_eddy --acqp=datain.txt --index=eddy_index.txt --data_is_shelled
	
	#eddy and movement correction are done, but now we need to split that time series by phase
	#encoding direction and make reference images for each phase encoding direction for distortion
	#correction
	set ConcatLength = `fslinfo DTI_concat_ec.nii.gz | grep -w dim4 | awk '{print $2}'`
	echo $ConcatLength
	
	foreach ped($peds)
		#go through the whole DTI list and see which runs match the current ped
		#then extract that runs volumes
		@ RunStart = 0
		@ i = 1
		while($i <= $#DTI)
			@ RunLength = `fslinfo ${SubjectHome}/dicom/$DTI[$i] | grep -w dim4 | awk '{print $2}'` - 1
			@ RunEnd = $RunStart + $RunLength
			if($DTI_ped[$i] == $ped) then
				fslroi DTI_concat_ec.nii.gz DTI_concat_ec_${ped}_${i}.nii.gz $RunStart $RunEnd
				if($status) exit 1
			endif
			@ RunStart = $RunStart + $RunLength + 1
			@ i++
		end
		
		fslmerge -t DTI_${ped}_dirs `ls *_${ped}_*.nii.gz`
		if($status) exit 1
		
		fslmaths DTI_${ped}_dirs -Tmean ${SubjectHome}/Anatomical/Volume/DTI_ref/${patid}_DTI_ref_distorted_${ped}
		if($status) exit 1
	end
	
	#create DTI reference image from the eddy corrected images
	fslmaths DTI_concat_ec -Tmean ${SubjectHome}/Anatomical/Volume/DTI_ref/${patid}_DTI_ref
	if($status) exit 1
	
	bet ${SubjectHome}/Anatomical/Volume/DTI_ref/${patid}_DTI_ref ${SubjectHome}/Anatomical/Volume/DTI_ref/${patid}_DTI_ref_brain -R -f 0.35
	if($status) exit 1
	
	#generate the distortion correction transform
	pushd $SubjectHome
 		$PP_SCRIPTS/Registration/ComputeDistortionCorrection.csh $1 $2 "DTI" "$DTI_dwell" "$DTI_ped" "$DTI_fm" "$DTI_FieldMapping" "$DTI_Reg_Target" "$DTI_delta" "$DTI"
 		if($status) exit 1
 		
 		foreach direction($peds)
		
			if($NonLinear) then
				if($DTI_FieldMapping == "6dof" || $DTI_FieldMapping == "none" || $DTI_FieldMapping == "") then
					#just has a affine transform to the T1
					convertwarp -r ${target}_${FinalResTrailer} --premat=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_${direction}.mat -w ${SubjectHome}/Anatomical/Volume/${DTI_Reg_Target}/${patid}_${DTI_Reg_Target}_warpfield_111.nii.gz -o ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_${direction}_to_${AtlasName}_warp
				else
					convertwarp -r ${target}_${FinalResTrailer} --warp1=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_${direction}_warp.nii.gz --warp2=${SubjectHome}/Anatomical/Volume/${DTI_Reg_Target}/${patid}_${DTI_Reg_Target}_warpfield_111.nii.gz -o ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_${direction}_to_${AtlasName}_warp
				endif
				
				set out_trailer = "_fnirt"
			else if($target != "") then
				if($DTI_FieldMapping == "6dof" || $DTI_FieldMapping == "none" || $DTI_FieldMapping == "") then
					#just has a affine transform to the T1 -> atlas
					convertwarp -r ${target}_${FinalResTrailer} --premat=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_${direction}.mat --postmat=${SubjectHome}/Anatomical/Volume/${DTI_Reg_Target}/${patid}_${DTI_Reg_Target}_to_${AtlasName}.mat -o ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_${direction}_to_${AtlasName}_warp
				else
					convertwarp -r ${target}_${FinalResTrailer} --warp1=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_${direction}_warp.nii.gz --postmat=${SubjectHome}/Anatomical/Volume/${DTI_Reg_Target}/${patid}_${DTI_Reg_Target}_to_${AtlasName}.mat -o ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_${direction}_to_${AtlasName}_warp
				endif
				
				set out_trailer = ""
			else
				if($DTI_FieldMapping == "6dof" || $DTI_FieldMapping == "none" || $DTI_FieldMapping == "") then
					#just has a affine transform to the T1
					convertwarp -r ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1 --premat=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_${direction}.mat -o ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_${direction}_to_${AtlasName}_warp
				else
					convertwarp -r ${RegTarget}_${FinalResTrailer} --warp1=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_${direction}_warp.nii.gz -o ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_${direction}_to_${AtlasName}_warp
				endif
				set out_trailer = ""
			endif
		end
		
		applywarp -i ${SubjectHome}/Anatomical/Volume/DTI_ref/${patid}_DTI_ref_distorted_${direction} -r ${RegTarget}_${FinalResTrailer} -w ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_${direction}_to_${AtlasName}_warp -o ${SubjectHome}/Anatomical/Volume/DTI_ref/${patid}_DTI_ref_${FinalResTrailer}${out_trailer}
		if($status) exit 1
 	popd
 	
 	SPLIT:
 	
 	#this section is confusing. Needs simplification somehow
 	#For each volume in the concat timeseries, we need need to find the phase encoding
 	#direction to find the correct shift warp to the target to apply
 	#since the runs are concatenated in the same order as the run order, we
 	#go from concat volume 1 and run 1 volume 1 and progress through each volume applying
 	#the appropriate transforms for a one step resample of the raw data.
 	#One we reach the end of a runs volumes, we increment to the next run.
 	#the run is needed for getting the phase encoding.
 	
 	#this can be made easier to wrap ones head around by just referencing the 
 	#
	set Num_dirs = `fslinfo DTI_concat | grep dim4 | head -1 | awk '{print $2}'`
	
	echo "Number of directions: $Num_dirs"
	
	set DTI_dirs_images = ()
	@ i = 0
	
	while($i < $Num_dirs)
	
		echo "==== Current Positions ===="
		echo "DTI dirr: $i"
		set curr_dir = `echo $i | awk '{printf("%04.0f",$1)}'`
		@ k = $i + 1	#can't head -0
		set curr_ped = `cat ${SubjectHome}/DTI/DTI_dir_ped.txt | head -${k} | tail -1`
		
		fslroi DTI_concat DTI_dir_${curr_dir} $i 1
		
		if($status) exit 1
		
		grep -A 6 DTI_concat_ec_tmp${curr_dir} DTI_concat_ec.ecclog | tail -4 >! DTI_dir_${curr_dir}_ec.mat
		
		echo "============ eddy matrix ============="
		
		cat DTI_dir_${curr_dir}_ec.mat
		
		echo "======================================"
		
		echo "============ mc matrix ============="
		
		@ j = $i + 1
		set MovementXfm = `ls $ScratchFolder/${patid}/DTI_temp/DTI_concat_ec_mcf.mat/* | head -$j | tail -1`
		echo $MovementXfm
		cat $MovementXfm
		
		echo "======================================"
		
		echo "============ phase encoding ============="
		echo $curr_ped
		echo "======================================"
		
		#combine the eddy correct and movement matrices
		convert_xfm -omat DTI_dir_${curr_dir}_ec_mv.mat -concat $MovementXfm DTI_dir_${curr_dir}_ec.mat
		if($status) exit 1
		
		#apply the current direction eddy + movement with the warp to the registration target and output in target final resolution space
		applywarp --ref=${RegTarget}_${FinalResTrailer} --premat=DTI_dir_${curr_dir}_ec_mv.mat --warp=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_${curr_ped}_to_${AtlasName}_warp --in=DTI_dir_${curr_dir} --out=DTI_dir_${curr_dir}_on_${RegTarget:t}_${FinalResolution} --interp=spline
		if ($status) exit $status
				
		#convertwarp -o DTI_dir_${curr_dir}_ec_dc_warp -r DTI_dir_${curr_dir} --premat=DTI_dir_${curr_dir}_ec_mv.mat --warp1=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_$DTI_ped[$CurrentRun]_warp.nii.gz --warp2 ${SubjectHome}/Anatomical/Volume/${DTI_Reg_Target}/${patid}_${DTI_Reg_Target}_warpfield_111.nii.gz -o DTI_dir_${curr_dir}_ec_dc_warp  # --postmat=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_$DTI_ped[$CurrentRun]_to_${patid}_${DTI_Reg_Target}.mat
		#if($status) exit 1
		
		#applywarp -i DTI_dir_${curr_dir} -r ${SubjectHome}/Anatomical/Volume/${DTI_Reg_Target}/${patid}_${DTI_Reg_Target} -o DTI_dir_${curr_dir}_ec_dc -w DTI_dir_${curr_dir}_ec_dc_warp
		#if($status) exit 1
		
		set DTI_dirs_images = ($DTI_dirs_images DTI_dir_${curr_dir}_on_${RegTarget:t}_${FinalResolution})
		
		@ i++
	end
	
	fslmerge -t DTI_concat_ec_dc $DTI_dirs_images
	if($status) exit 1
	
	cp DTI_concat_ec_dc.nii.gz ${SubjectHome}/DTI/DTI_concat_ec_dc.nii.gz
	if($status) exit 1
	
	#make a brain mask
	fslmaths DTI_concat_ec_dc -Tmean ${SubjectHome}/Anatomical/Volume/DTI_ref/${patid}_DTI_ref_ec_dc_ref
	if($status) exit 1
	
	bet ${SubjectHome}/Anatomical/Volume/DTI_ref/${patid}_DTI_ref_ec_dc_ref b0_brain -m -f 0.35 -R
	if($status) exit 1
	
	cp b0_brain.nii.gz b0_brain_mask.nii.gz ${SubjectHome}/DTI/
	if($status) exit 1
	
	#run dti fit
	dtifit -k DTI_concat_ec_dc -o ${SubjectHome}/DTI/DTI_concat_ec_dc_fit -m b0_brain_mask.nii.gz -r ${SubjectHome}/DTI/DTI_concat.bvec -b ${SubjectHome}/DTI/DTI_concat.bval --verbose
	if($status) exit 1
popd

if($?RunBEDPOSTX) then
	pushd ${SubjectHome}/DTI		
			rm -rf Probabalistic Probabalistic.bedpostX
			mkdir Probabalistic
			
			#link up files for bedpostx
			ln -s ${cwd}/DTI_concat_ec_dc.nii.gz Probabalistic/data.nii.gz 
			if($status) exit 1
			
			ln -s ${cwd}/DTI_concat.bvec Probabalistic/bvecs
			if($status) exit 1
			
			ln -s ${cwd}/DTI_concat.bval Probabalistic/bvals
			if($status) exit 1
			
			ln -s ${cwd}/b0_brain.nii.gz Probabalistic/nodif_brain.nii.gz
			if($status) exit 1
			
			ln -s ${cwd}/b0_brain_mask.nii.gz Probabalistic/nodif_brain_mask.nii.gz
			if($status) exit 1
			
			ln -s ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz Probabalistic/T1wMPR.nii.gz
			if($status) exit 1
			
			ln -s ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_brain_restore.nii.gz Probabalistic/T1wMPR_brain.nii.gz
			if($status) exit 1
			
			bedpostx Probabalistic --nf=3 --fudge=1  --bi=1000 --model=3 --rician
			if($status) exit 1
	popd
endif
exit 0
