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

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$SWI_List" "$SWI_Exclude_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	set image_set = ()
	foreach Image($Scan)
		set image_set = ($image_set \"$Image\")
	end

	echo "set SWI = ($image_set)		# SWI. Multiple are registered and averaged to the first entry" >> $output_params_file
	echo "set SWI_Target = T1		# Target modality to register SWI to." >> $output_params_file
	echo "set SWI_CostFunction = mutualinfo		# Cost function to use when registering SWI to target. Used by flirt." >> $output_params_file
	echo "SWI: "${Scan}
	echo "Set SWI..."
else
	echo "Could not find SWI..."
	echo "#set SWI = ()		# SWI. Multiple are registered and averaged to the first entry" >> $output_params_file
	echo "#set SWI_Target = T1		# Target modality to register SWI to." >> $output_params_file
	echo "#set SWI_CostFunction = mutualinfo		# Cost function to use when registering SWI to target. Used by flirt." >> $output_params_file
endif
