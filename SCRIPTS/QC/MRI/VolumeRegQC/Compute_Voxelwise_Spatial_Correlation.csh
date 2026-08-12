#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

if(! $?FinalResolution) then
	set FinalResolution = 1
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if($?T1 && ! $?day1_path) then
	pushd QC
		#generate the structural ETA image
		echo matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/SurfacePipeline/QC_scripts'));ComputeStructuralETA('${target}_${FinalResTrailer}.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}_fnirt.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', [3 3 3]);end;exit"
		
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/SurfacePipeline/QC_scripts'));ComputeStructuralETA('${target}_${FinalResTrailer}.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}_fnirt.nii.gz', '${target}_brain_mask_${FinalResTrailer}.nii.gz', [3 3 3]);end;exit"

		$PP_SCRIPTS/QC/MRI/VolumeRegQC/gen_StructuralETAscenes.sh $SubjectHome $patid $cwd
		$PP_SCRIPTS/QC/MRI/VolumeRegQC/capture_StructuralETAscenes.sh $cwd $patid $cwd 1920 1080
	popd
endif
