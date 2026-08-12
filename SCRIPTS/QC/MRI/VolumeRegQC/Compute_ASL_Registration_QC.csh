#!/bin/csh

source $1
source $2

if(! $?ASL) exit 0

set SubjectHome = $cwd

#compute correlations's

if(! $?ASL_FinalResolution) then
	set ASL_FinalResolution = 3
endif

set FinalResTrailer = "${ASL_FinalResolution}${ASL_FinalResolution}${ASL_FinalResolution}"

set Reg_Target = $ASL_Reg_Target

if($?day1_path) then
	set day1_patid = $day1_path:t
endif


	
if(-e ${SubjectHome}/Anatomical/Volume/ASL_ref/${patid}_ASL_ref_${FinalResTrailer}.nii.gz && ! $?day1_patid) then
	#t2 transform/warp -> atl
	rm -f ${SubjectHome}/QC/temp.txt
	
	if($NonLinear) then
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('$FREESURFER_HOME/matlab'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Anatomical/Volume/ASL_ref/${patid}_ASL_ref_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}_fnirt.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		echo "Non-Linearly Aligned ASL_ref -> ${Reg_Target} : "`cat ${SubjectHome}/QC/temp.txt` >> QC/SpatialCorrelation.txt
	endif
	
	rm -f ${SubjectHome}/QC/temp.txt
	matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('$FREESURFER_HOME/matlab'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/${Reg_Target}/${patid}_${Reg_Target}_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/Anatomical/Volume/ASL_ref/${patid}_ASL_ref_${FinalResTrailer}.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
	echo "Linearly Aligned ASL_ref -> ${Reg_Target} : "`cat ${SubjectHome}/QC/temp.txt` >> QC/SpatialCorrelation.txt
endif

	rm -f ${SubjectHome}/QC/temp.txt
