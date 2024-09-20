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

Sigma=`echo "$SmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`

if [ `echo "if ( $BrainOrdinatesResolution == $FinalfMRIResolution ) { 1 }" | bc -l` -eq 1 ] ; then
  ${CARET7DIR}/wb_command -volume-parcel-resampling "$VolumefMRI".nii.gz "$ROIFolder"/ROIs."$FinalfMRIResolution".nii.gz "$ROIFolder"/Atlas_ROIs."$BrainOrdinatesResolution".nii.gz $Sigma "$VolumefMRI"_AtlasSubcortical_s"$SmoothingFWHM".nii.gz -fix-zeros
else
  ${CARET7DIR}/wb_command -volume-parcel-resampling-generic "$VolumefMRI".nii.gz "$ROIFolder"/ROIs."$FinalfMRIResolution".nii.gz "$ROIFolder"/Atlas_ROIs."$BrainOrdinatesResolution".nii.gz $Sigma "$VolumefMRI"_AtlasSubcortical_s"$SmoothingFWHM".nii.gz -fix-zeros
fi  
echo " END: SubcorticalProcessing"

