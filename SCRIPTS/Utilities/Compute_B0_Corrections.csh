#!/bin/csh
set echo
if(! -e $1) then
	echo "SCRIPT: $0 : 00000 : $1 does not exist"
	exit 1
endif

set InputImage = $1

if($InputImage:e == "gz") then
	set InputImage = $InputImage:r
endif

if($InputImage:e == "nii") then
	set InputImage = $InputImage:r:r
endif

echo "Bias correcting: $InputImage"

#make a run average without the hyperintense frames
fslmaths $InputImage -Tmean ${InputImage}_avg
if($status) then
	echo "SCRIPT: $0 : 00001 : could not create average"
	exit 1
endif

bet ${InputImage}_avg ${InputImage}_avg_brain -f 0.3
if($status) then
	echo "SCRIPT: $0 : 00002 : could not compute brain extraction"
	exit 1
endif

fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -B -o ${InputImage}_avg_brain ${InputImage}_avg_brain
if($status) then
	echo "SCRIPT: $0 : 00003 : could not compute initial B0 field"
	exit 1
endif

niftigz_4dfp -4 ${InputImage}_avg_brain_restore ${InputImage}_avg_brain_restore
if($status) then
	echo "SCRIPT: $0 : 00004 : could not convert restore from nifti to 4dfp"
	exit 1
endif

niftigz_4dfp -4 ${InputImage}_avg ${InputImage}_avg
if($status) then
	echo "SCRIPT: $0 : 00005 : could not convert brain from nifti to 4dfp"
	exit 1
endif

extend_fast_4dfp -G ${InputImage}_avg ${InputImage}_avg_brain_restore ${InputImage}_avg_BF
if($status) then
	echo "SCRIPT: $0 : 00006 : could not extend B0 bias field"
	exit 1
endif

niftigz_4dfp -n ${InputImage}_avg_BF ${InputImage}_avg_BF
if($status) then
	echo "SCRIPT: $0 : 00007 : could not convert extended bias field to nifti"
	exit 1
endif

#imgopr_4dfp -pbold${Run}_upck_faln_dbnd_BC bold${Run}_upck_faln_dbnd bold${Run}_upck_faln_dbnd_avg_BF
fslmaths $InputImage -mul ${InputImage}_avg_BF $InputImage
if($status) then
	echo "SCRIPT: $0 : 00008 : could not apply extended bias field"
	exit 1
endif

rm ${InputImage}_avg*.4dfp.*
