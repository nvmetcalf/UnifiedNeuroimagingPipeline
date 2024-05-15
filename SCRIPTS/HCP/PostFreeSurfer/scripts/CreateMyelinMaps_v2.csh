#!/bin/csh

set echo



set LeftGreyRibbonValue="3"
set RightGreyRibbonValue="42"
set MyelinMappingFWHM="5"
set SurfaceSmoothingFWHM="2"
set MyelinMappingSigma=`echo "$MyelinMappingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
set SurfaceSmoothingSigma=`echo "$SurfaceSmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
set CorrectionSigma=`echo "sqrt ( 200 )" | bc -l`

source $1
source $2

cd atlas

set Subject = "$patid"
set T1w = ${Subject}"_mpr_n1_111_t88_fnirt.nii.gz"
set T2w = ${Subject}"_t2wT_t88_111_fnirt.nii.gz"
set ReferenceMyelinMaps = "$PP_SCRIPTS/SurfacePipeline/HCP/global/templates/standard_mesh_atlases/Conte69.MyelinMap_BC.164k_fs_LR.dscalar.nii"

set AtlasFolder = "$AtlasName"
#set HighResMesh = 164

#for the lulz?
#${CARET7DIR}/wb_command -volume-palette ${Subject}_jacobiantransform.nii.gz MODE_AUTO_SCALE -interpolate true -disp-pos true -disp-neg false -disp-zero false -palette-name HSB8_clrmid -thresholding THRESHOLD_TYPE_NORMAL THRESHOLD_TEST_SHOW_OUTSIDE 0.5 2

$PP_SCRIPTS/SurfacePipeline/HCP/PostFreeSurfer/scripts/CreateRibbon_StandAlone.sh $AtlasName ${Subject} ${Subject}_mpr_n1_111_t88_fnirt.nii.gz
if($status) exit 1

#divide the T1 by the T2
${CARET7DIR}/wb_command -volume-math "clamp((T1w / T2w), 0, 100)" T1wDividedByT2w.nii.gz -var T1w $T1w -var T2w $T2w -fixnan 0
if($status) exit 1
${CARET7DIR}/wb_command -volume-palette T1wDividedByT2w.nii.gz MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
if($status) exit 1

#divide the T1 by T2 in just the ribbon
${CARET7DIR}/wb_command -volume-math "(T1w / T2w) * (((ribbon > ($LeftGreyRibbonValue - 0.01)) * (ribbon < ($LeftGreyRibbonValue + 0.01))) + ((ribbon > ($RightGreyRibbonValue - 0.01)) * (ribbon < ($RightGreyRibbonValue + 0.01))))" T1wDividedByT2w_ribbon.nii.gz -var T1w $T1w -var T2w $T2w -var ribbon ${AtlasFolder}/Results/ribbon_only.nii.gz
if($status) exit 1
${CARET7DIR}/wb_command -volume-palette T1wDividedByT2w_ribbon.nii.gz MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
if($status) exit 1

#${CARET7DIR}/wb_command -cifti-separate-all "$ReferenceMyelinMaps" -left Native/"$Subject".L.RefMyelinMap."$HighResMesh"k_fs_LR.func.gii -right Native/"$Subject".R.RefMyelinMap."$HighResMesh"k_fs_LR.func.gii
#if($status) exit 1


