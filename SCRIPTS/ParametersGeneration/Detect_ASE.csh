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

source $output_params_file

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$ASE_List" "$ASE_Exclude_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	echo "Set ASE..."

	set GoodScans = ()
	set ASE_dwell = ()
	set ASE_ped = ()
	set ASE_TE = ()

	foreach Image($Scan)

		set ASE_json = ${DICOM_Dir}/$Image:r:r".json"

		if(! -e $ASE_json) then
			decho "Could not find a json to go with $Image. BIDS conversion must have failed or been done improperly."
			exit 1
		endif

		if(`grep ORIGINAL $ASE_json` == "") then
			decho "${Image} is not an original series. Skipping..."
			continue
		endif

		set GoodScans = ($GoodScans \"$Image\")
		set dwell = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASE_json EffectiveEchoSpacing`
		set ASE_dwell = ($ASE_dwell `printf "%.8f" $dwell`)

		set ASE_TE = ($ASE_TE `$PP_SCRIPTS/Utilities/GetJSON_Value $ASE_json EchoTime | awk '{if($1 < 1) print($1*1000); else print($1);}'`)
		set ped = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASE_json PhaseEncodingDirection`

		set ASE_ped = ($ASE_ped `$PP_SCRIPTS/Utilities/AcqDir_to_PhDir $ped`)

	end
endif

#write out the valid runs
if($?GoodScans) then
	echo "set ASE = ("${GoodScans}")		# ASE Images" >> $output_params_file
	echo "set ASE_TE = ("$ASE_TE")	#TE of ASE images " >> $output_params_file
	if(`$PP_SCRIPTS/Utilities/GetJSON_Value $ASE_json PatientSex` == "M") then
		set hct = 42
	else
		set hct = 40
	endif

	echo "set ASE_HCT = ${hct} 	#Hemocrit from blood analysis. Rule of thumb if no blood samples exist, 42 = male, 40 = female" >> $output_params_file
	echo "set ASE_HGB = 0 	#hemoglobin (hgb) from blood analysis. Needed for computing CMRO2" >> $output_params_file
	echo "set ASE_SaO2 = 98	#percent oxygen saturation. Needed for computing CMRO2" >> $output_params_file

	echo "ASE: ${GoodScans}"
else
	echo "Could not find ASE..."
	echo "#set ASE = ()		# ASE Images" >> $output_params_file
	echo "#set ASE_TE = ()	#TE of ASE images" >> $output_params_file
	echo "#set ASE_HCT = 0 	#Hemocrit from blood analysis. Rule of thumb if no blood samples exist, 42 = male, 40 = female" >> $output_params_file
	echo "#set ASE_HGB = 0 	#hemoglobin (hgb) from blood analysis. Needed for computing CMRO2" >> $output_params_file
	echo "#set ASE_SaO2 = 98	#percent oxygen saturation. Needed for computing CMRO2" >> $output_params_file
	echo "#set ASE_CostFunction = mutualinfo	#Cost function to use for registering ASE to target. Used by flirt." >> $output_params_file
endif

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$ASE_FM_List" ${DICOM_Dir}`)
echo $PP_SCRIPTS/Utilities/detect_scan.csh "$ASE_FM_List" ${DICOM_Dir}

if($#Scan > 1) then
	echo "Set ASE Field Mapping..."
	set FirstEcho = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$Scan[1]:r:r".json" EchoTime\"`
	set SecondEcho = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$Scan[2]:r:r".json" EchoTime\"`
	set delta = `echo $FirstEcho $SecondEcho | awk '{print(sqrt(($2-$1)^2)*1000)}'`

	set fm_type = `echo $Scan[1] | tr "[a-z]" "[A-Z]"`

	if(`echo $fm_type | grep GRE` != "") then
		set fm_method = "gre_6dof"
	else if(`echo $fm_type | grep SPIN` != "" || `echo $fm_type | grep SE` != "") then
		set fm_method = "appa_6dof"
	else
		set fm_method = "6dof"
	endif

	echo "Setting field mapping method to: " $fm_method

	if($?ASE_dwell) then
		echo "set ASE_dwell = ("$ASE_dwell")	#total readout time of the ASE sequences." >> $output_params_file
		echo "set ASE_ped = ("$ASE_ped")		#phase encoding direction of the ASE images in order of detection" >> $output_params_file

		echo "set ASE_fm = ("${Scan}")		# ASE field mapping Images" >> $output_params_file
		echo "set ASE_FieldMapping = "\"${fm_method}\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration; id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
		echo "set ASE_delta = ${delta}	#time between echos for the field map magnitude images" >> $output_params_file

		if($?T2) then
			echo "set ASE_Reg_Target = T2	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
		else
			echo "set ASE_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
		endif
		echo "set ASE_CostFunction = mutualinfo	#Cost function to use for registering ASE to target. Used by flirt." >> $output_params_file
		echo "set ASE_FinalResolution = 2	#set the final isotropic resolution of the ASE data. Set to 0 to keep in native target space." >> $output_params_file
	endif

else if($#Scan == 0 && $?ASE_dwell && $?ASE_ped) then
	echo "Set ASE Field Mapping to synth..."

	if($?ASE_dwell) then
		echo "set ASE_dwell = ("$ASE_dwell")	#total readout time of the ASE sequences." >> $output_params_file
		echo "set ASE_ped = ("$ASE_ped")		#phase encoding direction of the ASE images in order of detection" >> $output_params_file

		echo "set ASE_fm = ("${Scan}")		# ASE field mapping Images" >> $output_params_file
		echo "set ASE_FieldMapping = "\"6dof\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
		echo "set ASE_delta = 2.46	#time between echos for the field map magnitude images" >> $output_params_file
		echo "set ASE_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
		echo "set ASE_CostFunction = mutualinfo	#Cost function to use for registering ASE to target. Used by flirt." >> $output_params_file
		echo "set ASE_FinalResolution = 2	#set the final isotropic resolution of the ASE data. Set to 0 to keep in native target space." >> $output_params_file
	endif
else
	echo "#set ASE_dwell = ()	#total readout time of the ASE sequences." >> $output_params_file
	echo "#set ASE_ped = ()		#phase encoding direction of the ASE images in order of detection" >> $output_params_file

	echo "#set ASE_fm = ()		# field mapping Images" >> $output_params_file
	echo "#set ASE_FieldMapping = "\"6dof\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
	echo "#set ASE_delta = 0	#time between echos for the field map magnitude images" >> $output_params_file
	echo "#set ASE_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
	echo "#set ASE_CostFunction = mutualinfo	#Cost function to use for registering ASE to target. Used by flirt." >> $output_params_file
	echo "#set ASE_FinalResolution = 2	#set the final isotropic resolution of the ASE data. Set to 0 to keep in native target space." >> $output_params_file
endif
