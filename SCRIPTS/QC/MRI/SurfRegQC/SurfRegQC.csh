#!/bin/csh

if($#argv < 3) then
	echo "SurfRegQC <SubjectID> <SubjectPath> <AtlasName> <low res mesh> <mask trailer>"
	exit 1
endif

set SubjectID = $1
set SubjectPath = $cwd
set OutputPath = ${SubjectPath}/QC
set AtlasName = $3
set LowResMesh = $4
set MaskTrailer = $5

pushd QC
	rm $SubjectPath/*scene

	#Generate the screens
	echo "Generating scenes..."

	if(-e ${SubjectPath}/Anatomical/T1/${SubjectID}_T1T_111_fnirt.nii.gz) then
		set MPR_ATL = "${SubjectPath}/Anatomical/T1/${SubjectID}_T1_111_fnirt.nii.gz"
	else
		set MPR_ATL = "${SubjectPath}/Anatomical/T1/${SubjectID}_T1_111.nii.gz"
	endif

	$PP_SCRIPTS/QC/SurfRegQC/gen_SurfaceSD.sh $SubjectID $SubjectPath $LowResMesh $AtlasName
	$PP_SCRIPTS/QC/SurfRegQC/gen_LesionSurfaceProjected.sh $SubjectID $SubjectPath $LowResMesh $AtlasName
	$PP_SCRIPTS/QC/SurfRegQC/gen_VolumeLesionWithSurfaceOutline.sh $SubjectID $SubjectPath $LowResMesh $AtlasName

	#Capture the scenes
	echo "Caputuring scense..."
	$PP_SCRIPTS/QC/SurfRegQC/capture_SurfaceSD.sh $SubjectID 3840 2180
	$PP_SCRIPTS/QC/SurfRegQC/capture_LesionSurfaceProjected.sh $SubjectID 3840 2180
	$PP_SCRIPTS/QC/SurfRegQC/capture_VolumeLesionWithSurfaceOutline.sh $SubjectID 3840 2180

popd
