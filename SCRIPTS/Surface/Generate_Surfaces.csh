#!/bin/csh

if(! -e $1) then
	echo "SCRIPT: $0 : 00001 : $1 does not exist"
	exit 1
endif

if(! -e $2) then
	echo "SCRIPT: $0 : 00002 : $2 does not exist"
	exit 1
endif

source $1
source $2

if(! $?day1_path) then
	set day1_path = ""
	set day1_patid = ""
else
	set day1_patid = $day1_path:t
endif

set SubjectHome = $cwd

if($NonLinear) then
	set NonLinAtlasTransform = ${SubjectHome}/Anatomical/Volume/T1/${patid}"_T1_warpfield_111.nii.gz"
	set NonLinInverseAtlasTransform =  ${SubjectHome}/Anatomical/Volume/T1/${patid}"_T1_invwarpfield_111.nii.gz"
else
	set NonLinAtlasTransform = "zero"
	set NonLinInverseAtlasTransform = "zero"
endif

if($target != "") then
	set AtlasName = $target:t
else
	set AtlasName = T1
endif

set AtlasSpaceFolder="Anatomical/Surface"
set NativeFolder="Native"

set DownSampleFolder=$AtlasSpaceFolder/fsaverage_LR${LowResMesh}k
set ROIFolder="ROIs"

set FreeSurferInput="${patid}_T1"
set AtlasSpaceT1wImage="${patid}_T1"
set AtlasSpaceT2wImage="${patid}_T1"
set T1wRestoreImage="${patid}_T1"
set T2wRestoreImage="${patid}_T1"
set OrginalT1wImage="${patid}_T1"
set OrginalT2wImage="${patid}_T1"

set AtlasTransform="zero"
set InverseAtlasTransform="zero"

set T1wFolder="Anatomical/Surface" #Location of T1w images

set SurfaceAtlasDIR="${HCPPIPEDIR_Templates}/standard_mesh_atlases" #(Need to rename make surf.gii and add 32k)
set FreeSurferLabels="${HCPPIPEDIR_Config}/FreeSurferAllLut.txt"
set GrayordinatesSpaceDIR="${HCPPIPEDIR_Templates}/91282_Greyordinates" #(Need to copy these in)
set GrayordinatesResolution="2" #Usually 2mm

set SubcorticalGrayLabels="${HCPPIPEDIR_Config}/FreeSurferSubcorticalLabelTableLut.txt"
set HighResMesh="164" #Usually 164k vertices

if(! $?LowResMesh) then
	set LowResMesh="32" #Usually 32k vertices
endif

if(! $?SmoothingFWHM) then
	set SmoothingFWHM=0
endif

