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

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$ASL_List" "$ASL_Exclude_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	echo "Set ASL..."
	set GoodScans = ()

	foreach Image($Scan)
		#have to pull off the first file found in two steps... cause ls is dumb sometimes
		if($Image:e == "gz") set ASL_json = ${DICOM_Dir}/$Image:r:r".json"
		if($Image:e == "nii") set ASL_json = ${DICOM_Dir}/$Image:r".json"

		if(! -e $ASL_json) then
			decho "Could not find a json to go with $Image. BIDS conversion must have failed or been done improperly."
			exit 1
		endif

		if(`grep ORIGINAL $ASL_json` == "") then
			decho "${Image} is not an original series. Skipping..."
			continue
		endif

		if(`fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'` <= 4) then
			decho "${Image} does not have enough frames. Ignoring."
			continue
		endif

		#ASL stuff
		set GoodScans = ($GoodScans \"$Image\")
	end

	set ASL_dwell = ()
	set ASL_TE = ()
	set ASL_PLD = ()
	set ASL_TI1 = ()
	set ASL_TR = ()
	set ASL_PED = ()
	set ASL_RPTS = ()
	set ASL_LC_CL = 1

	#detect parameters for each scan
	foreach Image($GoodScans)

		set Image = `echo $Image | sed 's/\"//g'`

		if($Image:e == "gz") set ASL_json = ${DICOM_Dir}/$Image:r:r".json"
		if($Image:e == "nii") set ASL_json = ${DICOM_Dir}/$Image:r".json"

		set ASL_TE = ($ASL_TE `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json EchoTime | awk '{if($1 < 1) print($1*1000); else print($1);}'`)

		set ASL_dwell_time = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json EffectiveEchoSpacing`

		#check for DwellTime
		if($#ASL_dwell_time == 0) then
			set ASL_dwell_time = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json DwellTime | awk '{printf("%.14f",$1)}'`
		endif

		if($#ASL_dwell_time == 0) then

			#try to compute it
			set bandwidth = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json PixelBandwidth`
			set matrix = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json ReconMatrixPE`
			set factor = 1
			set num = `echo $bandwidth $matrix $factor | awk '{printf("%s",((1/($1 * $2))/$3) * 1000)}'`

			if($#num > 0) then
				set ASL_dwell_time = (`printf "%.14f" $num`)
			endif
		endif

		if($#ASL_dwell_time == 0) then
			set ASL_dwell_time = "-"
		endif

		set ASL_dwell = ($ASL_dwell `printf "%.8f" $ASL_dwell_time`)

		set temp = (`$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json PostLabelDelay`)
		if( $#temp > 0) then
			set temp =  (` $PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json PostLabelDelay | awk '{if($1 > 10) print($1*0.001); else print($1);}'`)
			goto HAS_PLD
		endif

		set temp = (`$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json PostLabelingDelay`)
		if( $#temp > 0) then
			set temp =  (` $PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json PostLabelingDelay | awk '{if($1 > 10) print($1*0.001); else print($1);}'`)
			goto HAS_PLD
		endif

		set temp =  (`$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json T1`)
		if( $#temp > 0) then
			set temp =  (`$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json T1`)
			goto HAS_PLD
		endif

		set temp = (`$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json InversionTime2`)
		if( $#temp > 0) then
			set temp = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json InversionTime2 | awk '{if($1 > 10) print($1*0.001); else print($1);}'`
			goto HAS_PLD
		endif

		if($#temp == 0) then
			decho "WARNING: Unable to determine PLD of ASL Sequence $Image ..."
			set temp = "-"
		endif

		HAS_PLD:

		set ASL_PLD = ($ASL_PLD $temp)

		set temp = (`$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json InversionTime1`)
		if( $#temp > 0) then
			set ASL_TI1 = ($ASL_TI1  `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json InversionTime1 | awk '{if($1 > 10) print($1*0.001); else print($1);}'`)
		else
			set ASL_TI1 = ($ASL_TI1 0)
		endif

		set temp =( `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json RepetitionTime`)
		if( $#temp > 0) then
			set ASL_TR = ($ASL_TR  `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json RepetitionTime | awk '{if($1 > 10) print($1*0.001); else print($1);}'`)
		else
			set ASL_TR = ($ASL_TR  0)
		endif

		set curr_scan = `echo $Scan | sed 's/\"//g'`

		set PED = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json PhaseEncodingDirection`

		if($#PED == 0) then
			set PED = `$PP_SCRIPTS/Utilities/GetJSON_Value $ASL_json PhaseEncodingAxis`
		endif

		set ASL_PED = ($ASL_PED `$PP_SCRIPTS/Utilities/AcqDir_to_PhDir $PED`)

		set ASL_RPTS = ($ASL_RPTS `fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{printf("%i",($2 - 1)/2);}'`)
	end

	echo "set ASL = ("${GoodScans}")		# ASL Images" >> $output_params_file
	echo "ASL: "${GoodScans}
	echo "set ASL_TE = ($ASL_TE)	#TE of the ASL sequence in milliseconds." >> $output_params_file
	echo "set ASL_PLD = ($ASL_PLD)	#PostLabelingDelay (pcASL) or TI2 (pASL)" >> $output_params_file
	echo "set ASL_RPTS = ($ASL_RPTS)	#number of repeats of the pairs. Should be more than 1 for each run." >> $output_params_file
	echo "set ASL_LC_CL = $ASL_LC_CL	#the order of the images in the pairs. 0 = Label -> Control, 1 = Control -> Label." >> $output_params_file
	echo "set ASL_TI1 = ($ASL_TI1)	#TI1 (pASL). 0 if the sequence is pcASL" >> $output_params_file
	echo "set ASL_TR = ($ASL_TR)	#TR of the sequence." >> $output_params_file

else
	echo "Could not find ASL..."
	echo "Could not find ASL."
	echo "#set ASL = ()		# ASL Images" >> $output_params_file
	echo "#set ASL_PLD = ()	#PostLabelingDelay (pcASL) or TI2 (pASL)" >> $output_params_file
	echo "#set ASL_TI1 = ()	#TI1 (pASL). 0 if the sequence is pcASL" >> $output_params_file
	echo "#set ASL_TR = ()	#TR of the sequence." >> $output_params_file
endif

#detect the field mapping parameters

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$ASL_FM_List" ${DICOM_Dir}`)

if($#Scan > 1) then
	echo "Set ASL Field Mapping..."
	set FirstEcho = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$Scan[1]:r:r".json" EchoTime`
	set SecondEcho = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$Scan[2]:r:r".json" EchoTime`
	set delta = `echo $FirstEcho $SecondEcho | awk '{print(sqrt(($2-$1)^2)*1000)}'`

	set fm_type = `echo $Scan[1] | tr "[a-z]" "[A-Z]"`

	if(`echo $fm_type | grep GRE` != "") then
		set fm_method = "gre_6dof"
	else if(`echo $fm_type | grep SPIN` != "") then
		set fm_method = "appa_6dof"
	else
		set fm_method = "6dof"
	endif
	echo "Setting field mapping method to: " $fm_method

	if($?ASL_dwell && $?ASL_PED) then
		echo "set ASL_dwell = ("${ASL_dwell}")	#1/( (0018,0095) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
		echo "set ASL_ped	= ($ASL_PED)" >> $output_params_file
	else
		echo "set ASL_dwell = 0	#1/( (0019,1028) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
		echo "set ASL_ped		= -y" >> $output_params_file
	endif

	echo "set ASL_fm = ("${Scan}")		# ASL field mapping Images" >> $output_params_file
	echo "set ASL_FieldMapping = "\"${fm_method}\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
	echo "set ASL_delta = ${delta}	#time between echos for the field map magnitude images" >> $output_params_file
	echo "set ASL_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
	echo "set ASL_CostFunction = corratio	#Cost function to use to register ASL to target. flirt uses this.." >> $output_params_file
	echo "set ASL_FinalResolution = 2	#set the final isotropic resolution of the ASL data. Set to 0 to keep in native target space." >> $output_params_file

else if($#Scan == 0 && $?ASL_dwell && $?ASL_PED) then
	echo "Set ASL Field Mapping to synth..."

	if($?ASL_dwell && $?ASL_PED) then
		echo "set ASL_dwell = ("${ASL_dwell}")	#1/( (0018,0095) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
		echo "set ASL_ped	= ($ASL_PED)" >> $output_params_file
	else
		echo "set ASL_dwell = 0	#1/( (0019,1028) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
		echo "set ASL_ped		= -y" >> $output_params_file
	endif

	echo "set ASL_fm = ("${Scan}")		# ASL field mapping Images" >> $output_params_file
	echo "set ASL_FieldMapping = "\"6dof\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
	echo "set ASL_delta = 2.46	#time between echos for the field map magnitude images" >> $output_params_file
	echo "set ASL_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
	echo "set ASL_CostFunction = corratio	#Cost function to use to register ASL to target. flirt uses this.." >> $output_params_file
	echo "set ASL_FinalResolution = 2	#set the final isotropic resolution of the ASL data. Set to 0 to keep in native target space." >> $output_params_file

else
	echo "#set ASL_dwell = 0	#1/( (0019,1028) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
	echo "#set ASL_ped		= -y" >> $output_params_file
	echo "#set ASL_fm = ()		# ASL field mapping Images" >> $output_params_file
	echo "#set ASL_FieldMapping = "\"6dof\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
	echo "#set ASL_delta = 0	#time between echos for the field map magnitude images" >> $output_params_file
	echo "#set ASL_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
	echo "#set ASL_CostFunction = corratio	#Cost function to use to register ASL to target. flirt uses this.." >> $output_params_file
	echo "#set ASL_FinalResolution = 2	#set the final isotropic resolution of the ASL data. Set to 0 to keep in native target space." >> $output_params_file
endif
