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

set SubjectHome = $cwd

pushd Anatomical/Surface

set Subject = "$patid"

if(-e ${SubjectHome}/Anatomical/Volume/T1/${Subject}"_T1.nii.gz") then
	set T1w = ${SubjectHome}/Anatomical/Volume/T1/${Subject}"_T1.nii.gz"
else
	set T1w = ${SubjectHome}/Anatomical/Volume/T1/${Subject}"_T1.nii"
endif

if(-e ${SubjectHome}/Anatomical/Volume/T2/${Subject}_T2_to_${Subject}_T1.nii.gz) then
	set T2w = ${SubjectHome}/Anatomical/Volume/T2/${Subject}_T2_to_${Subject}_T1.nii.gz
else
	set T2w = ${SubjectHome}/Anatomical/Volume/T2/${Subject}_T2_to_${Subject}_T1.nii
endif

set ReferenceMyelinMaps = "$PP_SCRIPTS/HCP/global/templates/standard_mesh_atlases/Conte69.MyelinMap_BC.164k_fs_LR.dscalar.nii"

if($target != "") then
	set AtlasName = `basename $target`
else
	set AtlasName = T1
endif

set AtlasFolder = ${AtlasName}_${LowResMesh}k
#set TargetDir = `dirname $target`

# if(-e $target_t1 && -e $target_t2) then
# 	#calibrate the T1 and T2
# 	matlab -nodesktop -nosplash -r "addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));Calibrate_T1_T2('${target_t1}','${TargetDir}/templates/eyemask_t88.nii.gz','${TargetDir}/templates/tempmask_t88.nii.gz','${T1w}');exit"
# 	matlab -nodesktop -nosplash -r "addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));Calibrate_T1_T2('${target_t2}','${TargetDir}/templates/eyemask_t88.nii.gz','${TargetDir}/templates/tempmask_t88.nii.gz','${T2w}');exit"
# 	#divide the T1 by the T2
# 	${CARET7DIR}/wb_command -volume-math "clamp((T1w / T2w), 0, 100)" T1wDividedByT2w.nii.gz -var T1w $T1w:r:r"_calibrated.nii.gz" -var T2w $T2w:r:r"_calibrated.nii.gz" -fixnan 0
# 	if($status) exit 1
# else
	#divide the T1 by the T2
	${CARET7DIR}/wb_command -volume-math "clamp((T1w / T2w), 0, 100)" T1wDividedByT2w.nii.gz -var T1w $T1w -var T2w $T2w -fixnan 0
	if($status) exit 1
# endif

#set HighResMesh = 164

#for the lulz?
#${CARET7DIR}/wb_command -volume-palette ${Subject}_jacobiantransform.nii.gz MODE_AUTO_SCALE -interpolate true -disp-pos true -disp-neg false -disp-zero false -palette-name HSB8_clrmid -thresholding THRESHOLD_TYPE_NORMAL THRESHOLD_TEST_SHOW_OUTSIDE 0.5 2

#$PP_SCRIPTS/HCP/PostFreeSurfer/scripts/CreateRibbon_StandAlone.sh $AtlasFolder ${Subject} ${SubjectHome}/Anatomical/Volume/T1/${Subject}_T1_111_fnirt.nii.gz $LowResMesh
#if($status) exit 1

if($NonLinear && $target != "") then
	applywarp -i T1wDividedByT2w.nii.gz -r $target -w ${SubjectHome}/Anatomical/Volume/T1/${Subject}_T1_warpfield_111.nii.gz -o T1wDividedByT2w_111_fnirt.nii.gz
	if($status) exit 1

	set MyelinAligned = T1wDividedByT2w_111_fnirt.nii.gz
else if($target != "") then
	flirt -in T1wDividedByT2w.nii.gz -r $target -out T1wDividedByT2w_111 -init ${SubjectHome}/Anatomical/Volume/T1/${Subject}_T1_to_${AtlasName}.mat -applyxfm -inter spline
	if($status) exit 1

	set MyelinAligned = T1wDividedByT2w_111.nii.gz
