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

if(! $?IncludeSubCortical) set IncludeSubCortical = 0
if(! $?TimeseriesTrailerToProject) set TimeseriesTrailerToProject = ""

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"
set SubjectHome = $cwd
set SubcorticalGrayLabels="${HCPPIPEDIR_Config}/FreeSurferSubcorticalLabelTableLut.txt"

if($TimeseriesTrailerToProject == "" && ! $DoSurfaceRegression) then
	set fcFileName = ${SubjectHome}/Functional/Volume/${patid}"_rsfMRI_uout_bpss_resid"
else if($TimeseriesTrailerToProject == ""  && $DoSurfaceRegression) then
	set fcFileName = ${SubjectHome}/Functional/Volume/${patid}"_rsfMRI_uout_bpss"
else
	set fcFileName = ${SubjectHome}/Functional/Volume/${patid}$TimeseriesTrailerToProject:r:r
endif

if(! -e $fcFileName.nii.gz && ! -e $fcFileName.nii) then
	decho "No metric data to sample (bold/asl/etc.). Skipping..." $DebugFile
	exit 0
endif

#default to 6mm smoothing - this effectively disables smoothing as it will be done
#by the user at their discression
set Sigma=`echo "0.000000000000000001 / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`

set GrayordinatesSpaceDIR="${HCPPIPEDIR_Templates}/91282_Greyordinates" #(Need to copy these in)
set GrayordinatesResolution="2" #Usually 2mm

decho "Using "$fcFileName" as BOLD to be projected." $DebugFile

set HighResMesh="164" #Usually 164k vertices

if($target != "") then
	set AtlasName = `basename $target`
else
	set AtlasName = T1
	set IncludeSubCortical = 0
endif

set AtlasSpaceFolder="Anatomical/Surface"