foreach Hemisphere ("L" "R")
  if ( $Hemisphere == "L" ) then 
    set Structure="CORTEX_LEFT"
    set ribbon="$LeftGreyRibbonValue"
  else if ( $Hemisphere == "R" ) then 
    set Structure="CORTEX_RIGHT"
   set ribbon="$RightGreyRibbonValue"
  endif
  
  ${CARET7DIR}/wb_command -metric-resample ${AtlasFolder}/${Subject}.${Hemisphere}.roi.native.shape.gii fsaverage/${Subject}.${Hemisphere}.sphere.164k_fs_${Hemisphere}.surf.gii fsaverage_LR${LowResMesh}k/${Subject}.${Hemisphere}.sphere.${LowResMesh}k_fs_LR.surf.gii BARYCENTRIC ${AtlasFolder}/${Subject}.${Hemisphere}.roi.${LowResMesh}K_fs_LR.shape.gii
  if($status) exit 1

  ${CARET7DIR}/wb_command -volume-math "(ribbon > ($ribbon - 0.01)) * (ribbon < ($ribbon + 0.01))" temp_ribbon.nii.gz -var ribbon ${AtlasFolder}/Results/ribbon_only.nii.gz
  if($status) exit 1
  
  ${CARET7DIR}/wb_command -volume-to-surface-mapping T1wDividedByT2w.nii.gz ${AtlasFolder}/"$Subject"."$Hemisphere".midthickness.${LowResMesh}k_fs_LR.surf.gii ${AtlasFolder}/"$Subject"."$Hemisphere".MyelinMap.${LowResMesh}k_fs_LR.func.gii -myelin-style temp_ribbon.nii.gz ${AtlasFolder}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii "$MyelinMappingSigma"
  if($status) exit 1
  
  rm temp_ribbon.nii.gz
  
  if(! -e ${AtlasFolder}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii) then
	cp fsaverage_LR${LowResMesh}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii ${AtlasFolder}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii
  endif
	
	
  ${CARET7DIR}/wb_command -metric-regression ${AtlasFolder}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii ${AtlasFolder}/"$Subject"."$Hemisphere".corrThickness.${LowResMesh}k_fs_LR.shape.gii -roi ${AtlasFolder}/"$Subject"."$Hemisphere".roi.${LowResMesh}K_fs_LR.shape.gii -remove ${AtlasFolder}/"$Subject"."$Hemisphere".curvature.${LowResMesh}k_fs_LR.shape.gii
  if($status) exit 1
  
  ${CARET7DIR}/wb_command -metric-smoothing ${AtlasFolder}/"$Subject"."$Hemisphere".midthickness.${LowResMesh}k_fs_LR.surf.gii ${AtlasFolder}/"$Subject"."$Hemisphere".MyelinMap.${LowResMesh}k_fs_LR.func.gii "$SurfaceSmoothingSigma" ${AtlasFolder}/"$Subject"."$Hemisphere".SmoothedMyelinMap.${LowResMesh}k_fs_LR.func.gii -roi ${AtlasFolder}/"$Subject"."$Hemisphere".roi.${LowResMesh}K_fs_LR.shape.gii 
  if($status) exit 1
  
#   ${CARET7DIR}/wb_command -metric-smoothing ${AtlasFolder}/"$Subject"."$Hemisphere".midthickness.32k_fs_LR.surf.gii ${AtlasFolder}/"$Subject"."$Hemisphere".MyelinMap.32k_fs_LR.func.gii "$CorrectionSigma" ${AtlasFolder}/"$Subject"."$Hemisphere".MyelinMap_s"$CorrectionSigma".32k_fs_LR.func.gii -roi ${AtlasFolder}/"$Subject"."$Hemisphere".roi.32K_fs_LR.shape.gii 
#   if($status) exit 1
  
  
#   ${CARET7DIR}/wb_command -metric-math "(Individual - Reference) * Mask" ${AtlasFolder}/"$Subject"."$Hemisphere".BiasField.native.func.gii -var Individual "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".MyelinMap_s"$CorrectionSigma".native.func.gii -var Reference "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".RefMyelinMap_s"$CorrectionSigma".native.func.gii -var Mask "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii 
#   if($status) exit 1
#   
#   ${CARET7DIR}/wb_command -metric-math "(Individual - Bias) * Mask" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".MyelinMap_BC.native.func.gii -var Individual "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".MyelinMap.native.func.gii -var Bias "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".BiasField.native.func.gii -var Mask "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii 
#   ${CARET7DIR}/wb_command -metric-math "(Individual - Bias) * Mask" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".SmoothedMyelinMap_BC.native.func.gii -var Individual "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".SmoothedMyelinMap.native.func.gii -var Bias "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".BiasField.native.func.gii -var Mask "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii 
#   rm "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".MyelinMap_s"$CorrectionSigma".native.func.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".RefMyelinMap_s"$CorrectionSigma".native.func.gii
#   for STRING in MyelinMap@func SmoothedMyelinMap@func MyelinMap_BC@func SmoothedMyelinMap_BC@func corrThickness@shape ; do
#     Map=`echo $STRING | cut -d "@" -f 1`
#     Ext=`echo $STRING | cut -d "@" -f 2`
#     ${CARET7DIR}/wb_command -set-map-name "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii 1 "$Subject"_"$Hemisphere"_"$Map"
#     ${CARET7DIR}/wb_command -metric-palette "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
#     #${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/"$NativeFolder"/"$Subject".native.wb.spec $Structure "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii
#     #${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject".native.wb.spec $Structure "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii
#     ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR."$Ext".gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
#     ${CARET7DIR}/wb_command -metric-mask "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR."$Ext".gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".atlasroi."$HighResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR."$Ext".gii
#     #${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR."$Ext".gii
#     ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR."$Ext".gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
#     ${CARET7DIR}/wb_command -metric-mask "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR."$Ext".gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR."$Ext".gii
#     #${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR."$Ext".gii
#     #${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR."$Ext".gii
#   done
end

