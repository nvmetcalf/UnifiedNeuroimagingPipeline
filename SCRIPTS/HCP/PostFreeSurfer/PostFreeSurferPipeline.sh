#!/bin/bash
#set -e
# Requirements for this script
#  installed versions of: FSL5.0.1 or higher , FreeSurfer (version 5.2 or higher) ,
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR , PATH (for gradient_unwarp.py)

# make pipeline engine happy...
#if [ $# -eq 1 ] ; then
#    echo "Version unknown..."
#    exit 0
#fi

########################################## PIPELINE OVERVIEW ########################################## 

#TODO

########################################## OUTPUT DIRECTORIES ########################################## 

#TODO

########################################## SUPPORT FUNCTIONS ########################################## 


set StudyFolder="$1"
set Subject="$2"
set T1wFolder="$3"
set AtlasSpaceFolder="$4"
set NativeFolder="$5"
set FreeSurferFolder="$6"
set FreeSurferInput="$7"
set T1wImage="$8"
set T2wImage="$9"
set SurfaceAtlasDIR="${10}"
set HighResMesh="${11}"
set LowResMesh="${12}"
set AtlasTransform="${13}"
set InverseAtlasTransform="${14}"
set AtlasSpaceT1wImage="${15}"
set AtlasSpaceT2wImage="${16}"
set T1wImageBrainMask="${17}"
set FreeSurferLabels="${18}"
set GrayordinatesSpaceDIR="${19}"
set GrayordinatesResolution="${20}"
set SubcorticalGrayLabels="${21}"
# function for parsing options
# getopt1() {
    # sopt="$1"
    # shift 1
    # for fn in $@ ; do
	# if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
	    # echo $fn | sed "s/^${sopt}=//"
	    # return 0
	# fi
    # done
# }

# defaultopt() {
    # echo $1
# }

################################################## OPTION PARSING #####################################################

# Input Variables
# StudyFolder=`getopt1 "--path" $@`
# Subject=`getopt1 "--subject" $@`
# SurfaceAtlasDIR=`getopt1 "--surfatlasdir" $@`
# GrayordinatesSpaceDIR=`getopt1 "--grayordinatesdir" $@`
# GrayordinatesResolution=`getopt1 "--grayordinatesres" $@`
# HighResMesh=`getopt1 "--hiresmesh" $@`
# LowResMesh=`getopt1 "--lowresmesh" $@`
# SubcorticalGrayLabels=`getopt1 "--subcortgraylabels" $@`
# FreeSurferLabels=`getopt1 "--freesurferlabels" $@`
# ReferenceMyelinMaps=`getopt1 "--refmyelinmaps" $@`


#PipelineScripts = "/data/nil-bluearc/corbetta/Hacker/Process/HCP/PIPE/PostFreeSurfer/scripts"



PipelineScripts="/data/nil-bluearc/corbetta/Hacker/Process/HCP/PIPE/PostFreeSurfer/scripts"
FSOUT="/data/nil-bluearc/corbetta/Hacker/Surfaces/FS_Output"

#Naming Conventions
T1wImage="${Subject}_mpr1"
T1wFolder="atlas" #Location of T1w images
T2wFolder="atlas" #Location of T1w images
T2wImage="${Subject}_mpr1" 
AtlasSpaceFolder="atlas"
NativeFolder="Native"
FreeSurferFolder="$Subject"
FreeSurferInput="${Subject}_mpr1"
AtlasTransform="zero"
InverseAtlasTransform="zero"
AtlasSpaceT1wImage="${Subject}_mpr1"
AtlasSpaceT2wImage="${Subject}_mpr1"
T1wRestoreImage="${Subject}_mpr1"
T2wRestoreImage="${Subject}_mpr1"
OrginalT1wImage="${Subject}_mpr1"
OrginalT2wImage="${Subject}_mpr1"
T1wImageBrainMask="brainmask_fs"
InitialT1wTransform="acpc.mat"
dcT1wTransform="T1w_dc.nii.gz"
InitialT2wTransform="acpc.mat"
dcT2wTransform="T2w_reg_dc.nii.gz"
FinalT2wTransform="${Subject}/mri/transforms/T2wtoT1w.mat"
BiasField="BiasField_acpc_dc"
OutputT1wImage="T1w_acpc_dc"
OutputT1wImageRestore="T1w_acpc_dc_restore"
OutputT1wImageRestoreBrain="T1w_acpc_dc_restore_brain"
OutputMNIT1wImage="T1w"
OutputMNIT1wImageRestore="T1w_restore"
OutputMNIT1wImageRestoreBrain="T1w_restore_brain"
OutputT2wImage="T2w_acpc_dc"
OutputT2wImageRestore="T2w_acpc_dc_restore"
OutputT2wImageRestoreBrain="T2w_acpc_dc_restore_brain"
OutputMNIT2wImage="T2w"
OutputMNIT2wImageRestore="T2w_restore"
OutputMNIT2wImageRestoreBrain="T2w_restore_brain"
OutputOrigT1wToT1w="OrigT1w2T1w.nii.gz"
OutputOrigT1wToStandard="OrigT1w2standard.nii.gz" #File was OrigT2w2standard.nii.gz, regnerate and apply matrix
OutputOrigT2wToT1w="OrigT2w2T1w.nii.gz" #mv OrigT1w2T2w.nii.gz OrigT2w2T1w.nii.gz
OutputOrigT2wToStandard="OrigT2w2standard.nii.gz"
BiasFieldOutput="BiasField"
Jacobian="NonlinearRegJacobians.nii.gz"