pushd $AtlasSpaceFolder
	# Surface Processing
	decho "Begin surface BOLD processing" $DebugFile

	rm ${SubjectHome}/Functional/Volume/$fcFileName:t"_SBRef.nii.gz"
	if($NonLinear) then
		ln -s ${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}_fnirt.nii.gz ${SubjectHome}/Functional/Volume/$fcFileName:t"_SBRef.nii.gz"
		if($status) exit 1
	else
		ln -s ${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}.nii.gz ${SubjectHome}/Functional/Volume/$fcFileName:t"_SBRef.nii.gz"
		if($status) exit 1
	endif
	
	#Surface Commands
	decho "Volume to Surface" $DebugFile
	"$HCPPIPEDIR_fMRISurf"/RibbonVolumeToSurfaceMapping.sh ${SubjectHome}/"$AtlasSpaceFolder"/RibbonVolumeToSurfaceMapping "$fcFileName" "$patid" ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k "$LowResMesh" ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k ${fcFileName}.nii.gz
	if($status) exit 1

	#move the results from the Functional/Volume Folder to Functional/Surface
	mv ${SubjectHome}/Functional/Volume/*.gii ${SubjectHome}/Functional/Surface
	if($status) exit 1

	SUBCORT:
	if($IncludeSubCortical) then
		#do the sub cortical extraction
		decho "Creating sub-cortical volume" $DebugFile
		decho $cwd $DebugFile

		#get the subcortical regions from the mni template brain that we have aligned to
		${CARET7DIR}/wb_command -volume-label-import ${target}_wmparc_${FinalResTrailer}.nii.gz ${SubcorticalGrayLabels} ROIs.${FinalResolution}.nii.gz
		if($status) exit 1

		#extract the sub cortical voxels
		${CARET7DIR}/wb_command -volume-parcel-resampling "$fcFileName".nii.gz ROIs.${FinalResolution}.nii.gz ROIs.${FinalResolution}.nii.gz $Sigma ${ScratchFolder}/${patid}/AtlasSubcortical.nii.gz -fix-zeros
		if($status) exit 1
	else
		decho "skipping creation of sub-cortical volume" $DebugFile
	endif

	decho "Creating atlas space functional surface." $DebugFile
	"$HCPPIPEDIR_fMRISurf"/CreateSurface_cii.sh ${SubjectHome}/"$AtlasSpaceFolder"/"$AtlasName"_${LowResMesh}k "$patid" "$LowResMesh" ${SubjectHome}/Functional/Surface/`basename ${fcFileName}` "$AtlasSpaceFolder" "${SubjectHome}/Functional/Surface/`basename ${fcFileName}`.ctx" "$GrayordinatesResolution" $ScratchFolder/${patid}/AtlasSubcortical.nii.gz $IncludeSubCortical $BOLD_TR $FinalResolution
	if($status) then
		decho "Failed to create functional surfaces."	
		exit 1
	endif

	if( -e $ScratchFolder/${patid}/AtlasSubcortical.nii.gz) then
		rm -f $ScratchFolder/${patid}/AtlasSubcortical.nii.gz
	endif
	
	rm -f ${SubjectHome}/Functional/Surface/*.gii

	#if we didn't do volume denoising, do it on the surface if requested
	if($DoSurfaceRegression && -e ${SubjectHome}/Functional/Regressors/${patid}_all_regressors.dat) then

 		pushd ${SubjectHome}/Functional/Volume/
 			if(! -e ${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt) then
 				decho "Unable to find rsfMRI_tmask.txt. Cannot perform nuissance regression on the surface." $DebugFile
 				exit 1
 			endif
 
 			echo "matlab -nodesktop -nosplash -r addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));fs_surfproc_v3_1('${SubjectHome}/Functional/Surface/$fcFileName:t.ctx.dtseries.nii','${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt',${BOLD_TR},[],'${SubjectHome}/Functional/Regressors/${patid}_all_regressors.dat');exit" >> $DebugFile
 			matlab -nodesktop -nosplash -r "addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));fs_surfproc_v3_1('${SubjectHome}/Functional/Surface/$fcFileName:t.ctx.dtseries.nii','${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt',${BOLD_TR},[],'${SubjectHome}/Functional/Regressors/${patid}_all_regressors.dat');exit"
 		popd
		
	endif
	
	#smooth the surface and subcortical areas after everything is done
	if($SurfSmoothingFWHM != 0) then
		pushd ${SubjectHome}/Functional/Surface
			echo "Smoothing dtseries using $SurfSmoothingFWHM mm gaussian kernel"

			set Sigma=`echo "$SurfSmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
			set smoothing = $SurfSmoothingFWHM
			
			if(-e `basename ${fcFileName}`".ctx.dtseries.nii") then
				wb_command -cifti-smoothing `basename ${fcFileName}`".ctx.dtseries.nii" $Sigma $Sigma COLUMN `basename ${fcFileName}`"_sm${SurfSmoothingFWHM}.ctx.dtseries.nii" -left-surface ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/$patid.L.midthickness.${LowResMesh}k_fs_LR.surf.gii -right-surface ${SubjectHome}/${AtlasSpaceFolder}/${AtlasName}_${LowResMesh}k/$patid.R.midthickness.${LowResMesh}k_fs_LR.surf.gii
				if($status) then
					decho "Failed to smooth ${fcFileName}.ctx.dtseries.nii" $DebugFile
					exit 1
				endif
			endif
			
			if(-e `basename ${fcFileName}`"_sr.ctx.dtseries.nii") then
				wb_command -cifti-smoothing `basename ${fcFileName}`"_sr.ctx.dtseries.nii" $Sigma $Sigma COLUMN `basename ${fcFileName}`"sr_sm${SurfSmoothingFWHM}.ctx.dtseries.nii" -left-surface ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/$patid.L.midthickness.${LowResMesh}k_fs_LR.surf.gii -right-surface ${SubjectHome}/${AtlasSpaceFolder}/${AtlasName}_${LowResMesh}k/$patid.R.midthickness.${LowResMesh}k_fs_LR.surf.gii
				if($status) then
					decho "Failed to smooth ${fcFileName}.ctx.dtseries.nii" $DebugFile
					exit 1
				endif
			endif
		popd
	endif
popd

exit 0
