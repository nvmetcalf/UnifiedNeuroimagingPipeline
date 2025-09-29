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

set Scan = (`$PP_SCRIPTS/Utilities/detect_pet_scan.csh "$FDG_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	##################################
	## Index the FDG
	##################################
	echo "Set FDG..."
	set FramesUsed = ()
	set GoodScans = ()
	foreach Image($Scan)
		set length = `fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'`

		if($length < 2) then
			decho "${Image} does not have enough frames. Ignoring."
			continue
		endif

		if(`grep NAC ${DICOM_Dir}/$Image:r:r".json"` != "") then
			decho "${Image} seems to be an attenuation correction image. Ignoring."
			continue
		endif

		set GoodScans =($GoodScans \"$Image\")
		set FramesUsed = ($FramesUsed "1200")
	end
	echo "set FDG = ($GoodScans)	#FDG timeseries" >> $output_params_file
	echo "set FDG_Target = (T1)" >> $output_params_file
	echo "set FDG_Duration = ($FramesUsed)" >> $output_params_file
	echo "set FDG_SumMethod = 2" >> $output_params_file
	echo "set FDG_Smoothing = 2" >> $output_params_file
	echo "set FDG_FrameAlign = 0"  >> $output_params_file
	echo "set FDG_RegMethod = corratio" >> $output_params_file
else
	echo "set FDG = ()	#FDG timeseries" >> $output_params_file
	echo "#set FDG_Target = (T1)" >> $output_params_file
	echo "#set FDG_Duration = (1200)" >> $output_params_file
	echo "#set FDG_SumMethod = 2" >> $output_params_file
	echo "#set FDG_Smoothing = 1" >> $output_params_file
	echo "#set FDG_FrameAlign = 0"  >> $output_params_file
	echo "#set FDG_RegMethod = corratio" >> $output_params_file
endif

#find the O2
set Scan = (`$PP_SCRIPTS/Utilities/detect_pet_scan.csh "$O2_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	##################################
	## Index the O2
	##################################
	echo "Set O2..."
	set FramesUsed = ()
	set GoodScans = ()
	foreach Image($Scan)
		set length = `fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'`

		if($length < 2) then
			decho "${Image} does not have enough frames. Ignoring."
			continue
		endif

		if(`grep NAC ${DICOM_Dir}/$Image:r:r".json"` != "") then
			decho "${Image} seems to be an attenuation correction image. Ignoring."
			continue
		endif

		set GoodScans =($GoodScans \"$Image\")
		set FramesUsed = ($FramesUsed "60")
	end
	echo "set O2 = ($GoodScans)	#O2 timeseries" >> $output_params_file
	echo "set O2_Target = (T1 FDG)" >> $output_params_file
	echo "set O2_Duration = ($FramesUsed)" >> $output_params_file
	echo "set O2_SumMethod = 1" >> $output_params_file
	echo "set O2_Smoothing = 2" >> $output_params_file
	echo "set O2_FrameAlign = 0"  >> $output_params_file
	echo "set O2_RegMethod = corratio" >> $output_params_file
else
	echo "set O2 = ()	#O2 timeseries" >> $output_params_file
	echo "#set O2_Target = (T1 FDG)" >> $output_params_file
	echo "#set O2_Duration = (60)" >> $output_params_file
	echo "#set O2_SumMethod = 1" >> $output_params_file
	echo "#set O2_Smoothing = 2" >> $output_params_file
	echo "#set O2_FrameAlign = 0"  >> $output_params_file
	echo "#set O2_RegMethod = corratio" >> $output_params_file
endif

#find the CO
set Scan = (`$PP_SCRIPTS/Utilities/detect_pet_scan.csh "$CO_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	##################################
	## Index the CO
	##################################
	echo "Set CO..."
	set FramesUsed = ()
	set GoodScans = ()
	foreach Image($Scan)
		set length = `fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'`

 		if($length < 1) then
 			decho "${Image} does not have enough frames. Ignoring."
 			continue
 		endif

		if(`grep NAC ${DICOM_Dir}/$Image:r:r".json"` != "") then
			decho "${Image} seems to be an attenuation correction image. Ignoring."
			continue
		endif

		set GoodScans =($GoodScans \"$Image\")
		set FramesUsed = ($FramesUsed "60")
	end
	echo "set CO = ($GoodScans)	#CO timeseries" >> $output_params_file
	echo "set CO_Target = (T1 FDG O2)" >> $output_params_file
	echo "set CO_Duration = ($FramesUsed)" >> $output_params_file
	echo "set CO_SumMethod = 5" >> $output_params_file
	echo "set CO_Smoothing = 2" >> $output_params_file
	echo "set CO_FrameAlign = 0"  >> $output_params_file
	echo "set CO_RegMethod = corratio" >> $output_params_file
else
	echo "set CO = ()	#CO timeseries" >> $output_params_file
	echo "#set CO_Target = (T1 FDG)" >> $output_params_file
	echo "#set CO_Duration = (60)" >> $output_params_file
	echo "#set CO_SumMethod = 5" >> $output_params_file
	echo "#set CO_Smoothing = 2" >> $output_params_file
	echo "#set CO_FrameAlign = 0"  >> $output_params_file
	echo "#set CO_RegMethod = corratio" >> $output_params_file
endif

#find the H2O
set Scan = (`$PP_SCRIPTS/Utilities/detect_pet_scan.csh "$H2O_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	##################################
	## Index the H2O
	##################################
	echo "Set H2O..."
	set FramesUsed = ()
	set GoodScans = ()
	foreach Image($Scan)
		set length = `fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'`

		if($length < 2) then
			decho "${Image} does not have enough frames. Ignoring."
			continue
		endif

		if(`grep NAC ${DICOM_Dir}/$Image:r:r".json"` != "") then
			decho "${Image} seems to be an attenuation correction image. Ignoring."
			continue
		endif

		set GoodScans =($GoodScans \"$Image\")
		set FramesUsed = ($FramesUsed "60")
	end
	echo "set H2O = ($GoodScans)	#H2O timeseries" >> $output_params_file
	echo "set H2O_Target = (T1 FDG)" >> $output_params_file
	echo "set H2O_Duration = ($FramesUsed)" >> $output_params_file
	echo "set H2O_SumMethod = 1" >> $output_params_file
	echo "set H2O_Smoothing = 2" >> $output_params_file
	echo "set H2O_FrameAlign = 0"  >> $output_params_file
	echo "set H2O_RegMethod = corratio" >> $output_params_file
else
	echo "set H2O = ()	#H2O timeseries" >> $output_params_file
	echo "#set H2O_Target = (T1 FDG)" >> $output_params_file
	echo "#set H2O_Duration = (60)" >> $output_params_file
	echo "#set H2O_SumMethod = 1" >> $output_params_file
	echo "#set H2O_Smoothing = 2" >> $output_params_file
	echo "#set H2O_FrameAlign = 0"  >> $output_params_file
	echo "#set H2O_RegMethod = corratio" >> $output_params_file
endif

#find the PIB
set Scan = (`$PP_SCRIPTS/Utilities/detect_pet_scan.csh "$PIB_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	##################################
	## Index the PIB
	##################################
	echo "Set PIB..."
	set FramesUsed = ()
	set GoodScans = ()
	foreach Image($Scan)
		set length = `fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'`

		if($length < 2) then
			decho "${Image} does not have enough frames. Ignoring."
			continue
		endif

		if(`grep NAC ${DICOM_Dir}/$Image:r:r".json"` != "") then
			decho "${Image} seems to be an attenuation correction image. Ignoring."
			continue
		endif

		set GoodScans =($GoodScans \"$Image\")
		set FramesUsed = ($FramesUsed "2400-3600")
	end
	echo "set PIB = ($GoodScans)	#PIB timeseries" >> $output_params_file
	echo "set PIB_Target = (T1)" >> $output_params_file
	echo "set PIB_Duration = ($FramesUsed)" >> $output_params_file
	echo "set PIB_SumMethod = 3" >> $output_params_file
	echo "set PIB_Smoothing = 2" >> $output_params_file
	echo "set PIB_FrameAlign = 0"  >> $output_params_file
	echo "set PIB_RegMethod = corratio" >> $output_params_file
else
	echo "set PIB = ()	#PIB timeseries" >> $output_params_file
	echo "#set PIB_Target = (T1)" >> $output_params_file
	echo "#set PIB_Duration = (2400-3600)" >> $output_params_file
	echo "#set PIB_SumMethod = 3" >> $output_params_file
	echo "#set PIB_Smoothing = 2" >> $output_params_file
	echo "#set PIB_FrameAlign = 0"  >> $output_params_file
	echo "#set PIB_RegMethod = corratio" >> $output_params_file
endif

#find the TAU
set Scan = (`$PP_SCRIPTS/Utilities/detect_pet_scan.csh "$TAU_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	##################################
	## Index the TAU
	##################################
	echo "Set TAU..."
	set FramesUsed = ()
	set GoodScans = ()
	foreach Image($Scan)
		set length = `fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'`

		if($length < 2) then
			decho "${Image} does not have enough frames. Ignoring."
			continue
		endif

		if(`grep NAC ${DICOM_Dir}/$Image:r:r".json"` != "") then
			decho "${Image} seems to be an attenuation correction image. Ignoring."
			continue
		endif

		set GoodScans =($GoodScans \"$Image\")
		set FramesUsed = ($FramesUsed "4800-6000")
	end
	echo "set TAU = ($GoodScans)	#TAU timeseries" >> $output_params_file
	echo "set TAU_Target = (T1)" >> $output_params_file
	echo "set TAU_Duration = ($FramesUsed)" >> $output_params_file
	echo "set TAU_SumMethod = 3" >> $output_params_file
	echo "set TAU_Smoothing = 2" >> $output_params_file
	echo "set TAU_FrameAlign = 0"  >> $output_params_file
	echo "set TAU_RegMethod = corratio" >> $output_params_file
else
	echo "set TAU = ()	#TAU timeseries" >> $output_params_file
	echo "#set TAU_Target = (T1)" >> $output_params_file
	echo "#set TAU_Duration = (4800-6000)" >> $output_params_file
	echo "#set TAU_SumMethod = 3" >> $output_params_file
	echo "#set TAU_Smoothing = 2" >> $output_params_file
	echo "#set TAU_FrameAlign = 0"  >> $output_params_file
	echo "#set TAU_RegMethod = corratio" >> $output_params_file
endif

#find the FBX
set Scan = (`$PP_SCRIPTS/Utilities/detect_pet_scan.csh "$FBX_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	##################################
	## Index the FBX
	##################################
	echo "Set FBX..."
	set FramesUsed = ()
	set GoodScans = ()
	foreach Image($Scan)
		set length = `fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'`

		if($length < 2) then
			decho "${Image} does not have enough frames. Ignoring."
			continue
		endif

		if(`grep NAC ${DICOM_Dir}/$Image:r:r".json"` != "") then
			decho "${Image} seems to be an attenuation correction image. Ignoring."
			continue
		endif

		set GoodScans =($GoodScans \"$Image\")
		set FramesUsed = ($FramesUsed "4800-6000")
	end
	echo "set FBX = ($GoodScans)	#FBX timeseries" >> $output_params_file
	echo "set FBX_Target = (T1)" >> $output_params_file
	echo "set FBX_Duration = ($FramesUsed)" >> $output_params_file
	echo "set FBX_SumMethod = 3" >> $output_params_file
	echo "set FBX_Smoothing = 2" >> $output_params_file
	echo "set FBX_FrameAlign = 0"  >> $output_params_file
	echo "set FBX_RegMethod = corratio" >> $output_params_file
else
	echo "set FBX = ()	#FBX timeseries" >> $output_params_file
	echo "#set FBX_Target = (T1)" >> $output_params_file
	echo "#set FBX_Duration = (4800-6000)" >> $output_params_file
	echo "#set FBX_SumMethod = 3" >> $output_params_file
	echo "#set FBX_Smoothing = 2" >> $output_params_file
	echo "#set FBX_FrameAlign = 0"  >> $output_params_file
	echo "#set FBX_RegMethod = corratio" >> $output_params_file
endif
