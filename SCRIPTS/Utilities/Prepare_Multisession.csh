#!/bin/csh
 
source $1
source $2
 
 if (! -e $1) then
	echo "$1 not found!"
	exit 1
endif

if (! -e $2) then
	echo "$2 not found!"
	exit 1
endif

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set SubjectHome = $cwd

#link up to the first sessions freesurfer
if(! -e ${day1_path}/Freesurfer) then
	decho "$day1_patid does not seem to have a Freesurfer folder." $DebugFile
	exit 1
endif

ln -sf ${day1_path}/Freesurfer .

#generate all the masks we will need to start things off
$PP_SCRIPTS/Utilities/Generate_UsedVoxels_Masks.csh $1 $2 $SubjectHome
if($status) then
	decho "Unable to generate UsedVoxels Masks for for current session." $DebugFile
	exit 1
endif
	

exit 0

# #!/bin/csh
# 
# source $1
# source $2
# 
# if(! $?FinalResolution) then
# 	set FinalResolution = 3
# endif
# 
# set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"
# 
# set SubjectHome = $cwd
# 
# ln -s ${day1_path}/Freesurfer .
# rm -r Masks
# mkdir Masks
# pushd Masks
# 	ln -s ${day1_path}/Masks/${day1_patid}_used_voxels.nii.gz ${patid}_used_voxels.nii.gz
# 	if($status) exit 1
# 	
# 	ln -s ${day1_path}/Masks/${day1_patid}_used_voxels_${FinalResTrailer}.nii.gz ${patid}_used_voxels_${FinalResTrailer}.nii.gz
# 	if($status) exit 1
# 	
# 	if($NonLinear) then
# 		ln -s ${day1_path}/Masks/${day1_patid}_used_voxels_fnirt.nii.gz ${patid}_used_voxels_fnirt.nii.gz
# 		if($status) exit 1
# 		
# 		ln -s ${day1_path}/Masks/${day1_patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz ${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz
# 		if($status) exit 1
# 		
# 	endif
# 	
# 	mkdir FreesurferMasks
# 	cd FreesurferMasks
# 		ln -s ${day1_path}/Masks/FreesurferMasks/${day1_patid}_orig_to_$target:t.mat ${patid}_orig_to_$target:t.mat 
# 		if($status) exit 1
# 		
# 		ln -s ${day1_path}/Masks/FreesurferMasks/${day1_patid}_orig_to_${day1_patid}_T1.mat ${patid}_orig_to_${patid}_T1.mat
# 		if($status) exit 1
# 				
# 		ln -s ${day1_path}/Masks/FreesurferMasks/${day1_patid}_orig.nii ${patid}_orig.nii
# 		if($status) exit 1
# 	cd ..
# popd
	
exit 0
