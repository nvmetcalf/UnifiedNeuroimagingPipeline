#!/bin/csh

set patid = $1
set SubjectHome = $2

#put the OEF, brain, masks into full resolution t1 space
rm -r PVC
mkdir PVC

flirt -in ${patid}_ase_0_brain_mask.nii.gz -ref ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111 -out PVC/${patid}_ase_0_brain_mask_T1_111 -applyxfm -init $PP_SCRIPTS/Registration/identity.mat -interp nearestneighbour
if($status) exit 1

flirt -in ${patid}_ase_0_brain.nii.gz -ref ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111 -out PVC/${patid}_ase_0_brain_T1_111 -applyxfm -init $PP_SCRIPTS/Registration/identity.mat
if($status) exit 1

foreach seg(*_t1_spm_*.nii.gz)
	flirt -in $seg -ref ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111 -out PVC/${seg:r:r}_111 -applyxfm -init $PP_SCRIPTS/Registration/identity.mat -interp nearestneighbour
	if($status) exit 1
end
foreach ase(${patid}_ase*_upck_xr3d_dc_atl.nii.gz)
	flirt -in $ase -ref ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111 -out PVC/${ase:r:r}_111 -applyxfm -init $PP_SCRIPTS/Registration/identity.mat
	if($status) exit 1
end

