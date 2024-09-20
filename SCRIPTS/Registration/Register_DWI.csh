#!/bin/csh

source $1

source $2

set SubjectHome = $cwd

rm -r $SubjectHome/Anatomical/Volume/DWI
mkdir -p $SubjectHome/Anatomical/Volume/DWI

set AtlasName = `basename $target`

if(! -e $ScratchFolder/${patid}) mkdir -p $ScratchFolder/${patid}
pushd $ScratchFolder/${patid}
	rm -r DWI_temp
	mkdir DWI_temp
	cd DWI_temp
	
		# collect all the DTI data by extracting all the frames
		foreach dwi($DTI)
		
			#make a brain mask of the average of the initial dti timeseries
			fslmaths ${SubjectHome}/dicom/$dwi -Tmean $dwi:r:r"_mean"
			if($status) exit 1
			
			bet $dwi:r:r"_mean" $dwi:r:r"_mean_brain" -m -f 0.3 -R
			if($status) exit 1
			
			set Mean = `fslstats ${SubjectHome}/dicom/$dwi -k $dwi:r:r"_mean_brain_mask" -M`
			set SD = `fslstats ${SubjectHome}/dicom/$dwi -k $dwi:r:r"_mean_brain_mask" -S`
			
			set DWI_Thresh = `echo $Mean $SD | awk '{print($1+($2*0.75))}'`
			
			set length = `fslinfo ${SubjectHome}/dicom/$dwi | grep -w dim4 | awk '{print $2}'`
			
			@ i = 0
			while($i < $length)
				fslroi ${SubjectHome}/dicom/$dwi $dwi:r:r_frame${i} $i 1
				if($status) exit 1
				
				set frame_mean = `fslstats $dwi:r:r_frame${i} -k $dwi:r:r"_mean_brain_mask" -M`
				
				#check to see if the current frame should be included in the DWI anat approximation
				if(`echo $DWI_Thresh $frame_mean | awk '{if($1 < $2) print("1"); else print("0");}'`) then
					rm $dwi:r:r_frame${i}.*
				endif
				
				@ i++
			end
		end
		
		#make a timeseries out of the surviving diffusion weighted images
		fslmerge -t DWI_timeseries *frame*
		if($status) exit 1
			
		mcflirt -in DWI_timeseries -out DWI_timeseries_mc -spline_final -meanvol -refvol 0
		if($status) exit 1
		
		mv DWI_timeseries_mc_mean_reg.nii.gz ${SubjectHome}/Anatomical/Volume/DWI/${patid}_DWI.nii.gz
popd

pushd $SubjectHome/Anatomical/Volume/DWI
		bet ${patid}_DWI ${patid}_DWI_brain -f 0.3 -R
		if($status) exit 1
		
		fast -B -b -I 10 -l 10 -t 2 ${patid}_DWI_brain
		if($status) exit 1
		
		fslmaths ${patid}_DWI -div ${patid}_DWI_brain_bias ${patid}_DWI
		if($status) exit 1
				
		flirt -in ${patid}_DWI_brain_restore -ref ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_brain_restore -omat ${patid}_DWI_to_${patid}_T1.mat -dof 6
		if($status) exit 1
		
		flirt -in ${patid}_DWI -ref ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1 -out ${patid}_DWI_on_${patid}_T1
		if($status) exit 1
		
		#see if we want to check how far a voxel displaces
		if($MaximumRegDisplacement != 0) then
			flirt -in ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1 -ref ${patid}_DWI -omat ${patid}_T1_to_${patid}_DWI_rev.mat -cost mutualinfo -searchcost mutualinfo
			if($status) exit 1
			
			set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_brain_restore ${patid}_DWI ${patid}_DWI_to_${patid}_T1.mat ${patid}_T1_to_${patid}_DWI_rev.mat 0 50 0`
			echo "2 way registration displacement: $Displacement"
			
			if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_brain_restore ${patid}_DWI ${patid}_DWI_to_${patid}_T1.mat ${patid}_T1_to_${patid}_DWI_rev.mat 0 50 0 $MaximumRegDisplacement`) then
				decho "	Error: Registration from DWI to T1 and DWI to T1 has a displacement of "$Displacement
				exit 1
			endif
		endif
	
		if($target != "") then
			convert_xfm -omat ${patid}_DWI_to_${AtlasName}.mat -concat ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_to_${AtlasName}.mat ${patid}_DWI_to_${patid}_T1.mat
			if($status) exit 1
		endif
		
		if($NonLinear) then
			convertwarp --ref=$target --premat=${patid}_DWI_to_${patid}_T1.mat --warp=${SubjectHome}/Anatomical/Volume/T1/$patid"_T1_warpfield_111.nii.gz" --out=${patid}_DWI_warpfield_111.nii.gz
			if($status) exit 1
			
			applywarp -i ${patid}_DWI -ref $target -w ${patid}_DWI_warpfield_111.nii.gz -o ${patid}_DWI_111
			if($status) exit 1
			
			applywarp -i ${patid}_DWI -ref ${target}_${FinalResTrailer} -w ${patid}_DWI_warpfield_${FinalResTrailer}.nii.gz -o ${patid}_DWI_${FinalResTrailer}
			if($status) exit 1
		endif
	cd ..
popd
