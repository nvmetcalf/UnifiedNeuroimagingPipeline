#!/bin/csh

source $1 
source $2

echo "Running file cleanup..."

#Clean up folders of intermediate files

rm -f ${patid}_dicom_list.txt

#BOLDS
rm -rf ${ScratchFolder}/${patid}/BOLD_temp
rm -rf ${ScratchFolder}/${patid}/ASL_temp
rm -rf ${ScratchFolder}/${patid}/DTI_temp
rm -f ${ScratchFolder}/${patid}/${patid}*.*
rm -f ${ScratchFolder}/${patid}/*.lst

rm -f Functional/Surface/${patid}_fcmri_bpss.ctx.dtseries.nii
rm -f Functional/Surface/${patid}_fcmri_sr.ctx.dtseries.nii
