#!/bin/csh

source $1
source $2

if(! $?BOLD) exit 0

set SubjectHome = $cwd

#compute correlations's

if(! $?BOLD_FinalResolution) then
	set BOLD_FinalResolution = 3
endif

set FinalResTrailer = "${BOLD_FinalResolution}${BOLD_FinalResolution}${BOLD_FinalResolution}"

set Reg_Target = ${BOLD_Reg_Target}

if($?day1_path) then
	set day1_patid = $day1_path:t
endif



if(-e ${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}.nii.gz && ! $?day1_patid) then
	#t2 transform/warp -> atl
	rm -f ${SubjectHome}/QC/temp.txt
	
	if($NonLinear) then
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('$FREESURFER_HOME/matlab'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		echo "Non-Linearly Aligned BOLD_ref -> ${Reg_Target} : "`cat ${SubjectHome}/QC/temp.txt` >> QC/SpatialCorrelation.txt
	endif
	
	rm -f ${SubjectHome}/QC/temp.txt
	matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('$FREESURFER_HOME/matlab'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
	echo "Linearly Aligned BOLD_ref -> ${Reg_Target} : "`cat ${SubjectHome}/QC/temp.txt` >> QC/SpatialCorrelation.txt
endif
rm -f ${SubjectHome}/QC/temp.txt