#Create CIFTI
# for STRING in "$AtlasSpaceFolder"/"$NativeFolder"@native@roi "$AtlasSpaceFolder"@"$HighResMesh"k_fs_LR@atlasroi "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k@"$LowResMesh"k_fs_LR@atlasroi ; do
#   Folder=`echo $STRING | cut -d "@" -f 1`
#   Mesh=`echo $STRING | cut -d "@" -f 2`
#   ROI=`echo $STRING | cut -d "@" -f 3`
#   ${CARET7DIR}/wb_command -cifti-create-dense-timeseries "$Folder"/tmp.dtseries.nii -left-metric "$Folder"/"$Subject".L.MyelinMap."$Mesh".func.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.MyelinMap."$Mesh".func.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
#   echo "${Subject}_MyelinMap" > "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-convert-to-scalar "$Folder"/tmp.dtseries.nii ROW "$Folder"/tmpII.dtseries.nii -name-file "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-palette "$Folder"/tmpII.dtseries.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".MyelinMap."$Mesh".dscalar.nii -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
# 
#   ${CARET7DIR}/wb_command -cifti-create-dense-timeseries "$Folder"/tmp.dtseries.nii -left-metric "$Folder"/"$Subject".L.SmoothedMyelinMap."$Mesh".func.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.SmoothedMyelinMap."$Mesh".func.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
#   echo "${Subject}_SmoothedMyelinMap" > "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-convert-to-scalar "$Folder"/tmp.dtseries.nii ROW "$Folder"/tmpII.dtseries.nii -name-file "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-palette "$Folder"/tmpII.dtseries.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".SmoothedMyelinMap."$Mesh".dscalar.nii -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
#   
#   ${CARET7DIR}/wb_command -cifti-create-dense-timeseries "$Folder"/tmp.dtseries.nii -left-metric "$Folder"/"$Subject".L.MyelinMap_BC."$Mesh".func.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.MyelinMap_BC."$Mesh".func.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
#   echo "${Subject}_MyelinMap_BC" > "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-convert-to-scalar "$Folder"/tmp.dtseries.nii ROW "$Folder"/tmpII.dtseries.nii -name-file "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-palette "$Folder"/tmpII.dtseries.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".MyelinMap_BC."$Mesh".dscalar.nii -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
# 
#   ${CARET7DIR}/wb_command -cifti-create-dense-timeseries "$Folder"/tmp.dtseries.nii -left-metric "$Folder"/"$Subject".L.SmoothedMyelinMap_BC."$Mesh".func.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.SmoothedMyelinMap_BC."$Mesh".func.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
#   echo "${Subject}_SmoothedMyelinMap_BC" > "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-convert-to-scalar "$Folder"/tmp.dtseries.nii ROW "$Folder"/tmpII.dtseries.nii -name-file "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-palette "$Folder"/tmpII.dtseries.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".SmoothedMyelinMap_BC."$Mesh".dscalar.nii -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
# 
#   ${CARET7DIR}/wb_command -cifti-create-dense-timeseries "$Folder"/tmp.dtseries.nii -left-metric "$Folder"/"$Subject".L.corrThickness."$Mesh".shape.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.corrThickness."$Mesh".shape.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
#   echo "${Subject}_corrThickness" > "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-convert-to-scalar "$Folder"/tmp.dtseries.nii ROW "$Folder"/tmpII.dtseries.nii -name-file "$Folder"/tmp.txt
#   ${CARET7DIR}/wb_command -cifti-palette "$Folder"/tmpII.dtseries.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".corrThickness."$Mesh".dscalar.nii -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
# 
#   rm "$Folder"/tmp.txt "$Folder"/tmp.dtseries.nii "$Folder"/tmpII.dtseries.nii
# done

#Add CIFTI Maps to Spec Files
# for STRING in "$T1wFolder"/"$NativeFolder"@"$AtlasSpaceFolder"/"$NativeFolder"@native "$AtlasSpaceFolder"/"$NativeFolder"@"$AtlasSpaceFolder"/"$NativeFolder"@native "$AtlasSpaceFolder"@"$AtlasSpaceFolder"@"$HighResMesh"k_fs_LR "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k@"$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k@"$LowResMesh"k_fs_LR "$T1wFolder"/fsaverage_LR"$LowResMesh"k@"$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k@"$LowResMesh"k_fs_LR ; do
#   FolderI=`echo $STRING | cut -d "@" -f 1`
#   FolderII=`echo $STRING | cut -d "@" -f 2`
#   Mesh=`echo $STRING | cut -d "@" -f 3`
#   for STRINGII in MyelinMap_BC@dscalar SmoothedMyelinMap_BC@dscalar corrThickness@dscalar ; do
#     Map=`echo $STRINGII | cut -d "@" -f 1`
#     Ext=`echo $STRINGII | cut -d "@" -f 2`
#     ${CARET7DIR}/wb_command -add-to-spec-file "$FolderI"/"$Subject"."$Mesh".wb.spec INVALID "$FolderII"/"$Subject"."$Map"."$Mesh"."$Ext".nii
#   done
# done
# 
# echo -e "\n END: CreateMyelinMaps"

cd ..