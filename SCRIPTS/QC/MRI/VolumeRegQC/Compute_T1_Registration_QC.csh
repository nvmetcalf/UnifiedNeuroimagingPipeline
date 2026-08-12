#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

#compute Eta's

if($?day1_path) then
	set day1_patid = $day1_path:t
endif

if($target == "") then
	set target = ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111
	set target_mask = ${SubjectHome}/Masks/${patid}_used_voxels_T1_111
else
	set target_mask = ${target}_brain_mask
endif

if(-e ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111.nii.gz && ! $?day1_path) then
	rm -f ${SubjectHome}/QC/temp.txt
	if($NonLinear) then
		#MPR->NonLinAtl SpatialCorrelation
		matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('$FREESURFER_HOME/matlab'));ComputeAnatomicalVolumeCorrelation('${target}.nii.gz', '${target_mask}.nii.gz', '${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111_fnirt.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_111_fnirt.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
		echo "Non-Linearly Aligned T1 ->"${target:t}" : "`cat ${SubjectHome}/QC/temp.txt` >> QC/SpatialCorrelation.txt
	endif
	rm -f ${SubjectHome}/QC/temp.txt
	#linear mpr -> atl
	matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('$FREESURFER_HOME/matlab'));ComputeAnatomicalVolumeCorrelation('${target}.nii.gz', '${target_mask}.nii.gz', '${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111.nii.gz', '${SubjectHome}/Masks/${patid}_used_voxels_111.nii.gz', '${SubjectHome}/QC/temp.txt');end;exit"
	echo "Linearly Aligned T1 ->"`basename $target`" : "`cat ${SubjectHome}/QC/temp.txt` >> QC/SpatialCorrelation.txt
endif

rm -f ${SubjectHome}/QC/temp.txt
