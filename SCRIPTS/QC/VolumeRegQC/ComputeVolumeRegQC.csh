#!/bin/csh

source $1
source $2

#compute and export anatomical transform information

set SubjectHome = $cwd
set SubjectFolderHome = $cwd:h

#compute Eta's
rm -rf QC/ETA.txt
touch QC/ETA.txt

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if(! $?Reg_Target) then
	set Reg_Target = T1
endif

if(-e ${target}.nii) then
	set target_extension = "nii"
else
	set target_extension = "nii.gz"
endif

if(-e ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111.nii.gz && ! $?day1_patid) then
	rm -f ${SubjectHome}/QC/temp.txt
	if($NonLinear) then
		#MPR->NonLinAtl ETA
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${target}.nii.gz', '${target}_brain_mask.nii.gz', '${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		echo "Non-Linearly Aligned T1 ->"`basename $target`" : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
	endif
	rm -f ${SubjectHome}/QC/temp.txt
	#linear mpr -> atl
	matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${target}.nii.gz', '${target}_brain_mask.nii.gz', '${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
	echo "Linearly Aligned T1 ->"`basename $target`" : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
endif

if(-e ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111.nii.gz && ! $?day1_patid) then
	#t2 transform/warp -> atl
	rm -f ${SubjectHome}/QC/temp.txt
	
	if($NonLinear) then
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz', '${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		echo "Non-Linearly Aligned T2 -> T1 : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
	endif
	
	rm -f ${SubjectHome}/QC/temp.txt
	matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels.nii.gz', '${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
	echo "Linearly Aligned T2 -> T1 : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
endif

if(-e ${SubjectHome}/Anatomical/Volume/FLAIR/${patid}_FLAIR_111.nii.gz && ! $?day1_patid) then
	rm -f ${SubjectHome}/QC/temp.txt
	#flair to T1
	if($NonLinear) then
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz', '${SubjectHome}/Anatomical/Volume/FLAIR/${patid}_FLAIR_111_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		echo "Non-Linearly Aligned FLAIR -> T1 : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
	endif
	
	rm -f ${SubjectHome}/QC/temp.txt
	matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels.nii.gz', '${SubjectHome}/Anatomical/Volume/FLAIR/${patid}_FLAIR_111.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
	echo "Linearly Aligned FLAIR -> T1 : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
endif

if($?BOLD) then
	rm -f ${SubjectHome}/QC/temp.txt
	if($?day1_patid) then
		if($NonLinear) then
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${day1_path}/Anatomical/Volume/BOLD_ref/${day1_patid}_BOLD_ref_${FinalResTrailer}_fnirt.nii.gz', '${day1_path}/Masks/${day1_patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		else
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${day1_path}/Anatomical/Volume/BOLD_ref/${day1_patid}_BOLD_ref_${FinalResTrailer}.nii.gz', '${day1_path}/Masks/${day1_patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		endif
		echo "Final Aligned + Distortion Corrected BOLD_ref -> ${day1_patid} BOLD_ref : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
		
	else
		#non-linear bold -> distortion correction -> T2 -> mpr -> atl
		#this will work on crossday too. For multisession beyond the 1st, this reflects
		#Session N -> Session 1 -> Session 1 Distortion correction -> Session 1 T2 -> Session 1 MPR -> atl
		if($NonLinear) then
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${target}_${FinalResTrailer}.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		else
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${target}_${FinalResTrailer}.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		endif
		echo "Final Aligned + Distortion Corrected BOLD_ref ->"`basename $target`" : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
		
		#compute the similarity between the final bold and the target anatomical image
		if($NonLinear) then
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		else
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		endif
		echo "Final Aligned + Distortion Corrected BOLD_ref ->"${Reg_Target}" : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
	endif
endif

if($?ASL) then
	
	#output each ASL runs registration to asl1
	if($?day1_path) then 
		set targ_path = $day1_path
		set targ_patid = $day1_patid
	else
		set targ_path = $SubjectHome
		set targ_patid = $patid
	endif
	@ i = 1
	while($i <= $#ASL)
		rm -f ${SubjectHome}/QC/temp.txt
		if($NonLinear) then
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${target}_${FinalResTrailer}.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/asl${i}_ref/${patid}_asl${i}_ref_${ASL_ped[$i]}_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		else
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${target}_${FinalResTrailer}.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/asl${i}_ref/${patid}_asl${i}_ref_${ASL_ped[$i]}_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		endif
		echo "Final Aligned + Distortion Corrected asl${i}_ref ->"`basename $target`" : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
		
		#compute the similarity between the final bold and the target anatomical image
		if($NonLinear) then
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/asl${i}_ref/${patid}_asl${i}_ref_${ASL_ped[$i]}_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		else
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/asl${i}_ref/${patid}_asl${i}_ref_${ASL_ped[$i]}_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		endif
		echo "Final Aligned + Distortion Corrected asl${i}_ref ->"${Reg_Target}" : "`cat ${SubjectHome}/QC/temp.txt` >> QC/ETA.txt
		
		@ i++
	end
endif

rm -f QC/temp.txt

if($?mprs && ! $?day1_patid) then
	pushd QC
		#generate the structural ETA image
		echo matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/SurfacePipeline/QC_scripts'));ComputeStructuralETA('${target}_${FinalResTrailer}.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}_fnirt.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', [3 3 3]);end;exit"
		
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/SurfacePipeline/QC_scripts'));ComputeStructuralETA('${target}_${FinalResTrailer}.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}_fnirt.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', [3 3 3]);end;exit"

		$PP_SCRIPTS/QC/VolumeRegQC/gen_StructuralETAscenes.sh $SubjectFolderHome $patid $cwd
		$PP_SCRIPTS/QC/VolumeRegQC/capture_StructuralETAscenes.sh $cwd $patid $cwd 1920 1080
	popd
endif
#compute edge overlap of the linear and non-linear brains
if($?mprs && ! $?day1_patid) then
	pushd QC
	rm EdgeOverlap.txt
	touch EdgeOverlap.txt
	
		rm -r Edges
		mkdir Edges
		pushd Edges
			#make the atlas edge mask
			fslmaths ${target}_brain_mask -ero -mul -1 -add 1 target_brain_mask_ero
			fslmaths ${target}_brain_mask -mul target_brain_mask_ero target_brain_mask_ero_edges
			
			#make the linear participant edge mask
			fslmaths ${SubjectHome}/Masks/${patid}_used_voxels.nii.gz -ero -mul -1 -add 1 ${patid}_brain_mask_ero
			fslmaths ${SubjectHome}/Masks/${patid}_used_voxels.nii.gz -mul ${patid}_brain_mask_ero ${patid}_brain_mask_ero_edges
			
			#make the non-linear participant edge mask
			fslmaths ${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz -ero -mul -1 -add 1 ${patid}_brain_fnirt_mask_ero
			fslmaths ${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz -mul ${patid}_brain_mask_ero ${patid}_brain_fnirt_mask_ero_edges
		popd
		
		rm -f ${SubjectHome}/QC/temp.txt
		if($NonLinear) then
			#MPR->NonLinAtl ETA
			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeMaskOverlap('${SubjectHome}/QC/Edges/target_brain_mask_ero_edges.nii.gz', '${SubjectHome}/QC/Edges/${patid}_brain_fnirt_mask_ero_edges.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
			echo "Non-Linearly T1 Edge Overlap ->"`basename $target`" : "`cat ${SubjectHome}/QC/temp.txt` >> EdgeOverlap.txt
		endif
		rm -f ${SubjectHome}/QC/temp.txt
		#linear mpr -> atl
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));ComputeMaskOverlap('${SubjectHome}/QC/Edges/target_brain_mask_ero_edges.nii.gz', '${SubjectHome}/QC/Edges/${patid}_brain_mask_ero_edges.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		echo "Linearly T1 Edge Overlap ->"`basename $target`" : "`cat ${SubjectHome}/QC/temp.txt` >> EdgeOverlap.txt
		rm -f ${SubjectHome}/QC/temp.txt
	popd	
endif

#combine all the registration displacements into a single file.
if($?MaximumDisplacement) then
	ftouch ${SubjectHome}/QC/RegistrationDisplacements.txt
	
	foreach modality(${SubjectHome}/Anatomical/Volume/*)
		if(-e $modality/registration_displacement.txt) then
			set Mode = `basename $modality | cut -d_ -f2,3,4`
			set Displacement = `cat $modality/registration_displacement.txt | awk '{print($NF)}'`
			
			echo $Mode" : "$Displacement >> ${SubjectHome}/QC/RegistrationDisplacements.txt
		endif
	end
endif
rm -f ${SubjectHome}/QC/temp.txt
exit 0
