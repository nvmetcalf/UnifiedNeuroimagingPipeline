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

#set the non linear alignment flag to 0 if it doesn't exist
if(! $?NonLinear) set NonLinear = 0
set AtlasSpaceFolder="Anatomical/Surface"

if(! $?BOLD_FinalResolution) then
	set FinalResolution = 1
else
	set FinalResolution = $BOLD_FinalResolution
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"
set SubjectHome = $cwd
if($target != "") then
	set AtlasName = $target:t
else
	set AtlasName = T1
endif

set T1wFolder="${cwd}/Anatomical/Volume/T1" #Location of T1w images

pushd $AtlasSpaceFolder

	if($day1_path == "") then
		if($NonLinear) then
			${PP_SCRIPTS}/HCP/PostFreeSurfer/scripts/CreateRibbon_StandAlone.sh ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k $patid "$T1wFolder/${patid}_T1_${FinalResTrailer}_fnirt.nii.gz" ${LowResMesh}
		else
			${PP_SCRIPTS}/HCP/PostFreeSurfer/scripts/CreateRibbon_StandAlone.sh ${SubjectHome}/$AtlasSpaceFolder/${AtlasName}_${LowResMesh}k $patid "$T1wFolder/${patid}_T1_${FinalResTrailer}.nii.gz" ${LowResMesh}
		endif

		if($status) then
			echo "SCRIPT: $0 : 00003 : failed to create cortical ribbon."
			exit 1
		endif
	else
		rm $AtlasSpaceFolder/RibbonVolumeToSurfaceMapping
		ln -s ${day1_path}/Anatomical/Surface/RibbonVolumeToSurfaceMapping RibbonVolumeToSurfaceMapping
		if($status) exit 1
	endif

	#this is the end IF there is no bold
	if(! $?FCProcIndex) then
		echo "No BOLD to project. Finished."
		exit 0
	endif

	if(-e "$cwd"/RibbonVolumeToSurfaceMapping) then
		rm -fr "$cwd"/RibbonVolumeToSurfaceMapping
	endif

	mkdir "$cwd"/RibbonVolumeToSurfaceMapping

	if($NonLinear) then
		set UsedVoxelsMask = ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}
		ln -sf ${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}_fnirt.nii.gz ${SubjectHome}/"$AtlasSpaceFolder"/RibbonVolumeToSurfaceMapping/BOLD_ref_${FinalResTrailer}.nii.gz
	else
		ln -sf ${SubjectHome}/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_${FinalResTrailer}.nii.gz ${SubjectHome}/"$AtlasSpaceFolder"/RibbonVolumeToSurfaceMapping/BOLD_ref_${FinalResTrailer}.nii.gz
		set UsedVoxelsMask = ${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}
	endif

popd

exit 0
