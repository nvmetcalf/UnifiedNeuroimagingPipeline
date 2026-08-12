#!/bin/csh

source $1
source $2

if(! $?T2) exit 0

set SubjectHome = $cwd

#compute Eta's
if($?day1_path) then
	set day1_patid = $day1_path:t
endif

set target = ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111
set target_mask = ${SubjectHome}/Masks/${patid}_used_voxels_T1_111


if(-e ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111.nii.gz && ! $?day1_patid) then
	#t2 transform/warp -> atl
	rm -f ${SubjectHome}/QC/temp.txt
	
	if($NonLinear) then
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('$FREESURFER_HOME/matlab'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_111_fnirt.nii.gz', '${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_111_fnirt.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		echo "Non-Linearly Aligned T2 -> T1 : "`cat ${SubjectHome}/QC/temp.txt` >> QC/SpatialCorrelation.txt
	endif
	
	rm -f ${SubjectHome}/QC/temp.txt
	matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('$FREESURFER_HOME/matlab'));ComputeAnatomicalVolumeCorrelation('${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_111.nii.gz', '${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_111.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
	echo "Linearly Aligned T2 -> T1 : "`cat ${SubjectHome}/QC/temp.txt` >> QC/SpatialCorrelation.txt
endif

rm -f ${SubjectHome}/QC/temp.txt
