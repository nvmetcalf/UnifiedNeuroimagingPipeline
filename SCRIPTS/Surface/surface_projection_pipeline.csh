#!/bin/csh

if($#argv < 2) then
	echo "surface_projection_pipeline <Subject.params> <ProcessingParemeters.params>"
	exit 1
endif

setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

set SubjectHome = $cwd #Path to patients folder

set ReferenceMyelinMaps="${HCPPIPEDIR_Templates}/standard_mesh_atlases/Conte69.MyelinMap_BC.164k_fs_LR.dscalar.nii"

setenv FSOUT ""

set AtlasSpaceFolder="Anatomical/Surface"
set NativeFolder="Native"
set HighResMesh="164" #Usually 164k vertices
set LowResMesh="32" #Usually 32k vertices
set SmoothingFWHM=0
set DoSurfaceRegression = 1

#nick - overrides previously defined variables
if( $1:e == params) then
	source $1
else
	source ${1}".params"
endif

set Subject = $patid

set T1wFolder="Anatomical/Volume/T1" #Location of T1w images

set SurfaceAtlasDIR="${HCPPIPEDIR_Templates}/standard_mesh_atlases" #(Need to rename make surf.gii and add 32k)
set FreeSurferLabels="${HCPPIPEDIR_Config}/FreeSurferAllLut.txt"
set GrayordinatesSpaceDIR="${HCPPIPEDIR_Templates}/91282_Greyordinates" #(Need to copy these in)
set GrayordinatesResolution="2" #Usually 2mm

set SubcorticalGrayLabels="${HCPPIPEDIR_Config}/FreeSurferSubcorticalLabelTableLut.txt"

if( -e $2) then
	source $2
else
	#legacy support
	set LowResMesh = $2
	set NiftiToSurfaceProject = $3
	set NonLinear = $4
	set DebugFile = surface_projection_pipeline.log
endif

#set the non linear alignment flag to 0 if it doesn't exist
if(! $?NonLinear) set NonLinear = 0
if(! $?IncludeSubCortical) set IncludeSubCortical = 0
if(! $?NiftiToSurfaceProject) then
	set fcFileName = ${SubjectHome}/Functional/Volume/${Subject}"_rsfMRI"
else
	set fcFileName = $NiftiToSurfaceProject:r:r
endif

if($NonLinear) then
	set T1wImageBrainMask="${SubjectHome}/Masks/${Subject}_used_voxels_fnirt"
else
	set T1wImageBrainMask="${SubjectHome}/Masks/${Subject}_used_voxels"
endif

decho "Using "$fcFileName" as BOLD to be projected." $DebugFile

if($NonLinear) then
	set NonLinAtlasTransform = ${SubjectHome}/Anatomical/Volume/T1/${patid}"_warpfield_111.nii.gz"
	set NonLinInverseAtlasTransform =  ${SubjectHome}/Anatomical/Volume/T1/${patid}"_invwarpfield_111.nii.gz"
else
	set NonLinAtlasTransform = "zero"
	set NonLinInverseAtlasTransform = "zero"
endif

if(! $?UseCurrentSurfs) then
	set UseCurrentSurfs = 0
endif

if(! $?UseFLIRT) then
	set UseFLIRT = 0
endif

set AtlasTransform="zero"
set InverseAtlasTransform="zero"

#default to 6mm smoothing - this effectively disables smoothing as it will be done
#by the user at their discression
set Sigma=`echo "0.000000000000000001 / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
set smoothing = 0

set AtlasName = `basename $target`

pushd $AtlasSpaceFolder

	#switch to the proper freesurfer orig space to atlas space t4 and surfaces
	if($?day1_patid) then
		if($IncludeSubCortical) then
			#copy over the 1st sessions surfaces and name them afte the current session as they are the same person
			cp -f ${day1_path}/Anatomical/Surface/ROIs.3.nii.gz ${SubjectHome}/Anatomical/Surface/ROIs.3.nii.gz
		endif
		foreach Folder(${day1_path}/Anatomical/Surface/*k)
			pushd $Folder
				set FolderName = `basename $Folder`
				mkdir ${SubjectHome}/Anatomical/Surface/${FolderName}
				foreach File(*)
					set NewFilename = ${Subject}.`echo $File | cut -d. -f2,3,4,5,6,7,8,9,10`
					cp $File ${SubjectHome}/Anatomical/Surface/${FolderName}/${NewFilename}
				end
			popd
		end

		goto RIBBON_MAPPING
	else
		set t4="${SubjectHome}/Masks/FreesurferMasks/${Subject}_orig_to_${AtlasName}_t4"
		set FreeSurferFolder="${SUBJECTS_DIR}"
	endif

	if( ! -e $t4) then
		echo "Could not to find orig to t1 transform. Unable to continue."
		exit 1
	endif

	set FinalfMRIResolution = 3
	set DownSampleFolder=$AtlasSpaceFolder/fsaverage_LR${LowResMesh}k
	set ROIFolder="ROIs"

	set FreeSurferInput="${Subject}_T1T"
	set AtlasSpaceT1wImage="${Subject}_T1T"
	set AtlasSpaceT2wImage="${Subject}_T1T"
	set T1wRestoreImage="${Subject}_T1T"
	set T2wRestoreImage="${Subject}_T1T"
	set OrginalT1wImage="${Subject}_T1T"
	set OrginalT2wImage="${Subject}_T1T"

	#For Freesurfer6 compatibility
	if(! -e ${FreeSurferFolder}/label/lh.BA.annot && -e ${FreeSurferFolder}/label/lh.BA_exvivo.annot) then
		pushd ${FreeSurferFolder}/label
			cp -s lh.BA_exvivo.annot lh.BA.annot
		popd
	else if(! -e ${FreeSurferFolder}/label/lh.BA.annot) then
		echo "Freesurfer 5.3 or higher did not create the lh.BA.annot files. Please rerun freesurfer and generate it."
		exit 1
	endif

	if(! -e ${FreeSurferFolder}/label/rh.BA.annot && -e ${FreeSurferFolder}/label/rh.BA_exvivo.annot) then
		pushd ${FreeSurferFolder}/label
			cp -s rh.BA_exvivo.annot rh.BA.annot
		popd
	else if(! -e ${FreeSurferFolder}/label/rh.BA.annot) then
		echo "Freesurfer 5.3 or higher did not create the rh.BA.annot files. Please rerun freesurfer and generate it."
		exit 1
	endif

#goto SUBCORT
	decho $SubjectHome $DebugFile
	decho $Subject $DebugFile

	
	#Create and register surfaces unless the user wants to use what
	#has already been created
	if(! $UseCurrentSurfs) then
		rm -rf *	#clean out previous surfaces

		if(! -e $SubjectHome/$T1wFolder/$T1wRestoreImage".nii.gz") then
			pushd $T1wFolder
				gzip $T1wRestoreImage".nii"
			popd
		endif
		
		if (! -e  xfms/zero.nii.gz ) then
			mkdir xfms
			pushd xfms
				$FSLBIN/fslmaths ${SubjectHome}/Anatomical/Volume/T1/${Subject}_T1T.nii.gz -sub ${SubjectHome}/Anatomical/Volume/T1/${Subject}_T1T.nii.gz zero.nii.gz
				if ( $status ) exit $status

				$FSLBIN/fslmerge -t zero_.nii.gz zero.nii.gz zero.nii.gz zero.nii.gz
				if ( $status ) exit $status

				mv -f zero_.nii.gz zero.nii.gz
				if ( $status ) exit $status
			popd
		endif

		# Run FreeSurfer2CaretConvertAndRegisterNonlinear
		echo  $HCPPIPEDIR_PostFS"/FreeSurfer2CaretConvertAndRegisterNonlinear_v3.sh "$SubjectHome" "$Subject" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$FreeSurferFolder" "$FreeSurferInput" "$T1wRestoreImage" "$T2wRestoreImage" "$SurfaceAtlasDIR" "$HighResMesh" "$LowResMesh" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$AtlasSpaceT2wImage" "${SubjectHome}/Anatomical/Surface/native_mask" "$FreeSurferLabels" "$GrayordinatesSpaceDIR" "$GrayordinatesResolution" "$SubcorticalGrayLabels

# 		echo SubjectHome = $SubjectHome
# 		echo Subject = "$Subject"
# 		echo T1wFolder = "$T1wFolder"
# 		echo AtlasSpaceFolder = "$AtlasSpaceFolder"
# 		echo NativeFolder = "$NativeFolder"
# 		echo FreesurferFolder = "$FreeSurferFolder"
# 		echo FreesurferInput "$FreeSurferInput"
# 		"$T1wRestoreImage" "$T2wRestoreImage" "$SurfaceAtlasDIR" "$HighResMesh" "$LowResMesh" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$AtlasSpaceT2wImage" "${SubjectHome}/Anatomical/Surface/native_mask" "$FreeSurferLabels" "$GrayordinatesSpaceDIR" "$GrayordinatesResolution" "$SubcorticalGrayLabels
# 		
		ln -s $SubjectHome/$T1wFolder/$T1wRestoreImage".nii.gz" $SubjectHome/$AtlasSpaceFolder/$AtlasSpaceT1wImage".nii.gz"
		if($status) exit 1
		
		#binarize the freesurfer mask
		fslmaths $FreeSurferFolder/mri/brainmask.nii.gz -bin ${SubjectHome}/Anatomical/Surface/native_mask.nii.gz
		if($status) exit 1
		
		$HCPPIPEDIR_PostFS/FreeSurfer2CaretConvertAndRegisterNonlinear_v3.sh $SubjectHome $Subject $T1wFolder $AtlasSpaceFolder $NativeFolder $FreeSurferFolder $FreeSurferInput $T1wRestoreImage $T2wRestoreImage $SurfaceAtlasDIR $HighResMesh $LowResMesh $AtlasTransform $InverseAtlasTransform $AtlasSpaceT1wImage $AtlasSpaceT2wImage ${SubjectHome}/Anatomical/Surface/native_mask $FreeSurferLabels $GrayordinatesSpaceDIR $GrayordinatesResolution $SubcorticalGrayLabels >! ${SubjectHome}/Logs/${Subject}_FreeSurfer2CaretConvertAndRegisterNonlinear_v3_out.log

		if ( $status ) then
			echo status $status
			decho "$Subject failed initial gifti surface creation" $DebugFile
			exit 1
		endif

		mkdir fsaverage_LR${HighResMesh}k
		mv *.${HighResMesh}k* fsaverage_LR${HighResMesh}k/

		# Transform gifti surfaces (t4_gifti) to reflect the linear atlas space 
		# volumes. The HCP combines the linear and non linear transforms, but since we are
		# starting with atlas transformed volumes and not orig spaced volumes, it is 
		# more difficult. In the future it will be a single transform.
		# Files are produced during this step that help with ecog surface registration.
		mkdir ${AtlasName}_${LowResMesh}k
		mkdir ${AtlasName}_${HighResMesh}k	#storing the 164k atlas transformed meshes

		foreach surf ( midthickness pial white inflated sphere very_inflated)
			foreach si (L R )
				set gii_in=${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${LowResMesh}k/$Subject.$si.$surf.${LowResMesh}k_fs_LR.surf.gii
				set gii_out=${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/$Subject.$si.$surf.${LowResMesh}k_fs_LR.surf.gii

				if(! -e $gii_in) then
					echo "$gii_in does not exist"
					exit 1
				endif
					
				$PP_SCRIPTS/t4_gifti $t4 $gii_in $gii_out
				
				
				if(! -e $gii_out) then
					echo "t4_gifti failed! $gii_out does not exist"
					exit 1
				endif
				
				
				#apply the non linear alignment
				#but not to the spheres, we just use them for resampling mesh spaces at this point
				if($NonLinear && $surf != "sphere") then
					cp $gii_out $gii_out.bak
					${CARET7DIR}/wb_command -surface-apply-warpfield $gii_out".bak" $NonLinInverseAtlasTransform $gii_out -fnirt $NonLinAtlasTransform
					rm $gii_out.bak
				endif

				#orig space gifti surface
				set gii_in=${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.$surf.${HighResMesh}k_fs_LR.surf.gii
				set gii_out=${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k/$Subject.$si.$surf.native.surf.gii

				if(! -e $gii_in) then
					echo "$gii_in does not exist"
					exit 1
				endif
				
				$PP_SCRIPTS/t4_gifti $t4 $gii_in $gii_out
				
				if(! -e $gii_out) then
					echo "t4_gifti failed! $gii_out does not exist"
					exit 1
				endif
				
				#apply the non linear alignment
				if($NonLinear && $surf != "sphere") then
					cp $gii_out $gii_out.bak
					wb_command -surface-apply-warpfield $gii_out".bak" $NonLinInverseAtlasTransform $gii_out -fnirt $NonLinAtlasTransform
					rm $gii_out.bak
				endif
			end
		end

		# Preparations for fMRI processing
		foreach si ( R L )

			${CARET7DIR}/wb_command -metric-math "thickness > 0" ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.roi.${HighResMesh}k_fs_LR.shape.gii -var thickness ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.thickness.${HighResMesh}k_fs_LR.shape.gii
			if ( $status ) exit 1

			set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.roi.${HighResMesh}k_fs_LR.shape.gii
			set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k/$Subject.$si.roi.native.shape.gii
			cp $srcA $targA
			if ( $status ) exit 1

			#copy over the resampling spheres, not registration sphere, for each mesh
			set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.sphere.${HighResMesh}k_fs_LR.surf.gii
			set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k/$Subject.$si.sphere.reg.reg_LR.native.surf.gii
			cp $srcA $targA
			if ( $status ) exit 1
			
			set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/$Subject.$si.sphere.${HighResMesh}k_fs_LR.surf.gii
			set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k/$Subject.$si.sphere.${HighResMesh}k_LR.native.surf.gii
			cp $srcA $targA
			if ( $status ) exit 1

			set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${LowResMesh}k/$Subject.$si.sphere.${LowResMesh}k_fs_LR.surf.gii
			set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/$Subject.$si.sphere.reg.reg_LR.native.surf.gii
			cp $srcA $targA
			if ( $status ) exit 1
			
			set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${LowResMesh}k/$Subject.$si.sphere.${LowResMesh}k_fs_LR.surf.gii
			set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/$Subject.$si.sphere.${LowResMesh}k_fs_LR.surf.gii
			cp $srcA $targA
			if ( $status ) exit 1

			set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${LowResMesh}k/$Subject.$si.atlasroi.${LowResMesh}k_fs_LR.shape.gii
			set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/$Subject.$si.atlasroi.${LowResMesh}k_fs_LR.shape.gii
			cp $srcA $targA
			if ( $status ) exit 1
		end
	

		#create the spec file for the atlas transformed goodies
		#Loop through left and right hemispheres
		cp ${PP_SCRIPTS}/SurfacePipeline/BLANK.spec ${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec

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
			${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/T1/${Subject}_T1T_111.nii.gz

			if( $NonLinear) then
				${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/T1/${Subject}_T1T_111_fnirt.nii.gz
			endif

			#add t2w to the spec file if it exists
			if(-e ${SubjectHome}/Anatomical/Volume/T2/${Subject}_T2T_111.nii.gz) then
				${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID $SubjectHome/Anatomical/Volume/T2/${Subject}_T2T_111.nii.gz
				if( -e ${SubjectHome}/Anatomical/Volume/T2/${Subject}_T2T_111_fnirt.nii.gz) then
					${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/T2/${Subject}_T2T_111_fnirt.nii.gz
				endif
			endif

			#add flair to the spec file if it exists
			if(-e ${SubjectHome}/Anatomical/Volume/FLAIR/${Subject}_FLAIRT_111.nii.gz) then
				${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/FLAIR/${Subject}_FLAIRT_111.nii.gz
				if( -e ${SubjectHome}/Anatomical/Volume/FLAIR/${Subject}_FLAIRT_111_fnirt.nii.gz) then
					${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/FLAIR/${Subject}_FLAIRT_111_fnirt.nii.gz
				endif
			endif

			#add BOLD_ref to the spec file if it exists
			if(-e ${SubjectHome}/Anatomical/Volume/BOLD_ref/${Subject}_BOLD_ref_333_fnirt.nii.gz) then
				${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/BOLD_ref/${Subject}_BOLD_ref_333_fnirt.nii.gz
			endif

			if(-e ${target}.nii.gz) then
				${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${target}.nii.gz
			else
				${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${target}.nii
			endif

			foreach Surface(white midthickness pial inflated very_inflated)
				${CARET7DIR}/wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$LowResMesh"k.${AtlasName}.LR.wb.spec $Structure ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
			end

		end

	endif
	
	RIBBON_MAPPING:
	#this is the end IF there is no bold
	if(! $?RunIndex) then
		if(! $?day1_path && ! $?day1_patid) then
			${PP_SCRIPTS}/SurfacePipeline/HCP/PostFreeSurfer/scripts/CreateRibbon_StandAlone.sh ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k $patid "$T1wFolder/${patid}_T1T_333_fnirt.nii.gz"
		else
			rm $AtlasSpaceFolder/RibbonVolumeToSurfaceMapping
			ln -s ${day1_path}/Anatomical/Surface/RibbonVolumeToSurfaceMapping RibbonVolumeToSurfaceMapping
			if($status) exit 1
		endif
		echo "No BOLD to project. Finished."
		exit 0
	endif

	if(-e "$cwd"/RibbonVolumeToSurfaceMapping) rm -fr "$cwd"/RibbonVolumeToSurfaceMapping

	mkdir "$cwd"/RibbonVolumeToSurfaceMapping

	set stdimg = "$cwd"/RibbonVolumeToSurfaceMapping/std

	#need to compute mean and SD without figuring in the frames that we will ignore in the future
	niftigz_4dfp -4 ${fcFileName} $ScratchFolder/${Subject}/BOLD_ts_temp
	if($status) then
		decho "	ERROR: atlas aligned bold does not exist at ${fcFileName}.nii.gz. Rerun -fs_f" $DebugFile
		exit 1
	endif
	
	if($FD_Threshold != 0 && $DVAR_Threshold != 0) then
		set TemporalMask = "${SubjectHome}/Functional/TemporalMask/${Subject}_rsfMRI_resid_bpss_dvar_fd.format"
	else if($?FD_Threshold == 0 && $DVAR_Threshold != 0) then
		set TemporalMask = "${SubjectHome}/Functional/TemporalMask/${Subject}_rsfMRI_dvar.format"
	else if($FD_Threshold != 0 && $DVAR_Threshold == 0) then
		set TemporalMask = "${SubjectHome}/Functional/TemporalMask/${Subject}_rsfMRI_fd.format"
	else
		set TemporalMask = "${SubjectHome}/Functional/TemporalMask/${Subject}_AllVolumes_rsfMRI_preproc.format"
	endif

	if(! -e $TemporalMask) then
		decho "Could not find a Temporal Mask."
		 exit 1
	endif

	var_4dfp -s -N -F${TemporalMask} $ScratchFolder/${Subject}/BOLD_ts_temp
	#fslmaths ${fcFileName} -Tstd $stdimg
	if($status) then
		decho "Could not compute standard deviation of ${SubjectHome}/Functional/Volume/${fcFileName}" $DebugFile
		exit 1
	endif
	
	niftigz_4dfp -n $ScratchFolder/${Subject}/BOLD_ts_temp_sd1 $stdimg
	if($status) exit 1

	rm -f $ScratchFolder/${Subject}/BOLD_ts_temp*

	set meanimg = ${SubjectHome}/"$AtlasSpaceFolder"/RibbonVolumeToSurfaceMapping/mean
	
	fslmaths ${fcFileName} -Tmean $meanimg
	if($status) exit 1
	
	if($NonLinear) then
		set UsedVoxelsMask = ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_333
	else
		set UsedVoxelsMask = ${SubjectHome}/Masks/${patid}_used_voxels_333
	endif

	$FSLBIN/fslmaths $meanimg -mas ${UsedVoxelsMask} ${meanimg}.nii.gz
	if($status) exit 1

	$FSLBIN/fslmaths $stdimg.nii.gz -mas ${UsedVoxelsMask} ${stdimg}.nii.gz
	if($status) exit 1

	$FSLBIN/fslmaths $fcFileName.nii.gz -mas ${UsedVoxelsMask} ${fcFileName}.nii.gz
	if($status) exit 1

	if($NonLinear) then
		ln -sf ${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_333_fnirt.nii.gz ${SubjectHome}/"$AtlasSpaceFolder"/RibbonVolumeToSurfaceMapping/BOLD_ref_333.nii.gz
	else
		ln -sf ${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_333.nii.gz ${SubjectHome}/"$AtlasSpaceFolder"/RibbonVolumeToSurfaceMapping/BOLD_ref_333.nii.gz
	endif

	SURF_BOLD:	
	# Surface Processing
	decho "Begin surface BOLD processing" $DebugFile

	rm ${SubjectHome}/Functional/Volume/$fcFileName:t"_SBRef.nii.gz"
	ln -s ${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_333_fnirt.nii.gz ${SubjectHome}/Functional/Volume/$fcFileName:t"_SBRef.nii.gz"
	
	if($status) exit 1
	
	#Surface Commands
	decho "Volume to Surface" $DebugFile
	"$HCPPIPEDIR_fMRISurf"/RibbonVolumeToSurfaceMapping.sh ${SubjectHome}/"$AtlasSpaceFolder"/RibbonVolumeToSurfaceMapping "$fcFileName" "$Subject" ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k "$LowResMesh" ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${HighResMesh}k
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
		${CARET7DIR}/wb_command -volume-label-import ${target}_wmparc_333.nii.gz ${SubcorticalGrayLabels} ROIs.3.nii.gz
		if($status) exit 1

		#extract the sub cortical voxels
		${CARET7DIR}/wb_command -volume-parcel-resampling "$fcFileName".nii.gz ROIs.3.nii.gz ROIs.3.nii.gz $Sigma ${ScratchFolder}/${patid}/AtlasSubcortical.nii.gz -fix-zeros
		if($status) exit 1
	else
		decho "skipping creation of sub-cortical volume" $DebugFile
	endif

	decho "Creating atlas space functional surface." $DebugFile
	"$HCPPIPEDIR_fMRISurf"/CreateSurface_cii.sh "$AtlasSpaceFolder"/"$AtlasName" "$Subject" "$LowResMesh" ${SubjectHome}/Functional/Surface/`basename ${fcFileName}` "$SmoothingFWHM" "$AtlasSpaceFolder" "${SubjectHome}/Functional/Surface/`basename ${fcFileName}`.ctx" "$GrayordinatesResolution" $ScratchFolder/${patid}/AtlasSubcortical.nii.gz $IncludeSubCortical $BOLD_TR
	if($status) then
		decho "Failed to create functional surfaces."	
		exit 1
	endif

	if( -e $ScratchFolder/${patid}/AtlasSubcortical.nii.gz) rm -f $ScratchFolder/${patid}/AtlasSubcortical.nii.gz
	rm -f ${SubjectHome}/Functional/Surface/${fcFileName}*.gii

	SURF_REG:
	#dosurface regression based on the volume regressors
	if($DoSurfaceRegression) then
		pushd ${SubjectHome}/Functional/Surface
			if(! -e ${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt) then
				decho "Unable to find rsfMRI_tmask.txt. Cannot perform nuissance regression on the surface." $DebugFile
				exit 1
			endif

			#echo "matlab -nodesktop -nosplash -r try;addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));fs_surfproc_v3('${SubjectHome}/Functional/Surface/${Subject}_rsfMRI.ctx.dtseries.nii','${SubjectHome}/Functional/TemporalMask/rsFMRI_tmask.txt',${BOLD_TR},${LowFrequency},${HighFrequency},[],'${SubjectHome}/Functional/Regressors/${Subject}_all_regressors.dat');end;exit" >> $DebugFile
			matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));fs_surfproc_v3('${SubjectHome}/Functional/Surface/${Subject}_rsfMRI.ctx.dtseries.nii','${SubjectHome}/Functional/TemporalMask/rsfMRI_tmask.txt',${BOLD_TR},${LowFrequency},${HighFrequency},[],'${SubjectHome}/Functional/Regressors/${Subject}_all_regressors.dat');end;exit"

		popd
	endif

	#smooth the surface and subcortical areas after everything is done
	if($SmoothingFWHM != 0) then
		pushd ${SubjectHome}/Functional/Surface
			echo "Smoothing dtseries using $SmoothingFWHM mm gaussian kernel"

			set Sigma=`echo "$SmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
			set smoothing = $SmoothingFWHM

			wb_command -cifti-smoothing ${fcFileName}"_sr_bpss.ctx.dtseries.nii" $Sigma $Sigma COLUMN ${fcFileName}"_sr_bpss_s${smoothing}.ctx.dtseries.nii" -left-surface $AtlasSpaceFolder/${AtlasName}/$Subject.L.midthickness.${LowResMesh}k_fs_LR.surf.gii -right-surface $AtlasSpaceFolder/${AtlasName}/$Subject.R.midthickness.${LowResMesh}k_fs_LR.surf.gii
			if($status) then
				decho "Failed to smooth ${fcFileName}_sr_bpss.ctx.dtseries.nii" $DebugFile
				exit 1
			endif
		popd
	endif

popd

#project the mask in the masks folder

pushd Masks
	if($NonLinear && -e ${Subject}_${MaskTrailer}_fnirt.nii.gz) then
		$PP_SCRIPTS/SurfacePipeline/volume_to_surface.csh ${Subject}_${MaskTrailer}_fnirt.nii.gz $AtlasSpaceFolder/${AtlasName}_${LowResMesh}k ${Subject}_${MaskTrailer}_fnirt ${LowResMesh}
	else if( -e ${Subject}_${MaskTrailer}.nii.gz) then
		$PP_SCRIPTS/SurfacePipeline/volume_to_surface.csh ${Subject}_${MaskTrailer}.nii.gz $AtlasSpaceFolder/${AtlasName}_${LowResMesh}k ${Subject}_${MaskTrailer} ${LowResMesh}
	endif
popd

#compute and project Myelin
$PP_SCRIPTS/SurfacePipeline/HCP/PostFreeSurfer/scripts/CreateMyelinMaps_v3.csh $1 $2

exit 0