else
	set MyelinAligned = T1wDividedByT2w.nii.gz
endif

${CARET7DIR}/wb_command -volume-palette ${MyelinAligned} MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
if($status) exit 1

#divide the T1 by T2 in just the ribbon
# ${CARET7DIR}/wb_command -volume-math "(T1w / T2w) * (((ribbon > ($LeftGreyRibbonValue - 0.01)) * (ribbon < ($LeftGreyRibbonValue + 0.01))) + ((ribbon > ($RightGreyRibbonValue - 0.01)) * (ribbon < ($RightGreyRibbonValue + 0.01))))" T1wDividedByT2w_ribbon.nii.gz -var T1w $T1w -var T2w $T2w -var ribbon ${AtlasFolder}/Results/ribbon_only.nii.gz
# if($status) exit 1
# ${CARET7DIR}/wb_command -volume-palette T1wDividedByT2w_ribbon.nii.gz MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
# if($status) exit 1

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

#   ${CARET7DIR}/wb_command -metric-resample ${AtlasFolder}/${Subject}.${Hemisphere}.atlasroi.32k_fs_LR.shape.gii fsaverage/${Subject}.${Hemisphere}.sphere.164k_fs_${Hemisphere}.surf.gii fsaverage_LR${LowResMesh}k/${Subject}.${Hemisphere}.sphere.${LowResMesh}k_fs_LR.surf.gii BARYCENTRIC ${AtlasFolder}/${Subject}.${Hemisphere}.roi.${LowResMesh}K_fs_LR.shape.gii
#   if($status) exit 1

  ${CARET7DIR}/wb_command -volume-math "(ribbon > ($ribbon - 0.01)) * (ribbon < ($ribbon + 0.01))" temp_ribbon.nii.gz -var ribbon ${AtlasFolder}/Results/ribbon_only.nii.gz
  if($status) exit 1

  ${CARET7DIR}/wb_command -volume-to-surface-mapping $MyelinAligned ${AtlasFolder}/"$Subject"."$Hemisphere".midthickness.${LowResMesh}k_fs_LR.surf.gii ${AtlasFolder}/"$Subject"."$Hemisphere".MyelinMap.${LowResMesh}k_fs_LR.func.gii -ribbon-constrained ${AtlasFolder}/"$Subject"."$Hemisphere".white.${LowResMesh}k_fs_LR.surf.gii ${AtlasFolder}/"$Subject"."$Hemisphere".pial.${LowResMesh}k_fs_LR.surf.gii
  if($status) exit 1

  rm temp_ribbon.nii.gz
#
#   if(! -e ${AtlasFolder}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii) then
# 	cp fsaverage_LR${LowResMesh}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii ${AtlasFolder}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii
#   endif
#
#
#   ${CARET7DIR}/wb_command -metric-regression ${AtlasFolder}/"$Subject"."$Hemisphere".thickness.${LowResMesh}k_fs_LR.shape.gii ${AtlasFolder}/"$Subject"."$Hemisphere".corrThickness.${LowResMesh}k_fs_LR.shape.gii -roi ${AtlasFolder}/"$Subject"."$Hemisphere".roi.${LowResMesh}K_fs_LR.shape.gii -remove ${AtlasFolder}/"$Subject"."$Hemisphere".curvature.${LowResMesh}k_fs_LR.shape.gii
#   if($status) exit 1
#
  ${CARET7DIR}/wb_command -metric-smoothing ${AtlasFolder}/"$Subject"."$Hemisphere".midthickness.${LowResMesh}k_fs_LR.surf.gii ${AtlasFolder}/"$Subject"."$Hemisphere".MyelinMap.${LowResMesh}k_fs_LR.func.gii "$SurfaceSmoothingSigma" ${AtlasFolder}/"$Subject"."$Hemisphere".SmoothedMyelinMap.${LowResMesh}k_fs_LR.func.gii
  if($status) exit 1


end

popd
