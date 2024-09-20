#!/bin/bash
set -e
echo -e "\n START: CreateRibbon"

AtlasSpaceNativeFolder="$1"
Subject="$2"
ReferenceRibbonVolume="$3"
LowResMesh="$4"

LeftGreyRibbonValue="3"
LeftWhiteMaskValue="2"
RightGreyRibbonValue="42"
RightWhiteMaskValue="41"

for Hemisphere in L R ; do
  if [ $Hemisphere = "L" ] ; then
    GreyRibbonValue="$LeftGreyRibbonValue"
  elif [ $Hemisphere = "R" ] ; then
    GreyRibbonValue="$RightGreyRibbonValue"
  fi    

  ${CARET7DIR}/wb_command -create-signed-distance-volume "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.${LowResMesh}k_fs_LR.surf.gii $ReferenceRibbonVolume "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.${LowResMesh}k_fs_LR.nii.gz
  ${CARET7DIR}/wb_command -create-signed-distance-volume "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.${LowResMesh}k_fs_LR.surf.gii $ReferenceRibbonVolume "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.${LowResMesh}k_fs_LR.nii.gz
  fslmaths "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.${LowResMesh}k_fs_LR.nii.gz -thr 0 -bin -mul 255 "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white_thr0.${LowResMesh}k_fs_LR.nii.gz
  fslmaths "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white_thr0.${LowResMesh}k_fs_LR.nii.gz -bin "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white_thr0.${LowResMesh}k_fs_LR.nii.gz
  fslmaths "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.${LowResMesh}k_fs_LR.nii.gz -uthr 0 -abs -bin -mul 255 "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial_uthr0.${LowResMesh}k_fs_LR.nii.gz
  fslmaths "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial_uthr0.${LowResMesh}k_fs_LR.nii.gz -bin "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial_uthr0.${LowResMesh}k_fs_LR.nii.gz
  fslmaths "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial_uthr0.${LowResMesh}k_fs_LR.nii.gz -mas "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white_thr0.${LowResMesh}k_fs_LR.nii.gz -mul 255 "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".ribbon.nii.gz
  fslmaths "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".ribbon.nii.gz -bin -mul $GreyRibbonValue "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".ribbon.nii.gz
  #rm "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.${LowResMesh}k_fs_LR.nii.gz "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white_thr0.${LowResMesh}k_fs_LR.nii.gz "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.${LowResMesh}k_fs_LR.nii.gz "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial_uthr0.${LowResMesh}k_fs_LR.nii.gz
done

rm -rf "$AtlasSpaceNativeFolder"/Results
mkdir "$AtlasSpaceNativeFolder"/Results
fslmaths "$AtlasSpaceNativeFolder"/"$Subject".L.ribbon.nii.gz -add "$AtlasSpaceNativeFolder"/"$Subject".R.ribbon.nii.gz "$AtlasSpaceNativeFolder"/Results/ribbon_only.nii.gz
rm "$AtlasSpaceNativeFolder"/"$Subject".L.ribbon.nii.gz "$AtlasSpaceNativeFolder"/"$Subject".R.ribbon.nii.gz