rm -rf $AtlasSpaceFolder
mkdir -p $AtlasSpaceFolder
pushd $AtlasSpaceFolder

	rm -rf *	#clean out previous surfaces

	#switch to the proper freesurfer orig space to atlas space t4 and surfaces
	if($day1_patid != "") then
		decho "Session is multiday, no need to recreate surfaces. Linking to first day."
		if($IncludeSubCortical) then
			#copy over the 1st sessions surfaces and name them afte the current session as they are the same person
			cp -f ${day1_path}/Anatomical/Surface/ROIs.${FinalResolution}.nii.gz ${SubjectHome}/Anatomical/Surface/ROIs.${FinalResolution}.nii.gz
		endif
		foreach Folder(${day1_path}/Anatomical/Surface/*k)
			pushd $Folder
				set FolderName = `basename $Folder`
				mkdir ${SubjectHome}/Anatomical/Surface/${FolderName}
				foreach File(*)
					set NewFilename = ${patid}.`echo $File | cut -d. -f2,3,4,5,6,7,8,9,10`
					cp -r $File ${SubjectHome}/Anatomical/Surface/${FolderName}/${NewFilename}
					if($status) exit 1
				end
			popd
		end
		exit 0
	else
		set t4 = "${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat"
		set FreeSurferFolder = " ${SubjectHome}/Freesurfer/${FreesurferVersionToUse}"
	endif

	if( ! -e $t4 ) then
		echo "SCRIPT: $0 : 00003 : Could not to find orig to t1 transform ($t4). Unable to continue."
		exit 1
	endif

	set T1_target = ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii
	if(! -e $T1_target) then
		set T1_target = ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz
	endif

	if(! -e $T1_target) then
		echo "SCRIPT: $0 : 00004 : Cannot find $T1_target"
		exit 1
	endif

	set orig_target = ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig.nii
	if(! -e $orig_target) then
		echo "SCRIPT: $0 : 00005 : Cannot find $orig_target"
		exit 1
	endif

	#For Freesurfer6 compatibility
	if(! -e ${FreeSurferFolder}/label/lh.BA.annot && -e ${FreeSurferFolder}/label/lh.BA_exvivo.annot) then
		pushd ${FreeSurferFolder}/label
			cp -s lh.BA_exvivo.annot lh.BA.annot
			if($status) exit 1
		popd
	else if(! -e ${FreeSurferFolder}/label/lh.BA.annot) then
		echo "SCRIPT: $0 : 00006 : reesurfer 5.3 or higher did not create the lh.BA.annot files. Please rerun freesurfer and generate it."
		exit 1
	endif

	if(! -e ${FreeSurferFolder}/label/rh.BA.annot && -e ${FreeSurferFolder}/label/rh.BA_exvivo.annot) then
		pushd ${FreeSurferFolder}/label
			cp -s rh.BA_exvivo.annot rh.BA.annot
			if($status) exit 1
		popd
	else if(! -e ${FreeSurferFolder}/label/rh.BA.annot) then
		echo "SCRIPT: $0 : 00007 : Freesurfer 5.3 or higher did not create the rh.BA.annot files. Please rerun freesurfer and generate it."
		exit 1
	endif

		if( -e ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz) then
			ln -s ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii.gz ${SubjectHome}/Anatomical/Surface/${patid}_T1.nii.gz
			if($status) exit 1
		else if(-e ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii) then
			cp ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1.nii ${SubjectHome}/Anatomical/Surface/${patid}_T1.nii
			pushd ${SubjectHome}/Anatomical/Surface

				gzip ${patid}_T1.nii
				if($status) exit 1
			popd
		else
			echo "SCRIPT: $0 : 00008 : ERROR: could not find a T1 in ${SubjectHome}/Anatomical/Volume/T1/"
			exit 1
		endif
		mri_convert $FreeSurferFolder/mri/brainmask.mgz $FreeSurferFolder/mri/brainmask.nii.gz
		if($status) exit 1

		#binarize the freesurfer mask
		fslmaths $FreeSurferFolder/mri/brainmask.nii.gz -bin ${SubjectHome}/Anatomical/Surface/native_mask.nii.gz
		if($status) exit 1

		if (! -e  xfms/zero.nii.gz ) then
			mkdir xfms
			pushd xfms

				fslmaths $FreeSurferFolder/mri/brainmask.nii.gz -mul 0 zero.nii.gz
				if ( $status ) exit $status

				fslmerge -t zero_.nii.gz zero.nii.gz zero.nii.gz zero.nii.gz
				if ( $status ) exit $status

				mv -f zero_.nii.gz zero.nii.gz
				if ( $status ) exit $status
			popd
		endif

		# Run FreeSurfer2CaretConvertAndRegisterNonlinear
		echo  $HCPPIPEDIR_PostFS"/FreeSurfer2CaretConvertAndRegisterNonlinear_v3.sh "$SubjectHome" "$patid" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$FreeSurferFolder" "$FreeSurferInput" "$T1wRestoreImage" "$T2wRestoreImage" "$SurfaceAtlasDIR" "$HighResMesh" "$LowResMesh" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$AtlasSpaceT2wImage" "${SubjectHome}/Anatomical/Surface/native_mask" "$FreeSurferLabels" "$GrayordinatesSpaceDIR" "$GrayordinatesResolution" "$SubcorticalGrayLabels

		$HCPPIPEDIR_PostFS/FreeSurfer2CaretConvertAndRegisterNonlinear_v3.sh $SubjectHome $patid $T1wFolder $AtlasSpaceFolder $NativeFolder $FreeSurferFolder $FreeSurferInput $T1wRestoreImage $T2wRestoreImage $SurfaceAtlasDIR $HighResMesh $LowResMesh $AtlasTransform $InverseAtlasTransform $AtlasSpaceT1wImage $AtlasSpaceT2wImage ${SubjectHome}/Anatomical/Surface/native_mask $FreeSurferLabels $GrayordinatesSpaceDIR $GrayordinatesResolution $SubcorticalGrayLabels >! ${SubjectHome}/Logs/${patid}_FreeSurfer2CaretConvertAndRegisterNonlinear_v3_out.log

		if ( $status ) then
			echo "SCRIPT: $0 : 00009 : failed initial gifti surface creation"
			exit 1
		endif

		mkdir fsaverage_LR${HighResMesh}k
		mv *.${HighResMesh}k* fsaverage_LR${HighResMesh}k/

		# Transform gifti surfaces to reflect the atlas registered
		# volumes. The HCP combines the linear and non linear transforms, but since we are
		# starting with atlas transformed volumes and not orig spaced volumes, it is
		# more difficult. In the future it will be a single transform.
		# Files are produced during this step that help with ecog surface registration.
		mkdir ${AtlasName}_${LowResMesh}k
		mkdir ${AtlasName}_${HighResMesh}k	#storing the 164k atlas transformed meshes
		cp ${PP_SCRIPTS}/BLANK.spec ${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec

		#add mpr to spec file
		wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111.nii.gz

		if( $NonLinear) then
			wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_111_fnirt.nii.gz
		endif

		#add t2w to the spec file if it exists
		if(-e ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111.nii.gz) then
			wb_command -add-to-spec-file ${SubjectHome}/${AtlasSpaceFolder}/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID $SubjectHome/Anatomical/Volume/T2/${patid}_T2_111.nii.gz
		endif

		if( -e ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111_fnirt.nii.gz) then
			wb_command -add-to-spec-file ${SubjectHome}/${AtlasSpaceFolder}/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/T2/${patid}_T2_111_fnirt.nii.gz
		endif

		#add flair to the spec file if it exists
		if(-e ${SubjectHome}/Anatomical/Volume/FLAIR/${patid}_FLAIR_111.nii.gz) then
			wb_command -add-to-spec-file ${SubjectHome}/${AtlasSpaceFolder}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/FLAIR/${patid}_FLAIR_111.nii.gz
		endif

		if( -e ${SubjectHome}/Anatomical/Volume/FLAIR/${patid}_FLAIR_111_fnirt.nii.gz) then
			wb_command -add-to-spec-file ${SubjectHome}/${AtlasSpaceFolder}/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${SubjectHome}/Anatomical/Volume/FLAIR/${patid}_FLAIR_111_fnirt.nii.gz
		endif

		#include the target for reference and visual QC
		if(-e ${target}.nii.gz) then
			wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${target}.nii.gz
		else
			wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec INVALID ${target}.nii
		endif

		foreach surf ( midthickness pial white inflated sphere very_inflated)

			foreach si (L R )

				#Set a bunch of different ways of saying left and right - for the spec files
				if( $si == "L" ) then
					set hemisphere="l"
					set Structure="CORTEX_LEFT"
				else
					set hemisphere="r"
					set Structure="CORTEX_RIGHT"
				endif

				foreach mesh (${LowResMesh} ${HighResMesh})
					set gii_in=${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${mesh}k/${patid}.${si}.${surf}.${mesh}k_fs_LR.surf.gii
					set gii_out=${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${mesh}k/${patid}.${si}.${surf}.${mesh}k_fs_LR.surf.gii

					if(! -e $gii_in) then
						echo "SCRIPT: $0 : 00010 : $gii_in does not exist"
						exit 1
					endif

					wb_command -surface-apply-affine $gii_in $t4 $gii_out".affine" -flirt $orig_target $T1_target
					if($status) exit 1

					if(! -e $gii_out".affine" ) then
						echo "SCRIPT: $0 : 00011 : affine transforming surfaces from freesurfer ${mesh}k to T1 failed! ${gii_out}.affine does not exist"
						exit 1
					endif

					#apply the non linear alignment
					#but not to the spheres, we just use them for resampling mesh spaces at this point
					if($NonLinear && $surf != "sphere") then
						wb_command -surface-apply-warpfield $gii_out".affine" $NonLinInverseAtlasTransform $gii_out -fnirt $NonLinAtlasTransform
						if($status) exit 1
					else if($target != "") then
						wb_command -surface-apply-affine $gii_out".affine" ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_to_${AtlasName}.mat $gii_out -flirt $T1_target $target".nii.gz"
						if($status) exit 1
					else
						cp $gii_out".affine" $gii_out
					endif

					rm $gii_out".affine"

					set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${mesh}k/${patid}.${si}.roi.${mesh}k_fs_LR.shape.gii
					set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${mesh}k/${patid}.${si}.roi.${mesh}k_fs_LR.shape.gii
					cp -f $srcA $targA
# 					if($status) exit 1

					#copy over the resampling spheres, not registration sphere, for each mesh
					set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${mesh}k/${patid}.${si}.sphere.${mesh}k_fs_LR.surf.gii
					set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${mesh}k/${patid}.${si}.sphere.reg.reg_LR.${mesh}k_fs_LR.surf.gii
					cp -f $srcA $targA
					if($status) exit 1

					set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${mesh}k/${patid}.${si}.sphere.${mesh}k_fs_LR.surf.gii
					set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${mesh}k/${patid}.${si}.sphere.${mesh}k_fs_LR.surf.gii
					cp -f $srcA $targA
					if($status) exit 1

					set srcA =  ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${mesh}k/${patid}.${si}.atlasroi.${mesh}k_fs_LR.shape.gii
					set targA = ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${mesh}k/${patid}.${si}.atlasroi.${mesh}k_fs_LR.shape.gii
					cp -f $srcA $targA
					if($status) exit 1
				end
				# Preparations for fMRI processing - more of a formality
				wb_command -metric-math "thickness > 0" ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/${patid}.${si}.roi.${HighResMesh}k_fs_LR.shape.gii -var thickness ${SubjectHome}/$AtlasSpaceFolder/fsaverage_LR${HighResMesh}k/${patid}.${si}.thickness.${HighResMesh}k_fs_LR.shape.gii
				if ( $status ) exit 1

				#add the low res meshes to the spec file
				wb_command -add-to-spec-file ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$patid"."$LowResMesh"k.${AtlasName}.LR.wb.spec $Structure ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k/"$patid"."$si"."$surf"."$LowResMesh"k_fs_LR.surf.gii
			end
		end

popd

exit 0
