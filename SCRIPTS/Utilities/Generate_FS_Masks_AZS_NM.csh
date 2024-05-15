#!/bin/csh
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/Generate_FS_Masks_AZS.csh,v 1.4 2014/06/02 21:27:53 avi Exp $
#$Log: Generate_FS_Masks_AZS.csh,v $
# Revision 1.4  2014/06/02  21:27:53  avi
# typo
#
# Revision 1.3  2014/06/02  02:54:57  avi
# tolerate $day1_patid == ""
#
# Revision 1.2  2014/02/22  03:31:33  avi
# note $?day1_patid and set patid accordingly
#
# Revision 1.1  2014/02/22  03:03:51  avi
# Initial revision
#
# NM: Sep 24, 2015: Updated to use non-linear registrations from 1st day or same day
# NM: Jan 15, 2021: Updated to remove all 4dfp calls
set program = $0; set program = $program:t

set rcsid = '$Id: Generate_FS_Masks_AZS.csh,v 1.4 2014/06/02 21:27:53 avi Exp $'
echo $rcsid

if (${#argv} < 1) then
	echo "Usage:	$program <parameters file> [instructions]"
	echo "e.g.,	$program FCS_039_A_1.params ../uwrp_process_Stroke_SMG_Subjects.params"
	exit 1
endif
date
uname -a


if (! -e $1) then
	echo "$1 not found!"
	exit 1
endif

if (! -e $2) then
	echo "$2 not found!"
	exit 1
endif

source $1
source $2

set SubjectHome = $cwd

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"


if (! ${?day1_patid}) set day1_patid = ""
if (! ${?day1_path}) set day1_path = ""

if($target != "") then
	set AtlasName = `basename $target`
else
	if($day1_path == "") then
		set AtlasName = ${patid}_T1
	else
		set AtlasName = ${day1_patid}_T1
	endif
endif

if ($day1_patid != "" || $day1_path != "") then
	set WarpField = ${day1_path}/Anatomical/Volume/T1/${day1_patid}"_T1_warpfield_111.nii.gz"
	set OrigToATL_mat = ${day1_path}/Masks/FreesurferMasks/${day1_patid}_orig_to_${AtlasName}.mat
	set FSdir = ${day1_path}/Freesurfer
else
	set WarpField = ${SubjectHome}/Anatomical/Volume/T1/${patid}"_T1_warpfield_111.nii.gz"
	set OrigToATL_mat = ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${AtlasName}.mat
	set FSdir = ${SubjectHome}/Freesurfer
endif

echo "patid	=" $patid
echo "AtlasName	=" $AtlasName

set GMasegnames	= $FSdir/${patid}_GM_roinames.txt
set WMasegnames	= $FSdir/${patid}_WM_roinames.txt
set CSFsegnames	= $FSdir/${patid}_CS_roinames.txt
set GMkeeprgns	= ( 7 8 10 11 12 13 16 17 18 26 28 46 47 49 50 51 52 53 54 58 60 )
set WMkeeprgns	= ( 2 41 )
set CSFeeprgns	= ( 4 14 15 43 )

##################################
# check existence of prerequisites
##################################
if (! -e ${SubjectHome}/Anatomical/Volume/T1 && $day1_path == "") then
	echo ${SubjectHome}/Anatomical/Volume/T1 not found
	exit 1
endif
if (! -e $FSdir) then
	echo $program": "$FSdir not found
	exit 1
endif
if (! -r $FSdir/mri/orig.mgz && $day1_path == "") then
	echo $program": "read enabled $FSdir/mri/orig.mgz not found
	exit 1
endif
if (! -r $FSdir/mri/aparc+aseg.mgz && $day1_path == "") then
	echo $program": "read enabled $FSdir/mri/aparc+aseg.mgz not found
	exit 1
endif

################
# check to make sure we have the transform from the previous module. It must exist.
################

if( ! -e $OrigToATL_mat) then
	echo "Freesurfer orig to atlas registration did not complete in c. Cannot continue."
	exit 1
endif

########################
# apply t4 to aseg image
########################
echo "Transforming aparc+aseg into atlas space."

rm -rf $ScratchFolder/${patid}/FS_Masks_temp
mkdir $ScratchFolder/$patid/FS_Masks_temp
pushd $ScratchFolder/$patid/FS_Masks_temp

	#figure out which used_voxels mask we should use
	if($NonLinear) then
		set UsedVoxelsMask = ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz
	else 
		set UsedVoxelsMask = ${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz
	endif

	echo "UsedVoxelsMask = $UsedVoxelsMask"
	if(! -e $UsedVoxelsMask) then
		decho "Could not find $UsedVoxelsMask. Unable to continue." $DebugFile
		exit 1
	endif

	#DO SOMETHING THAT WILL ALLOW MULTISESSION DATA TO MAKE THEIR OWN MASKS AND MASK BY CURRENT PATHOLOGY
	if($day1_path == "") then
		$FREESURFER_HOME/bin/mri_convert -it mgz -ot nii $FSdir/mri/aparc+aseg.mgz ${patid}_aparc+aseg.nii
		if ($status) exit $status
	else
		$FREESURFER_HOME/bin/mri_convert -it mgz -ot nii ${day1_path}/Freesurfer/mri/aparc+aseg.mgz ${patid}_aparc+aseg.nii
		if ($status) exit $status
	endif

	#if we are using non-linear registration, apply the warpfield to the aparc+aseg
	#this will ensure that all masks derived from the aparc+aseg are also non-linearly
	#warped to the atlas like the BOLD has been.
	if(! $NonLinear && $target != "") then
		flirt -in ${patid}_aparc+aseg.nii -ref $UsedVoxelsMask -init ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${AtlasName}.mat -applyxfm -interp nearestneighbour -out ${patid}_aparc+aseg_on_${AtlasName}
		if($status) exit 1
		
		set asegimg = ${patid}_aparc+aseg_on_${AtlasName}_${FinalResTrailer}
	else if($NonLinear && $target != "") then
		set asegimg = ${patid}_aparc+aseg_on_${AtlasName}_fnirt_${FinalResTrailer}
	
		$FSLBIN/applywarp -i ${patid}_aparc+aseg -o ${asegimg} -r $UsedVoxelsMask -w ${WarpField} --interp=nn --premat=${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat
		if($status) exit 1
	else
		set asegimg = ${patid}_aparc+aseg_on_${AtlasName}_${FinalResTrailer}
		flirt -in ${patid}_aparc+aseg.nii -ref $UsedVoxelsMask -init ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat -applyxfm -interp nearestneighbour -out ${patid}_aparc+aseg_on_${AtlasName}
		if($status) exit 1
		
		flirt -in ${patid}_aparc+aseg_on_${AtlasName} -ref ${patid}_aparc+aseg_on_${AtlasName} -out ${patid}_aparc+aseg_on_${AtlasName}_${FinalResTrailer} -applyisoxfm $FinalResolution -interp nearestneighbour
		if($status) exit 1
	endif

	cp $asegimg.nii.gz ${SubjectHome}/Masks/FreesurferMasks/
	if($status) exit 1
	
	CREATE_MASKS:
	################
	# create WB mask
	################
	if (! -d aseg_split) mkdir aseg_split
	if ($status) exit $status

	fslmaths $asegimg -bin ${SubjectHome}/Masks/FreesurferMasks/${patid}_FSWB_on_${AtlasName}_${FinalResTrailer}.nii.gz
	if($status) exit 1
		
	###########################
	# initialize ROI list files
	###########################
	ftouch $GMasegnames
	ftouch $WMasegnames
	ftouch $CSFsegnames

	########################
	# build grey matter mask
	########################
	echo "building grey matter mask"

	#create the base image
	fslmaths ${asegimg} -mul 0 ${patid}_GM_on_${AtlasName}.nii.gz
	if($status) exit 1
	
	foreach r ( $GMkeeprgns )
		fslmaths ${asegimg} -thr $r -uthr $r -bin ${r}
		if ($status) exit $status

		fslmaths ${patid}_GM_on_${AtlasName} -add ${r}.nii.gz -bin ${patid}_GM_on_${AtlasName}.nii.gz
		if ($status) exit $status
	end
	
	fslmaths ${asegimg} -thr 1000 -uthr 2999 -bin ${asegimg}_ctx
	if ($status) exit $status

	fslmaths ${patid}_GM_on_${AtlasName} -add ${asegimg}_ctx -bin -mul -1 -add 1 ${SubjectHome}/Masks/FreesurferMasks/${patid}_GM_on_${AtlasName}_${FinalResTrailer}.nii.gz
	if ($status) exit $status

	###############
	# build WM mask
	###############
	echo "building white matter mask"

	#make a blank image that we can add voxels to
	fslmaths ${asegimg} -mul 0 ${patid}_WM_on_${AtlasName}.nii.gz
	if($status) exit 1
	
	foreach r ( $WMkeeprgns )
		fslmaths ${asegimg} -thr $r -uthr $r -bin $r
		if($status) exit 1
		
 		fslmaths ${patid}_WM_on_${AtlasName} -add ${r}.nii.gz -bin ${patid}_WM_on_${AtlasName}.nii.gz
		if ($status) exit $status
	end
	
	fslmaths ${patid}_WM_on_${AtlasName} -bin ${SubjectHome}/Masks/FreesurferMasks/${patid}_WM_on_${AtlasName}_${FinalResTrailer}
	if($status) exit 1
	
	################
	# build CSF mask
	################
	echo "building csf mask"
	fslmaths ${asegimg} -mul 0 ${patid}_CSF_on_${AtlasName}.nii.gz
	if($status) exit 1
	
	foreach r ( $CSFeeprgns )
#
		fslmaths ${asegimg} -thr $r -uthr $r -bin $r
		if($status) exit 1
		
 		fslmaths ${patid}_CSF_on_${AtlasName} -add ${r}.nii.gz -bin ${patid}_CSF_on_${AtlasName}.nii.gz
		if ($status) exit $status

	end
	
	#remove all gray matter voxels from the CSF mask
	fslmaths ${patid}_CSF_on_${AtlasName} -bin ${SubjectHome}/Masks/FreesurferMasks/${patid}_CSF_on_${AtlasName}_${FinalResTrailer}
	if($status) exit 1
	
popd

echo $program sucessfully completed
exit 0
