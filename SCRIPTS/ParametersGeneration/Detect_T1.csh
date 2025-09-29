#!/bin/csh

set output_params_file = $1

if(! -e $output_params_file || $#argv < 1) then
	echo "$output_params_file file cannot be found or wasn't specified."
	exit 1
endif

#load the configuration file
if(-e ${PP_SCRIPTS}/Config/P1.cfg) then
	source ${PP_SCRIPTS}/Config/P1.cfg
else
	echo "Cannot open P1 configuration. Ensure your login files are setup correctly."
	exit 1
endif

if(! -e ../../Study.cfg) then
	echo "Could not find a Study.cfg for the current study."
	exit 1
endif

if(! $?DICOM_Dir) then
	set DICOM_Dir = dicom
endif

##################################
## Find the T1
##################################
set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$T1w_List" "$T1w_Exclude_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	set image_set = ()
	foreach Image($Scan)
		set image_set = ($image_set \"$Image\")
	end
	echo "set T1 = ($image_set)		# hi-res MPRAGE/T1. Multiple are registered and averaged to the first entry." >> $output_params_file
	echo "T1: "${Scan}
	echo "Set T1..."
else
	echo "Could not find a T1..."
	echo "#set T1 = ()		# hi-res MPRAGE/T1. Multiple are registered and averaged to the first entry" >> $output_params_file
endif