T1wFolder="$StudyFolder"/"$Subject"/"$T1wFolder" 
T2wFolder="$StudyFolder"/"$Subject"/"$T1wFolder" 
AtlasSpaceFolder="$StudyFolder"/"$Subject"/"$AtlasSpaceFolder"
FreeSurferFolder="$FSOUT"/"$Subject"

echo FreeSurferFolder: $FreeSurferFolder
AtlasTransform="$AtlasSpaceFolder"/xfms/"$AtlasTransform"
InverseAtlasTransform="$AtlasSpaceFolder"/xfms/"$InverseAtlasTransform"

#Conversion of FreeSurfer Volumes and Surfaces to NIFTI and GIFTI and Create Caret Files and Registration
echo PipelineScripts: $PipelineScripts
echo "$PipelineScripts"/FreeSurfer2CaretConvertAndRegisterNonlinear.sh "$StudyFolder" "$Subject" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$FreeSurferFolder" "$FreeSurferInput" "$T1wRestoreImage" "$T2wRestoreImage" "$SurfaceAtlasDIR" "$HighResMesh" "$LowResMesh" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$AtlasSpaceT2wImage" "$T1wImageBrainMask" "$FreeSurferLabels" "$GrayordinatesSpaceDIR" "$GrayordinatesResolution" "$SubcorticalGrayLabels"

echo $Subject
echo $T1wFolder
"$PipelineScripts"/FreeSurfer2CaretConvertAndRegisterNonlinear.sh "$StudyFolder" "$Subject" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$FreeSurferFolder" "$FreeSurferInput" "$T1wRestoreImage" "$T2wRestoreImage" "$SurfaceAtlasDIR" "$HighResMesh" "$LowResMesh" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$AtlasSpaceT2wImage" "$T1wImageBrainMask" "$FreeSurferLabels" "$GrayordinatesSpaceDIR" "$GrayordinatesResolution" "$SubcorticalGrayLabels"

#Create FreeSurfer ribbon file at full resolution
#"$PipelineScripts"/CreateRibbon.sh "$StudyFolder" "$Subject" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$AtlasSpaceT1wImage" "$T1wRestoreImage" "$FreeSurferLabels"

##Myelin Mapping
#"$PipelineScripts"/CreateMyelinMaps.sh "$StudyFolder" "$Subject" "$AtlasSpaceFolder" "$NativeFolder" "$T1wFolder" "$HighResMesh" "$LowResMesh" "$T1wFolder"/"$OrginalT1wImage" "$T2wFolder"/"$OrginalT2wImage" "$T1wFolder"/"$T1wImageBrainMask" "$T1wFolder"/xfms/"$InitialT1wTransform" "$T1wFolder"/xfms/"$dcT1wTransform" "$T2wFolder"/xfms/"$InitialT2wTransform" "$T1wFolder"/xfms/"$dcT2wTransform" "$T1wFolder"/"$FinalT2wTransform" "$AtlasTransform" "$T1wFolder"/"$BiasField" "$T1wFolder"/"$OutputT1wImage" "$T1wFolder"/"$OutputT1wImageRestore" "$T1wFolder"/"$OutputT1wImageRestoreBrain" "$AtlasSpaceFolder"/"$OutputMNIT1wImage" "$AtlasSpaceFolder"/"$OutputMNIT1wImageRestore" "$AtlasSpaceFolder"/"$OutputMNIT1wImageRestoreBrain" "$T1wFolder"/"$OutputT2wImage" "$T1wFolder"/"$OutputT2wImageRestore" "$T1wFolder"/"$OutputT2wImageRestoreBrain" "$AtlasSpaceFolder"/"$OutputMNIT2wImage" "$AtlasSpaceFolder"/"$OutputMNIT2wImageRestore" "$AtlasSpaceFolder"/"$OutputMNIT2wImageRestoreBrain" "$T1wFolder"/xfms/"$OutputOrigT1wToT1w" "$T1wFolder"/xfms/"$OutputOrigT1wToStandard" "$T1wFolder"/xfms/"$OutputOrigT2wToT1w" "$T1wFolder"/xfms/"$OutputOrigT2wToStandard" "$AtlasSpaceFolder"/"$BiasFieldOutput" "$AtlasSpaceFolder"/"$T1wImageBrainMask" "$AtlasSpaceFolder"/xfms/"$Jacobian" "$ReferenceMyelinMaps" 



