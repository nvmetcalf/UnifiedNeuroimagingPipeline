#!/bin/bash 
set -e
echo -e "\n START: SubcorticalProcessing"
HCPPIPEDIR="/data/nil-bluearc/corbetta/Hacker/Process/HCP/PIPE/"
CARET7DIR="${HCPPIPEDIR}/global/binaries/caret7/bin_rh_linux64"
AtlasSpaceFolder="$1"
ROIFolder="$2"
FinalfMRIResolution="$3"
VolumefMRI="$4"
SmoothingFWHM="$5"
BrainOrdinatesResolution="$6"

#need to extract the roi's from the wmparc

set SubcorticalGrayLabels="${HCPPIPEDIR_Config}/FreeSurferSubcorticalLabelTableLut.txt"
set GrayordinatesSpaceDIR="${HCPPIPEDIR_Templates}/91282_Greyordinates" #(Need to copy these in)

#Import ROIs
cp "$GrayordinatesSpaceDIR"/Atlas_ROIs."$GrayordinatesResolution".nii.gz "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz
applywarp --interp=nn -i "$AtlasSpaceFolder"/wmparc.nii.gz -r "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz -o "$AtlasSpaceFolder"/ROIs/wmparc."$GrayordinatesResolution".nii.gz
${CARET7DIR}/wb_command -volume-label-import "$AtlasSpaceFolder"/ROIs/wmparc."$GrayordinatesResolution".nii.gz "$FreeSurferLabels" "$AtlasSpaceFolder"/ROIs/wmparc."$GrayordinatesResolution".nii.gz -drop-unused-labels
applywarp --interp=nn -i "$SurfaceAtlasDIR"/CCNMD_MyelinMapping_Avgwmparc.nii.gz -r "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz -o "$AtlasSpaceFolder"/ROIs/Atlas_wmparc."$GrayordinatesResolution".nii.gz
${CARET7DIR}/wb_command -volume-label-import "$AtlasSpaceFolder"/ROIs/Atlas_wmparc."$GrayordinatesResolution".nii.gz "$FreeSurferLabels" "$AtlasSpaceFolder"/ROIs/Atlas_wmparc."$GrayordinatesResolution".nii.gz -drop-unused-labels
${CARET7DIR}/wb_command -volume-label-import "$AtlasSpaceFolder"/ROIs/wmparc."$GrayordinatesResolution".nii.gz ${SubcorticalGrayLabels} "$AtlasSpaceFolder"/ROIs/ROIs."$GrayordinatesResolution".nii.gz -discard-others
applywarp --interp=spline -i "$AtlasSpaceFolder"/"$AtlasSpaceT2wImage".nii.gz -r "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz -o "$AtlasSpaceFolder"/"$AtlasSpaceT2wImage"."$GrayordinatesResolution".nii.gz
applywarp --interp=spline -i "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage".nii.gz -r "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz -o "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage"."$GrayordinatesResolution".nii.gz


Sigma=`echo "$SmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`

if [ `echo "if ( $BrainOrdinatesResolution == $FinalfMRIResolution ) { 1 }" | bc -l` -eq 1 ] ; then
  ${CARET7DIR}/wb_command -volume-parcel-resampling "$VolumefMRI".nii.gz "$ROIFolder"/ROIs."$FinalfMRIResolution".nii.gz "$ROIFolder"/Atlas_ROIs."$BrainOrdinatesResolution".nii.gz $Sigma "$VolumefMRI"_AtlasSubcortical_s"$SmoothingFWHM".nii.gz -fix-zeros
else
  ${CARET7DIR}/wb_command -volume-parcel-resampling-generic "$VolumefMRI".nii.gz "$ROIFolder"/ROIs."$FinalfMRIResolution".nii.gz "$ROIFolder"/Atlas_ROIs."$BrainOrdinatesResolution".nii.gz $Sigma "$VolumefMRI"_AtlasSubcortical_s"$SmoothingFWHM".nii.gz -fix-zeros
fi  
echo " END: SubcorticalProcessing"

