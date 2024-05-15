#!/bin/bash
set -e
echo -e "\n START: RibbonVolumeToSurfaceMapping"
#HCPPIPEDIR="/data/nil-bluearc/corbetta/Hacker/Process/HCP/PIPE/"
#CARET7DIR="${HCPPIPEDIR}/global/binaries/caret7/bin_rh_linux64"
WorkingDirectory="$1"
VolumefMRI="$2"
Subject="$3"
DownsampleFolder="$4"
LowResMesh="$5"
AtlasSpaceNativeFolder="$6"
T1wNativeFolder="$7"
RawBOLD="$8"

NeighborhoodSmoothing="5"
Factor="0.5"	#was 0.5
LeftGreyRibbonValue="1"
RightGreyRibbonValue="1"

for Hemisphere in L R ; do
  if [ $Hemisphere = "L" ] ; then
    GreyRibbonValue="$LeftGreyRibbonValue"
  elif [ $Hemisphere = "R" ] ; then
    GreyRibbonValue="$RightGreyRibbonValue"
  fi
  ${CARET7DIR}/wb_command -create-signed-distance-volume "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.164k_fs_LR.surf.gii "$VolumefMRI"_SBRef.nii.gz "$WorkingDirectory"/"$Subject"."$Hemisphere".white.164k_fs_LR.nii.gz
  ${CARET7DIR}/wb_command -create-signed-distance-volume "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.164k_fs_LR.surf.gii "$VolumefMRI"_SBRef.nii.gz "$WorkingDirectory"/"$Subject"."$Hemisphere".pial.164k_fs_LR.nii.gz
  fslmaths "$WorkingDirectory"/"$Subject"."$Hemisphere".white.164k_fs_LR.nii.gz -thr 0 -bin -mul 255 "$WorkingDirectory"/"$Subject"."$Hemisphere".white_thr0.164k_fs_LR.nii.gz
  fslmaths "$WorkingDirectory"/"$Subject"."$Hemisphere".white_thr0.164k_fs_LR.nii.gz -bin "$WorkingDirectory"/"$Subject"."$Hemisphere".white_thr0.164k_fs_LR.nii.gz
  fslmaths "$WorkingDirectory"/"$Subject"."$Hemisphere".pial.164k_fs_LR.nii.gz -uthr 0 -abs -bin -mul 255 "$WorkingDirectory"/"$Subject"."$Hemisphere".pial_uthr0.164k_fs_LR.nii.gz
  fslmaths "$WorkingDirectory"/"$Subject"."$Hemisphere".pial_uthr0.164k_fs_LR.nii.gz -bin "$WorkingDirectory"/"$Subject"."$Hemisphere".pial_uthr0.164k_fs_LR.nii.gz
  fslmaths "$WorkingDirectory"/"$Subject"."$Hemisphere".pial_uthr0.164k_fs_LR.nii.gz -mas "$WorkingDirectory"/"$Subject"."$Hemisphere".white_thr0.164k_fs_LR.nii.gz -mul 255 "$WorkingDirectory"/"$Subject"."$Hemisphere".ribbon.nii.gz
  fslmaths "$WorkingDirectory"/"$Subject"."$Hemisphere".ribbon.nii.gz -bin -mul $GreyRibbonValue "$WorkingDirectory"/"$Subject"."$Hemisphere".ribbon.nii.gz
  #rm "$WorkingDirectory"/"$Subject"."$Hemisphere".white.164k_fs_LR.nii.gz "$WorkingDirectory"/"$Subject"."$Hemisphere".white_thr0.164k_fs_LR.nii.gz "$WorkingDirectory"/"$Subject"."$Hemisphere".pial.164k_fs_LR.nii.gz "$WorkingDirectory"/"$Subject"."$Hemisphere".pial_uthr0.164k_fs_LR.nii.gz
done

fslmaths "$WorkingDirectory"/"$Subject".L.ribbon.nii.gz -add "$WorkingDirectory"/"$Subject".R.ribbon.nii.gz "$WorkingDirectory"/ribbon_only.nii.gz
rm "$WorkingDirectory"/"$Subject".L.ribbon.nii.gz "$WorkingDirectory"/"$Subject".R.ribbon.nii.gz

