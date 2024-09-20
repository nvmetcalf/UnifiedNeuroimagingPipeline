#!/bin/csh

source $1
source $2

set concroot	= $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI
set conc	= $concroot.conc
set SubjectHome = $cwd

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

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"
@ nframe  = `wc ${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt | awk '{print $2}'`


if( ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz) then
	set DVAR_Threshold = 0
	decho "WARNING: Disabling DVAR threshold as denoised timeseries does not exist!"
endif

if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
	set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_dvar.format
else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
	set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format
else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
	set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_resid_dvar_fd.format
else
	decho "Unknown combination of format criteria. Iterative rsfMRI processing not possible." ${DebugFile}
	exit 1
endif
	

###########################
# make ventricle regressors
###########################

pushd ${SubjectHome}/Masks/FreesurferMasks
	fslmaths ${SubjectHome}/Masks/FreesurferMasks/${patid}_CSF_on_${AtlasName}_${FinalResTrailer} ${SubjectHome}/Masks/FreesurferMasks/${patid}_CSF_on_${AtlasName}_${FinalResTrailer}
	if($status) exit 1
	
	niftigz_4dfp -4 ${SubjectHome}/Masks/FreesurferMasks/${patid}_CSF_on_${AtlasName}_${FinalResTrailer} temp
	if($status) exit 1
	
	cluster_4dfp temp -n15
	if($status) exit 1
	
	maskimg_4dfp temp_clus ${concroot}_dfnd ${patid}_Ventricle_mask
	if($status) exit 1
	
	niftigz_4dfp -n ${patid}_Ventricle_mask ${patid}_Ventricle_mask
	if($status) exit 1
	
	rm temp*
popd

pushd ${SubjectHome}/Functional/Regressors
	@ n = `echo $CSF_lcube | awk '{print int($1^3/2)}'`	# minimum cube defined voxel count is 1/2 total
	qntv_4dfp ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_Ventricle_mask -F$format -l$CSF_lcube -t$CSF_svdt -n$n -D -O4 -o${patid}_Ventricle_regressors.dat
	if ($status) then

		#fall back on the atlas segmentation if possible
		#if(-e ${target}_CS_erode_on_${AtlasName}_${FinalResTrailer}_clus.4dfp.img) then
		if(-e ${target}_CSF_${FinalResTrailer}.nii.gz || -e ${target}_CSF_${FinalResTrailer}.nii) then
			decho "Segmented Ventricle mask has no voxels (probably unusually small ventricles). Using Atlas segmentation." $DebugFile
				
			if( -e ${target}_CSF_${FinalResTrailer}.nii.gz) then
				niftigz_4dfp -4 ${target}_CSF_${FinalResTrailer}.nii.gz ${AtlasName}_CSF_${FinalResTrailer}
			else
				nifti_4dfp -4 ${target}_CSF_${FinalResTrailer}.nii ${AtlasName}_CSF_${FinalResTrailer}
			endif
			
			if($status) exit 1
				
			maskimg_4dfp ${AtlasName}_CSF_${FinalResTrailer} ${concroot}_dfnd ${SubjectHome}/Masks/FreesurferMasks/${patid}_Ventricle_mask
			if($status) then
				decho "Could not mask atlas Ventricle segmentation by subjects dfnd." $DebugFile
				exit 1
			endif

			qntv_4dfp ${concroot}_uout_bpss.conc ${SubjectHome}/Masks/FreesurferMasks/${patid}_Ventricle_mask -F$format -l$CSF_lcube -t$CSF_svdt -n1 -D -O4 -o${patid}_Ventricle_regressors.dat
			if($status != 0) then #still no dice...somehow...
				decho "unable to compute ventricle regressors using atlas segmentation" $DebugFile
				exit 1
			endif
		else
			decho " unable to compute ventricle regressors (no atlas segmentation)" $DebugFile
			exit 1
		endif
	endif

	@ n = `wc ${patid}_Ventricle_regressors.dat | awk '{print $1}'`
	if ($n != $nframe) then
		decho "${patid}_mov_regressors.dat ${patid}_Ventricle_regressors.dat length mismatch" $DebugFile
		exit 1
	endif

popd

exit 0
