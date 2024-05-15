#!/bin/csh

echo "START: CreateDenseTimeSeries"

#HCPPIPEDIR="/data/nil-bluearc/corbetta/Hacker/Process/HCP/PIPE/"
#CARET7DIR="${HCPPIPEDIR}/global/binaries/caret7/bin_rh_linux64"

set DownSampleFolder="$1"
set Subject="$2"
set LowResMesh="$3"
set NameOffMRI="$4"
set ROIFolder="$5"
set OutputAtlasDenseTimeseries="$6"
set GrayordinatesResolution="$7"
set SubCortical="$8"
set IncludeSubCortical=${9}
set BOLD_TR=$10
set FinalResolution=$11


#Some way faster and more concise code:

if( -e $SubCortical && $IncludeSubCortical == 1) then
	echo "creating dense time series WITH sub-cortical"

	echo ${CARET7DIR}/wb_command -cifti-create-dense-timeseries "$OutputAtlasDenseTimeseries".dtseries.nii -volume "$SubCortical" ROIs.${FinalResolution}.nii.gz -left-metric "$NameOffMRI".L.atlasroi."$LowResMesh"k_fs_LR.func.gii -roi-left "$DownSampleFolder"/"$Subject".L.atlasroi."$LowResMesh"k_fs_LR.shape.gii -right-metric "$NameOffMRI".R.atlasroi."$LowResMesh"k_fs_LR.func.gii -roi-right "$DownSampleFolder"/"$Subject".R.atlasroi."$LowResMesh"k_fs_LR.shape.gii -timestep "$BOLD_TR"
	${CARET7DIR}/wb_command -cifti-create-dense-timeseries "$OutputAtlasDenseTimeseries".dtseries.nii -volume "$SubCortical" ROIs.${FinalResolution}.nii.gz -left-metric "$NameOffMRI".L.atlasroi."$LowResMesh"k_fs_LR.func.gii -roi-left "$DownSampleFolder"/"$Subject".L.atlasroi."$LowResMesh"k_fs_LR.shape.gii -right-metric "$NameOffMRI".R.atlasroi."$LowResMesh"k_fs_LR.func.gii -roi-right "$DownSampleFolder"/"$Subject".R.atlasroi."$LowResMesh"k_fs_LR.shape.gii -timestep "$BOLD_TR"
else
	echo "creating dense time series WITHOUT sub-cortical"
	${CARET7DIR}/wb_command -cifti-create-dense-timeseries "$OutputAtlasDenseTimeseries".dtseries.nii -left-metric "$NameOffMRI".L.atlasroi."$LowResMesh"k_fs_LR.func.gii -roi-left "$DownSampleFolder"/"$Subject".L.atlasroi."$LowResMesh"k_fs_LR.shape.gii -right-metric "$NameOffMRI".R.atlasroi."$LowResMesh"k_fs_LR.func.gii -roi-right "$DownSampleFolder"/"$Subject".R.atlasroi."$LowResMesh"k_fs_LR.shape.gii -timestep "$BOLD_TR"
endif

if($status) then
	echo "Error in creating CIFTI surface"
	exit 1
endif

echo " END: CreateDenseTimeSeries"