#use the raw bold to determine the coefficient of variance. Should be atlas transformed
fslmaths "$RawBOLD" -Tmean "$WorkingDirectory"/mean -odt float
fslmaths "$RawBOLD" -Tstd "$WorkingDirectory"/std -odt float
fslmaths "$WorkingDirectory"/std -div "$WorkingDirectory"/mean "$WorkingDirectory"/cov

#clears out parts of the mask that are outside of the acquired brain.
fslmaths "$WorkingDirectory"/cov.nii.gz -uthr 1.0 "$WorkingDirectory"/cov.nii.gz

fslmaths "$WorkingDirectory"/cov -mas "$WorkingDirectory"/ribbon_only.nii.gz "$WorkingDirectory"/cov_ribbon

fslmaths "$WorkingDirectory"/cov_ribbon -div `fslstats "$WorkingDirectory"/cov_ribbon -M` "$WorkingDirectory"/cov_ribbon_norm
fslmaths "$WorkingDirectory"/cov_ribbon_norm -bin -s $NeighborhoodSmoothing "$WorkingDirectory"/SmoothNorm
fslmaths "$WorkingDirectory"/cov_ribbon_norm -s $NeighborhoodSmoothing -div "$WorkingDirectory"/SmoothNorm -dilD "$WorkingDirectory"/cov_ribbon_norm_s$NeighborhoodSmoothing
fslmaths "$WorkingDirectory"/cov -div `fslstats "$WorkingDirectory"/cov_ribbon -M` -div "$WorkingDirectory"/cov_ribbon_norm_s$NeighborhoodSmoothing "$WorkingDirectory"/cov_norm_modulate
fslmaths "$WorkingDirectory"/cov_norm_modulate -mas "$WorkingDirectory"/ribbon_only.nii.gz "$WorkingDirectory"/cov_norm_modulate_ribbon

STD=`fslstats "$WorkingDirectory"/cov_norm_modulate_ribbon -S`
echo $STD
MEAN=`fslstats "$WorkingDirectory"/cov_norm_modulate_ribbon -M`
echo $MEAN
Lower=`echo "$MEAN - ($STD * $Factor)" | bc -l`
echo $Lower
Upper=`echo "$MEAN + ($STD * $Factor)" | bc -l`
echo $Upper

fslmaths "$WorkingDirectory"/mean -bin "$WorkingDirectory"/mask
fslmaths "$WorkingDirectory"/cov_norm_modulate -thr $Upper -bin -sub "$WorkingDirectory"/mask -mul -1 "$WorkingDirectory"/goodvoxels

