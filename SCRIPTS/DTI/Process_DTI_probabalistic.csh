#!/bin/csh

setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

source $1 
source $2

set SubjectHome = $cwd

set peds = (`echo $DTI_ped | tr " " "\n" | sort | uniq`)
	
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
			@ j++
		end
		@ i++
	end
	
	decho "Moving bval and bvecs to ${SubjectHome}/DTI" $DebugFile
	mv DTI_concat.bval DTI_concat.bvec ${SubjectHome}/DTI/
	
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
	#encoding direction and make referance images for each phase encoding direction for distortion
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
 		$PP_SCRIPTS/Registration/ComputeDistortionCorrection.csh $1 $2 "DTI" "$DTI_dwell" "$DTI_ped" "$DTI_fm" "$DTI_FieldMapping" "$DTI_Reg_Target"
 		if($status) exit 1
 	popd
 	
 	SPLIT:
	set Num_dirs = `fslinfo DTI_concat | grep dim4 | head -1 | awk '{print $2}'`
	
	echo "Number of directions: $Num_dirs"
	
	set DTI_dirs_images = ()
	@ i = 0
	@ CurrentRunVol = 1
	@ CurrentRun = 1
	while($i < $Num_dirs)
	
		if($CurrentRunVol > `fslinfo ${SubjectHome}/dicom/$DTI[$CurrentRun] | grep -w dim4 | awk '{print $2}'`) then
			@ CurrentRun++
			@ CurrentRunVol = 1
		endif
		echo "==== Current Positions ===="
		echo $CurrentRun
		echo $CurrentRunVol
		echo "DTI dirr: $i"
		set curr_dir = `echo $i | awk '{printf("%04.0f",$1)}'`
		
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
		
		convertwarp -o DTI_dir_${curr_dir}_ec_dc_warp -r DTI_dir_${curr_dir} --premat=DTI_dir_${curr_dir}_ec.mat --midmat=$MovementXfm --warp2=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_$DTI_ped[$CurrentRun]_warp.nii.gz # --postmat=${SubjectHome}/Anatomical/Volume/FieldMapping_DTI/${patid}_DTI_ref_unwarped_$DTI_ped[$CurrentRun]_to_${patid}_${DTI_Reg_Target}.mat
		if($status) exit 1
		
		applywarp -i DTI_dir_${curr_dir} -r ${SubjectHome}/Anatomical/Volume/${DTI_Reg_Target}/${patid}_${DTI_Reg_Target} -o DTI_dir_${curr_dir}_ec_dc -w DTI_dir_${curr_dir}_ec_dc_warp
		if($status) exit 1
		
		set DTI_dirs_images = ($DTI_dirs_images DTI_dir_${curr_dir}_ec_dc)
		
		@ i++
		@ CurrentRunVol++
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
pause
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
	
exit 0
