#!/bin/csh

if($#argv < 3) then
	echo "Projects a freesurfer subject surface space overlay to"
	echo "	gifti atlas aligned surface."
	echo "	Requires the subjects to complete both surface projection"
	echo "		and recon-all"
	echo "Run from the studies scratch folder (i.e. /scratch/SurfaceStroke)"
	echo " "
	echo "Usage: OverlayToGifti.csh <subject ID> <path to study folder> <overlay to resample im mgh or mgz format>"
	exit 1
endif
set echo
set Subject = $1
set SubjectsFolder = $2 
set Overlay = $3

setenv SUBJECTS_DIR $cwd

#creates a right hemisphere for the overlay to be sampled to
surfreg --s ${Subject} --t fsaverage_sym --lh
surfreg --s ${Subject} --t fsaverage_sym --lh --xhemi

#registers the overlay to the left hemisphere
mri_surf2surf --srcsubject fsaverage_sym --srcsurfreg sphere.reg --trgsubject ${Subject} --trgsurfreg fsaverage_sym.sphere.reg --hemi lh --sval ${Overlay} --tval $Overlay:r"_lh.mgh"
if($status) exit 1

#creates a gifti surface based on the whitematter surface (could use pial, doesn't matter in the end)
mris_convert -c ./$Overlay:r"_lh.mgh" ${Subject}/surf/lh.white $Overlay:r".L.func.gii"
if($status) exit 1

#takes the native gifti registration sphere that the given subject has and registers the metric we jsut created 
#to the 164k surface for the subject. Coincidentally since we are registering to that surface, the resampled
#metric will also work on every subject
wb_command -metric-resample $Overlay:r".L.func.gii" ${SubjectsFolder}/${Subject}/atlas/Native/${Subject}.L.sphere.reg.reg_LR.native.surf.gii ${SubjectsFolder}/${Subject}/atlas/fsaverage_LR164k/${Subject}.L.sphere.164k_fs_LR.surf.gii BARYCENTRIC $Overlay:r".L.164k.func.gii"
if($status) exit 1

#does the same operations for the right hemisphere
mri_surf2surf --srcsubject fsaverage_sym --srcsurfreg sphere.reg --trgsubject ${Subject}/xhemi --trgsurfreg fsaverage_sym.sphere.reg --hemi lh --sval ${Overlay} --tval $Overlay:r"_rh.mgh"
if($status) exit 1
mris_convert -c ./$Overlay:r"_rh.mgh" ${Subject}/surf/rh.white $Overlay:r".R.func.gii"
if($status) exit 1
wb_command -metric-resample $Overlay:r".R.func.gii" ${SubjectsFolder}/${Subject}/atlas/Native/${Subject}.R.sphere.reg.reg_LR.native.surf.gii ${SubjectsFolder}/${Subject}/atlas/fsaverage_LR164k/${Subject}.R.sphere.164k_fs_LR.surf.gii BARYCENTRIC $Overlay:r".R.164k.func.gii"
if($status) exit 1