niftigz_4dfp -4 "$WorkingDirectory"/goodvoxels "$WorkingDirectory"/goodvoxels
  niftigz_4dfp -n "$WorkingDirectory"/goodvoxels "$WorkingDirectory"/goodvoxels
  rm "$WorkingDirectory"/*.4dfp.*
  
for Hemisphere in L R ; do
  for Map in mean cov ; do
	#workbench does a strict header check on volume to surface mapping. This conversion 
	#to 4dfp and back to nifti is purely to allow that strict check to pass since the 
	#functional BOLD data comes from 4dfp and lacks a lot of the header information
	#normally present in "whole" nifti headers
  echo `which niftigz_4dfp`
  
    niftigz_4dfp -4 "$WorkingDirectory"/"$Map" "$WorkingDirectory"/"$Map"
    niftigz_4dfp -n "$WorkingDirectory"/"$Map" "$WorkingDirectory"/"$Map"
    rm "$WorkingDirectory"/"$Map"*.4dfp*
    ${CARET7DIR}/wb_command -volume-to-surface-mapping "$WorkingDirectory"/"$Map".nii.gz "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii "$WorkingDirectory"/"$Hemisphere"."$Map".164k_fs_LR.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.164k_fs_LR.surf.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.164k_fs_LR.surf.gii -volume-roi "$WorkingDirectory"/goodvoxels.nii.gz
    ${CARET7DIR}/wb_command -metric-dilate "$WorkingDirectory"/"$Hemisphere"."$Map".164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii 10 "$WorkingDirectory"/"$Hemisphere"."$Map".164k_fs_LR.func.gii -nearest
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere"."$Map".164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".roi.164k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere"."$Map".164k_fs_LR.func.gii
    ${CARET7DIR}/wb_command -volume-to-surface-mapping "$WorkingDirectory"/"$Map".nii.gz "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii "$WorkingDirectory"/"$Hemisphere"."$Map"_all.164k_fs_LR.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.164k_fs_LR.surf.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.164k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere"."$Map"_all.164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".roi.164k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere"."$Map"_all.164k_fs_LR.func.gii
    ${CARET7DIR}/wb_command -metric-resample "$WorkingDirectory"/"$Hemisphere"."$Map".164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.164k_fs_LR.surf.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$WorkingDirectory"/"$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.func.gii -area-surfs "$T1wNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".roi.164k_fs_LR.shape.gii
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.func.gii
    ${CARET7DIR}/wb_command -metric-resample "$WorkingDirectory"/"$Hemisphere"."$Map"_all.164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.164k_fs_LR.surf.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$WorkingDirectory"/"$Hemisphere"."$Map"_all."$LowResMesh"k_fs_LR.func.gii -area-surfs "$T1wNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".roi.164k_fs_LR.shape.gii
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere"."$Map"_all."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere"."$Map"_all."$LowResMesh"k_fs_LR.func.gii
  done
  ${CARET7DIR}/wb_command -volume-to-surface-mapping "$WorkingDirectory"/goodvoxels.nii.gz "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii "$WorkingDirectory"/"$Hemisphere".goodvoxels.164k_fs_LR.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.164k_fs_LR.surf.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.164k_fs_LR.surf.gii
  ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere".goodvoxels.164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".roi.164k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere".goodvoxels.164k_fs_LR.func.gii
  ${CARET7DIR}/wb_command -metric-resample "$WorkingDirectory"/"$Hemisphere".goodvoxels.164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.164k_fs_LR.surf.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$WorkingDirectory"/"$Hemisphere".goodvoxels."$LowResMesh"k_fs_LR.func.gii -area-surfs "$T1wNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".roi.164k_fs_LR.shape.gii
  ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere".goodvoxels."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere".goodvoxels."$LowResMesh"k_fs_LR.func.gii
  
  ${CARET7DIR}/wb_command -volume-to-surface-mapping "$VolumefMRI".nii.gz "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii "$VolumefMRI"."$Hemisphere".164k_fs_LR.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".white.164k_fs_LR.surf.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".pial.164k_fs_LR.surf.gii -volume-roi "$WorkingDirectory"/goodvoxels.nii.gz
  ${CARET7DIR}/wb_command -metric-dilate "$VolumefMRI"."$Hemisphere".164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii 10 "$VolumefMRI"."$Hemisphere".164k_fs_LR.func.gii -nearest
  ${CARET7DIR}/wb_command -metric-mask  "$VolumefMRI"."$Hemisphere".164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".roi.164k_fs_LR.shape.gii  "$VolumefMRI"."$Hemisphere".164k_fs_LR.func.gii
  ${CARET7DIR}/wb_command -metric-resample "$VolumefMRI"."$Hemisphere".164k_fs_LR.func.gii "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.164k_fs_LR.surf.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$VolumefMRI"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.func.gii -area-surfs "$T1wNativeFolder"/"$Subject"."$Hemisphere".midthickness.164k_fs_LR.surf.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceNativeFolder"/"$Subject"."$Hemisphere".roi.164k_fs_LR.shape.gii
  ${CARET7DIR}/wb_command -metric-mask "$VolumefMRI"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Subject"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$VolumefMRI"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.func.gii
done

echo " END: RibbonVolumeToSurfaceMapping"

