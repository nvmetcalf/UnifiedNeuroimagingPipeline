#!/bin/csh
#CDH 7/22/2013
#Sept2012

set log  = surface_projection_pipeline_log_08082013.log

setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

if($#argv < 2) then
	echo "surface_projection_pipeline <Subject.params> <ProcessingParemeters.params>"
	exit 1
endif

set StudyFolder = $cwd #Path to overall patients folder

set ReferenceMyelinMaps="${HCPPIPEDIR_Templates}/standard_mesh_atlases/Conte69.MyelinMap_BC.164k_fs_LR.dscalar.nii"

setenv FSOUT ""
set T1wFolder="Anatomical/Volume/T1" #Location of T1w images
set AtlasSpaceFolder="Anatomical/Surface"
set NativeFolder="Native"
set HighResMesh="164" #Usually 164k vertices
set LowResMesh="10" #Usually 32k vertices
set SmoothingFWHM=0
set T1wImageBrainMask="${StudyFolder}/Anatomical/Surface/native_mask"
set SurfaceAtlasDIR="${HCPPIPEDIR_Templates}/standard_mesh_atlases" #(Need to rename make surf.gii and add 32k)
set FreeSurferLabels="${HCPPIPEDIR_Config}/FreeSurferAllLut.txt"
set GrayordinatesSpaceDIR="${HCPPIPEDIR_Templates}/91282_Greyordinates" #(Need to copy these in)
set GrayordinatesResolution="2" #Usually 2mm

set DoVolumeRegression = 1
set DoSurfaceRegression = 1

#nick - overrides previously defined variables
if( $1:e == params) then
	source $1
else
	source ${1}".params"
endif

set Subject = $patid

set SubcorticalGrayLabels="${HCPPIPEDIR_Config}/FreeSurferSubcorticalLabelTableLut.txt"

if( -e $2) then
	source $2
else
	#legacy support
	set LowResMesh = $2
	set ConcTrailerToSurfaceProject = $3
	set NonLinear = $4
	set DebugFile = surface_projection_pipeline.log
endif

#set the non linear alignment flag to 0 if it doesn't exist
if(! $?NonLinear) set NonLinear = 0
if(! $?IncludeSubCortical) set IncludeSubCortical = 0
if(! $?ConcTrailerToSurfaceProject) then
	if( -e ${StudyFolder}/Functional/Volume/${patid}_rsfMRI_uout_resid_bpss.nii.gz) then
		set fcFileName = ${Subject}"_rsfMRI_uout_resid_bpss"
	else if( -e ${StudyFolder}/Functional/Volume/${Subject}_rsfMRI_uout_resid_bpss.nii.gz) then
		set fcFileName = ${Subject}"_rsfMRI_uout_resid_bpss"
	else
		decho "Unable to find volume rsfMRI timeseries in ${StudyFolder}/Functional/Volume" $log
		exit 1
	endif
else
	set fcFileName = ${Subject}"_"$ConcTrailerToSurfaceProject:r
endif

if(! $?FinalResolution) then
	set FinalResolution = 3
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

decho "Using "$fcFileName" as BOLD to be projected." $DebugFile

if($NonLinear) then
	set NonLinAtlasTransform = ${StudyFolder}/Anatomical/Volume/T1/${patid}"_warpfield_111.nii.gz"
	set NonLinInverseAtlasTransform = ${StudyFolder}/Anatomical/Volume/T1/${patid}"_invwarpfield_111.nii.gz"
else
	set NonLinAtlasTransform = "zero"
	set NonLinInverseAtlasTransform = "zero"
endif

#set UseCurrentSurfs = 1
if(! $?UseCurrentSurfs) then
	set UseCurrentSurfs = 0
endif

if(! $?UseFLIRT) then
	set UseFLIRT = 0
endif

if($UseFLIRT) then
	set MPR_in = "T1"
else
	set MPR_in = "T1"
endif
set AtlasTransform="zero"
set InverseAtlasTransform="zero"

set AtlasName = $target:t
set scrdir = $ScratchFolder/${Subject}

#default to 6mm smoothing - this effectively disables smoothing as it will be done
#by the user at their discression
set Sigma=`echo "0.000000000000000001 / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
set smoothing = 0

#clean out the current Surface folder if we aren't reusing the surfaces
if(! $UseCurrentSurfs) then
	rm -rf $StudyFolder/$AtlasSpaceFolder/*
endif

#switch to the proper freesurfer orig space to atlas space t4
if($?day1_patid) then
	set t4="${day1_path}/Masks/FreesurferMasks/${Subject}_orig_to_${Subject}_T1.mat"
else
	set t4="${cwd}/Masks/FreesurferMasks/${Subject}_orig_to_${Subject}_T1.mat"
endif

if(! -e $t4) then
	decho "Could not find $t4. Unable to transform surfaces from freesurfer space to atlas space." $DebugFile
	exit 1
endif

set T1_target = ${StudyFolder}/Anatomical/Volume/T1/${Subject}_T1.nii.gz
if(! -e $T1_target && -e ${StudyFolder}/Anatomical/Volume/T1/${Subject}_T1.nii) then
	set T1_target = ${StudyFolder}/Anatomical/Volume/T1/${Subject}_T1.nii
endif

set orig_target = ${StudyFolder}/Masks/FreesurferMasks/${Subject}_orig.nii
if(! -e $orig_target) then
	decho "Cannot find $orig_target" $DebugFile
endif
	
set FinalfMRIResolution = $FinalResolution
set ResultsFolder="$StudyFolder"/$AtlasSpaceFolder/HCP_Results/
set DownSampleFolder=${StudyFolder}/${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k
set ROIFolder="ROIs"

set FreeSurferFolder="$cwd/Freesurfer"
set FreeSurferInput="${Subject}_${MPR_in}"
set AtlasSpaceT1wImage="${Subject}_${MPR_in}"
set AtlasSpaceT2wImage="${Subject}_${MPR_in}"
set T1wRestoreImage="${Subject}_${MPR_in}"
set T2wRestoreImage="${Subject}_${MPR_in}"
set OrginalT1wImage="${Subject}_${MPR_in}"
set OrginalT2wImage="${Subject}_${MPR_in}"

if(! -e ${T1wFolder}/${T1wRestoreImage}.nii.gz && -e ${T1wFolder}/${T1wRestoreImage}.nii) then
	pushd ${T1wFolder}
	gzip ${T1wRestoreImage}.nii
	popd
endif

## Surface fMRI Processing
if(! $?FCdir) then
	set FCdir = ${StudyFolder}/Functional/Volume/
else
	set FCdir = ${StudyFolder}/${FCdir}/
endif

set NameOffMRI = ${FCdir}/$fcFileName

#For Freesurfer6 compatibility
if(! -e ${SUBJECTS_DIR}/label/lh.BA.annot && -e ${SUBJECTS_DIR}/label/lh.BA_exvivo.annot) then
	pushd ${SUBJECTS_DIR}/label
		cp -s lh.BA_exvivo.annot lh.BA.annot
	popd
else if(! -e ${SUBJECTS_DIR}/label/lh.BA.annot) then
	echo "Freesurfer 5.3 or higher did not create the lh.BA.annot files. Please rerun freesurfer and generate it."
	exit 1
endif

if(! -e ${SUBJECTS_DIR}/label/rh.BA.annot && -e ${SUBJECTS_DIR}/label/rh.BA_exvivo.annot) then
	pushd ${SUBJECTS_DIR}/label
		cp -s rh.BA_exvivo.annot rh.BA.annot
	popd
else if(! -e ${SUBJECTS_DIR}/label/rh.BA.annot) then
	echo "Freesurfer 5.3 or higher did not create the rh.BA.annot files. Please rerun freesurfer and generate it."
	exit 1
endif

mkdir -p "$ResultsFolder"/RibbonVolumeToSurfaceMapping
if ( $status ) exit 1

set NativeFolder_Redirect = $StudyFolder/"$AtlasSpaceFolder"/${AtlasName}_${HighResMesh}k
mkdir -p $NativeFolder_Redirect
if ( $status ) exit 1

pushd ${StudyFolder}/${AtlasSpaceFolder}

	rm -rf xfms
	mkdir xfms
	$FSLBIN/fslmaths ${StudyFolder}/$T1wFolder/${Subject}_${MPR_in}.nii.gz -sub ${StudyFolder}/$T1wFolder/${Subject}_${MPR_in}.nii.gz zero.nii.gz
	if ( $status ) exit $status

	$FSLBIN/fslmerge -t zero_.nii.gz zero.nii.gz zero.nii.gz zero.nii.gz
	if ( $status ) exit $status

	mv -f zero_.nii.gz ${StudyFolder}/${AtlasSpaceFolder}/xfms/zero.nii.gz
	if ( $status ) exit $status

	rm -rf ${scrdir}/${fcFileName}*

	decho $StudyFolder $DebugFile
	decho $Subject $DebugFile

	if(! -e ${Subject}_${MPR_in}.nii.gz) then
		ln -s ${StudyFolder}/$T1wFolder/${Subject}_${MPR_in}.nii.gz ${Subject}_${MPR_in}.nii.gz
		if($status) exit 1
	endif

	#Create and register surfaces unless the user wants to use what
	#has already been created
	if(! $UseCurrentSurfs) then
		# Run FreeSurfer2CaretConvertAndRegisterNonlinear
		echo  $HCPPIPEDIR_PostFS"/FreeSurfer2CaretConvertAndRegisterNonlinear_v3.sh "$StudyFolder" "$Subject" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$FreeSurferFolder" "$FreeSurferInput" "$T1wRestoreImage" "$T2wRestoreImage" "$SurfaceAtlasDIR" "$HighResMesh" "$LowResMesh" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$AtlasSpaceT2wImage" "$T1wImageBrainMask" "$FreeSurferLabels" "$GrayordinatesSpaceDIR" "$GrayordinatesResolution" "$SubcorticalGrayLabels

		#$HCPPIPEDIR_PostFS/FreeSurfer2CaretConvertAndRegisterNonlinear_v2.sh $StudyFolder $Subject $T1wFolder $AtlasSpaceFolder $NativeFolder $FreeSurferFolder $FreeSurferInput $T1wRestoreImage $T2wRestoreImage $SurfaceAtlasDIR $HighResMesh $LowResMesh $AtlasTransform $InverseAtlasTransform $AtlasSpaceT1wImage $AtlasSpaceT2wImage $T1wImageBrainMask $FreeSurferLabels $GrayordinatesSpaceDIR $GrayordinatesResolution $SubcorticalGrayLabels >! ${StudyFolder}/Logs/${Subject}_FreeSurfer2CaretConvertAndRegisterNonlinear_v2_out.log
		$HCPPIPEDIR_PostFS/FreeSurfer2CaretConvertAndRegisterNonlinear_v3.sh $StudyFolder $Subject $T1wFolder $AtlasSpaceFolder $NativeFolder $FreeSurferFolder $FreeSurferInput $T1wRestoreImage $T2wRestoreImage $SurfaceAtlasDIR $HighResMesh $LowResMesh $AtlasTransform $InverseAtlasTransform $AtlasSpaceT1wImage $AtlasSpaceT2wImage $T1wImageBrainMask $FreeSurferLabels $GrayordinatesSpaceDIR $GrayordinatesResolution $SubcorticalGrayLabels >! ${StudyFolder}/Logs/${Subject}_FreeSurfer2CaretConvertAndRegisterNonlinear_v3_out.log
		if ( $status ) then
			echo status $status
			decho "$Subject failed PostFS" $DebugFile
			exit 1
		endif

		# Transform gifti surfaces (t4_gifti) to reflect the linear atlas space volumes. The HCP combines the linear and non linear transforms, but since we are
		# starting with atlas transformed volumes and not orig spaced volumes, it is more difficult. In the future it will be a single transform.
		# Files are produced during this step that help with ecog surface registration.
		mkdir ${StudyFolder}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k
		mkdir ${StudyFolder}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k
		
		mkdir ${StudyFolder}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k
		mv ${StudyFolder}/$AtlasSpaceFolder/*.${HighResMesh}k* ${StudyFolder}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k
		
		foreach surf ( midthickness pial white inflated sphere very_inflated)
			foreach si (L R )
				set gii_in=${StudyFolder}/$AtlasSpaceFolder/fsaverage_LR${LowResMesh}k/$Subject.$si.$surf.${LowResMesh}k_fs_LR.surf.gii
				set gii_out=${StudyFolder}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/$Subject.$si.$surf.${LowResMesh}k_fs_LR.surf.gii

				if(! -e $gii_in) then
					echo "$gii_in does not exist"
					exit 1
				endif
					
				#$PP_SCRIPTS/t4_gifti $t4 $gii_in $gii_out
				wb_command -surface-apply-affine $gii_in $t4 $gii_out".affine" -flirt $orig_target $T1_target
				if($status) exit 1
				
				if(! -e $gii_out".affine") then
					echo "could not apply affine transform to $gii_in!"
					exit 1
				endif
				
				
				#apply the non linear alignment
				#but not to the spheres, we just use them for resampling mesh spaces at this point
				if($NonLinear && $surf != "sphere") then
					cp $gii_out $gii_out.bak
					${CARET7DIR}/wb_command -surface-apply-warpfield $gii_out".affine" $NonLinInverseAtlasTransform $gii_out -fnirt $NonLinAtlasTransform
					if($status) exit 1
					rm $gii_out.affine
				endif

				#orig space gifti surface
				set gii_in=${StudyFolder}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.$surf.${HighResMesh}k_fs_LR.surf.gii
				set gii_out=${StudyFolder}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k/$Subject.$si.$surf.native.surf.gii

				if(! -e $gii_in) then
					echo "$gii_in does not exist"
					exit 1
				endif
				
				#$PP_SCRIPTS/t4_gifti $t4 $gii_in $gii_out
				wb_command -surface-apply-affine $gii_in $t4 $gii_out".affine" -flirt $orig_target $T1_target
				if($status) exit 1
				
				if(! -e $gii_out".affine") then
					echo "could not apply affine transform to $gii_in!"
					exit 1
				endif
				
				#apply the non linear alignment
				if($NonLinear && $surf != "sphere") then
					cp $gii_out $gii_out.bak
					wb_command -surface-apply-warpfield $gii_out".affine" $NonLinInverseAtlasTransform $gii_out -fnirt $NonLinAtlasTransform
					if($status) exit 1
					rm $gii_out.affine
				endif
			end
		end

		# Preparations for fMRI processing
		foreach si ( R L )

			${CARET7DIR}/wb_command -metric-math "thickness > 0" ${StudyFolder}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.roi.${HighResMesh}k_fs_LR.shape.gii -var thickness ${StudyFolder}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.thickness.164k_fs_LR.shape.gii
			if ( $status ) exit 1

			set srcA =  ${StudyFolder}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.roi.${HighResMesh}k_fs_LR.shape.gii
			set targA = $NativeFolder_Redirect/$Subject.$si.roi.native.shape.gii
			cp $srcA $targA
			if ( $status ) exit 1

			set srcA =  ${StudyFolder}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.sphere.${HighResMesh}k_fs_LR.surf.gii
			set targA = $NativeFolder_Redirect/$Subject.$si.sphere.reg.reg_LR.native.surf.gii
			cp $srcA $targA
			if ( $status ) exit 1
		end
	endif

	#Generate Brain Mask
# 	$RELEASE/niftigz_4dfp -4 brainmask_fs.nii.gz brainmask_fs.4dfp.img
# 	if ( $status ) exit 1
#
# 	$RELEASE/t4img_4dfp $t4 brainmask_fs.4dfp.img brainmask_fs_on_${AtlasName}_333.4dfp.img -O333 -n
# 	if ( $status ) exit 1
#
# 	$RELEASE/niftigz_4dfp -n brainmask_fs_on_${AtlasName}_333.4dfp.img brainmask_fs_on_${AtlasName}_333
# 	if ( $status ) exit 1

	#create the spec file for the atlas transformed goodies
	#Loop through left and right hemispheres
	cp ${PP_SCRIPTS}/SurfacePipeline/BLANK.spec $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec

	foreach Hemisphere(L R)
		#Set a bunch of different ways of saying left and right
		if( $Hemisphere == "L" ) then
			set hemisphere="l"
			set Structure="CORTEX_LEFT"
		else
		set hemisphere="r"
		set Structure="CORTEX_RIGHT"
		endif
		#add mpr to spec file
		${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID $StudyFolder/$AtlasSpaceFolder/${Subject}_mpr_n1_111_t88_fnirt.nii.gz

		if( $NonLinear) then
			${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID $StudyFolder/$AtlasSpaceFolder/${Subject}_mpr_n1_111_t88_fnirt.nii.gz
		endif

		#add t2w to the spec file if it exists
		if(-e $StudyFolder/$AtlasSpaceFolder/${Subject}_t2wT_t88_111.nii.gz) then
			${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID $StudyFolder/$AtlasSpaceFolder/${Subject}_t2wT_t88_111.nii.gz
			if( $NonLinear) then
				${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID $StudyFolder/$AtlasSpaceFolder/${Subject}_t2wT_t88_111_fnirt.nii.gz
			endif
		endif

		#add flair to the spec file if it exists
		if(-e $StudyFolder/$AtlasSpaceFolder/${Subject}_flair_t2w_t88_111_fnirt.nii.gz) then
			${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID $StudyFolder/$AtlasSpaceFolder/${Subject}_flair_t2w_t88_111.nii.gz
			if( $NonLinear) then
				${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID $StudyFolder/$AtlasSpaceFolder/${Subject}_flair_t2w_t88_111_fnirt.nii.gz
			endif
		endif

		if(-e ${target}.nii.gz) then
			${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${target}.nii.gz
		else
			${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${target}.nii
		endif

		foreach Surface(white midthickness pial inflated very_inflated)
			${CARET7DIR}/wb_command -add-to-spec-file $StudyFolder/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec $Structure $StudyFolder/$AtlasSpaceFolder/${AtlasName}/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
		end

	end

	#this is the end IF there is no bold
	if(! $?FCProcIndex) then
		${PP_SCRIPTS}/SurfacePipeline/HCP/PostFreeSurfer/scripts/CreateRibbon_StandAlone.sh "$cwd" $patid $AtlasSpaceFolder "${cwd}/Anatomical/Surface/T1/${patid}_T1_${FinalResTrailer}_fnirt.nii.gz"

		echo "No BOLD to project. Finished."
		exit 0
	endif


	#Reference Volume
# 	niftigz_4dfp -n ${patid}_func_vols_ave_on_${AtlasName}_333 ${scrdir}/${fcFileName}_SBRef.nii.gz
# 	if($status) exit 1

	ln -sf ${StudyFolder}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}_fnirt.nii.gz ${StudyFolder}/Functional/Volume/${fcFileName}_SBRef.nii.gz
	if ( $status ) exit 1

	set meanimg = ${StudyFolder}/Functional/Volume/$fcFileName:t"_mean"
	set stdimg = ${StudyFolder}/Functional/Volume/$fcFileName:t"_sd"
	
	fslmaths ${StudyFolder}/Functional/Volume/$fcFileName -Tmean $meanimg
	if($status) exit 1
	
	fslmaths ${StudyFolder}/Functional/Volume/$fcFileName -Tstd $stdimg
	if($status) exit 1


# 	if (! -e $stdimg.4dfp.img ) then
# 		pushd $FCdir
# 		niftigz_4dfp -4 ${fcFileName} ${fcFileName}
# 		if($status) exit 1
# 
# 		if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
# 			set Format = ${StudyFolder}/Functional/TemporalMask/${patid}_rsfMRI_resid_bpss_dvar.format
# 		else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
# 			set Format = ${StudyFolder}/Functional/TemporalMask/${patid}_rsfMRI_fd.format
# 		else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
# 			set Format = ${StudyFolder}/Functional/TemporalMask/${patid}_rsfMRI_resid_bpss_dvar_fd.format
# 		else
# 			decho "Unknown combination of format criteria. No format able to be used" ${DebugFile}
# 			exit 1
# 		endif
# 
# 		$RELEASE/var_4dfp -s -n5 ${fcFileName} -F$Format
# 		if($status) exit 1
# 		popd
# 	endif

	#rm -f $meanimg.nii.gz
# 	rm -f $stdimg.nii.gz

# 	decho "niftigz_4dfp -n $meanimg.4dfp.img $meanimg" $DebugFile
# 	$RELEASE/niftigz_4dfp -n $meanimg mean
# 	if($status) then
# 		decho "Could not convert meanimg to niftigz" $DebugFile
# 		exit 1
# 	endif

# 	$RELEASE/niftigz_4dfp -n $stdimg.4dfp.img $stdimg
# 	if($status) then
# 		decho "Could not convert stdimg to niftigz" $DebugFile
# 		exit 1
# 	endif

	rm -f "$ResultsFolder"/RibbonVolumeToSurfaceMapping/mean.nii.gz
	rm -f "$ResultsFolder"/RibbonVolumeToSurfaceMapping/std.nii.gz

	ln -sf ${meanimg}.nii.gz "$ResultsFolder"/RibbonVolumeToSurfaceMapping/mean.nii.gz
	ln -sf $stdimg.nii.gz "$ResultsFolder"/RibbonVolumeToSurfaceMapping/std.nii.gz

	#convert BOLD to nifti
# 	$RELEASE/conc2nifti ${NameOffMRI}.conc -o${scrdir}/${fcFileName}
# 	if($status) exit 1

# 	rm -f ${scrdir}/${fcFileName}.nii.gz
# 	if($status) exit 1
#
# 	gzip -f ${scrdir}/${fcFileName}.nii
# 	if($status) exit 1

# 	cp $FCdir/${fcFileName}.nii.gz ${NameOffMRI}.nii.gz
# 	if($status) exit 1

#  	$FSLBIN/fslmaths ${meanimg}.nii.gz -mas ${StudyFolder}/Masks/FreesurferMasks/${patid}_WholeBrain_mask.nii.gz ${meanimg}.nii.gz
#  	if($status) exit 1
#  
#  	$FSLBIN/fslmaths $stdimg.nii.gz -mas ${StudyFolder}/Masks/FreesurferMasks/${patid}_WholeBrain_mask.nii.gz ${stdimg}.nii.gz
#  	if($status) exit 1
# 
#  	$FSLBIN/fslmaths $NameOffMRI.nii.gz -mas ${StudyFolder}/Masks/FreesurferMasks/${patid}_WholeBrain_mask.nii.gz ${NameOffMRI}.nii.gz
#  	if($status) exit 1

	SURF_BOLD:
	# Surface Processing
	decho "Begin surface BOLD processing" $DebugFile

	#Surface Commands
	decho "Volume to Surface" $DebugFile
	"$HCPPIPEDIR_fMRISurf"/RibbonVolumeToSurfaceMapping.sh "$ResultsFolder"/RibbonVolumeToSurfaceMapping "$FCdir/$fcFileName" "$Subject" "$DownSampleFolder" "$LowResMesh" "$NativeFolder_Redirect" "$NativeFolder_Redirect"
	if($status) exit 1

	ln -fs $FCdir/${fcFileName}.L.atlasroi.${LowResMesh}k_fs_LR.func.gii $FCdir/${fcFileName}.atlasroi.L.${LowResMesh}k_fs_LR.func.gii
	ln -fs $FCdir/${fcFileName}.R.atlasroi.${LowResMesh}k_fs_LR.func.gii $FCdir/${fcFileName}.atlasroi.R.${LowResMesh}k_fs_LR.func.gii

#
# 	cp -sf ${scrdir}/${fcFileName}*.gii $FCdir

	SUBCORT:
	if($IncludeSubCortical) then
		#do the sub cortical extraction
		decho "Creating sub-cortical volume" $DebugFile
		decho $cwd $DebugFile

		#get the subcortical regions from the mni template brain that we have aligned to

		#convert atlas wmparc to 4dfp.
		#compliment the goodvoxels mask.
		#set 0's to NaN
		pushd "$ResultsFolder"/RibbonVolumeToSurfaceMapping
			fslmaths goodvoxels -nan goodvoxels_nan
			if($status) exit 1
		popd

		${CARET7DIR}/wb_command -volume-label-import ${target}_wmparc_${FinalResTrailer}.nii.gz ${SubcorticalGrayLabels} ROIs.${FinalResolution}.nii.gz #-discard-others
		if($status) exit 1

		#extract the sub cortical voxels
		${CARET7DIR}/wb_command -volume-parcel-resampling "$NameOffMRI".nii.gz ROIs.${FinalResolution}.nii.gz ROIs.${FinalResolution}.nii.gz $Sigma ${scrdir}/"$fcFileName"_AtlasSubcortical.nii.gz -fix-zeros
		if($status) exit 1

		fslmaths ${scrdir}/"$fcFileName"_AtlasSubcortical.nii.gz -mul "$ResultsFolder"/RibbonVolumeToSurfaceMapping/goodvoxels_nan temp
		if($status) exit 1

		mv temp ${scrdir}/"$fcFileName"_AtlasSubcortical.nii.gz
		
		#link up the subcortical timeseries to the active folder
		cp -sf ${scrdir}/"$fcFileName"_AtlasSubcortical.nii.gz $FCdir

	else
		decho "skipping creation of sub-cortical volume" $DebugFile
	endif

	cp -sf $DownSampleFolder/*shape.gii $NativeFolder_Redirect	#make links to the templates
	if($status) exit 1

	decho "Creating atlas space functional surface." $DebugFile
	"$HCPPIPEDIR_fMRISurf"/CreateSurface_cii.sh "$NativeFolder_Redirect" "$Subject" "$LowResMesh" "$NameOffMRI" "$SmoothingFWHM" "$ROIFolder" "${scrdir}/$fcFileName.ctx" "$GrayordinatesResolution" ${scrdir}/"$fcFileName"_AtlasSubcortical.nii.gz $IncludeSubCortical
	if($status) exit 1

	cp -sf ${scrdir}/${fcFileName}.ctx.dtseries.nii ${FCdir}

	#at this point, we are in dire need of some cleanup.
	rm ${StudyFolder}/Functional/Volume/*.gii
	mv ${StudyFolder}/Functional/Volume/$fcFileName".ctx.dtseries.nii" ${StudyFolder}/Functional/Surface/$fcFileName".ctx.dtseries.nii"

	SURF_REG:
	#dosurface regression based on the volume regressors
# 	if($DoSurfaceRegression) then
# 		cd $FCdir
# 			if(! -e ${StudyFolder}/Functional/TemporalMask/rsfMRI_tmask.txt) then
# 				decho "Unable to find tmask.txt. Cannot perform nuissance regression on the surface." $DebugFile
# 				exit 1
# 			endif
# 
# 			echo "matlab -nodesktop -nosplash -r addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));fs_surfproc_v3('${fcFileName}.conc','tmask.txt',${BOLD_TR},${LowFrequency},${HighFrequency},[],'${Subject}_nuisance_regressors.dat');exit" >> $DebugFile
# 			matlab -nodesktop -nosplash -r "addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));fs_surfproc_v3('${StudyFolder}/Functional/Surface/${fcFileName}.ctx.dtseries.nii','${StudyFolder}/Functional/TemporalMask/rsfMRI_tmask.txt',${BOLD_TR},${LowFrequency},${HighFrequency},[],'${StudyFolder}/Functional/Regressors/${Subject}_all_regressors.dat');exit"
# 		cd ..
# 	endif

	#smooth the surface and subcortical areas after everything is done
	if($SmoothingFWHM != 0) then
		cd $FCdir
			echo "Smoothing dtseries using $SmoothingFWHM mm gaussian kernel"

			set Sigma=`echo "$SmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
			set smoothing = $SmoothingFWHM

			wb_command -cifti-smoothing ${StudyFolder}/Functional/Surface/${fcFileName}_sr_bpss.ctx.dtseries.nii $Sigma $Sigma COLUMN ${StudyFolder}/Functional/Surface/${fcFileName}_sr_bpss_s${smoothing}.ctx.dtseries.nii -left-surface $StudyFolder/$AtlasSpaceFolder/${AtlasName}/$Subject.L.midthickness.${LowResMesh}k_fs_LR.surf.gii -right-surface $StudyFolder/$AtlasSpaceFolder/${AtlasName}/$Subject.R.midthickness.${LowResMesh}k_fs_LR.surf.gii
			if($status) then
				decho "Failed to smooth ${StudyFolder}/Functional/Surface/${fcFileName}.ctx.dtseries.nii" $DebugFile
				exit 1
			endif
		cd ..
	endif

popd

#project the mask in the masks folder

pushd ${StudyFolder}/Masks
	if($NonLinear && -e ${Subject}_${MaskTrailer}_fnirt.nii.gz) then
		$PP_SCRIPTS/SurfacePipeline/volume_to_surface.csh ${Subject}_${MaskTrailer}_fnirt.nii.gz ${StudyFolder}/Anatomical/Surface/${AtlasName} ${Subject}_${MaskTrailer}_fnirt ${LowResMesh}
	else if( -e ${Subject}_${MaskTrailer}.nii.gz) then
		$PP_SCRIPTS/SurfacePipeline/volume_to_surface.csh ${Subject}_${MaskTrailer}.nii.gz ${StudyFolder}/Anatomical/Surface/${AtlasName} ${Subject}_${MaskTrailer} ${LowResMesh}
	endif
popd

#project the SD image to surface
pushd ${StudyFolder}/Anatomical/Surface
	$PP_SCRIPTS/SurfacePipeline/volume_to_surface.csh ${StudyFolder}/Anatomical/Surface/HCP_Results/RibbonVolumeToSurfaceMapping/std.nii.gz ${StudyFolder}/Anatomical/Surface/${AtlasName}_${LowResMesh}k ${patid}_SD ${LowResMesh}
popd

#compute and project Myelin

#$PP_SCRIPTS/SurfacePipeline/HCP/PostFreeSurfer/scripts/CreateMyelinMaps_v3.csh $1 $2

exit 0
