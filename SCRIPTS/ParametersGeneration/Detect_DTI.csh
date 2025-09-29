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

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$DTI_List" "$DTI_Exclude_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	echo "Set DTI..."
	set GoodScans = ()

	set DTI_dwell = ()
	set DTI_ped = ()
	set DTI_TE = ()

	foreach Image($Scan)

		set DTI_json = ${DICOM_Dir}/$Image:r:r".json"

		if(! -e $DTI_json) then
			decho "Could not find a json to go with $Image. BIDS conversion must have failed or been done improperly."
			exit 1
		endif

		if(`grep ORIGINAL $DTI_json` == "") then
			decho "${Image} is not an original series. Skipping..."
			continue
		endif

		if(! -e $DTI_json:r".bval") then
			decho "${Image} does not have a bval file. Skipping..."
			continue
		endif

		if(! -e $DTI_json:r".bvec") then
			decho "${Image} does not have a bvec file. Skipping..."
			continue
		endif

		set GoodScans = ($GoodScans \"$Image\")

		set dwell = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DTI_json} EffectiveEchoSpacing`

		set DTI_dwell = ($DTI_dwell `printf "%.8f" $dwell`)
		set DTI_TE = ($DTI_TE `$PP_SCRIPTS/Utilities/GetJSON_Value ${DTI_json} EchoTime | awk '{if($1 < 1) print($1*1000); else print($1);}'`)
		set ped = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DTI_json} PhaseEncodingDirection`

		set DTI_ped = ($DTI_ped `$PP_SCRIPTS/Utilities/AcqDir_to_PhDir $ped`)

	end

	#DTI stuff

	echo "set DTI = ("${GoodScans}")		# DTI Images" >> $output_params_file
	echo "set DTI_TE = ("$DTI_TE")	#TE of DTI images " >> $output_params_file
	echo "DTI: "${GoodScans}
else
	echo "Could not find DTI..."
	echo "Could not find DTI."
	echo "#set DTI = ()		# DTI Images" >> $output_params_file
	echo "#set DTI_TE = ()	#TE of DTI images" >> $output_params_file
endif

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$DTI_FM_List" ${DICOM_Dir}`)
echo $PP_SCRIPTS/Utilities/detect_scan.csh "$DTI_FM_List" ${DICOM_Dir}

if($#Scan > 1) then
	echo "Set DTI Field Mapping..."
	set FirstEcho = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DTI_json} EchoTime`
	set SecondEcho = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DTI_json} EchoTime`
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

	if($?DTI_dwell) then
		echo "set DTI_dwell = ("$DTI_dwell")	#total readout time of the DTI sequences." >> $output_params_file
		echo "set DTI_ped = ("$DTI_ped")		#phase encoding direction of the DTI images in order of detection" >> $output_params_file

		echo "set DTI_fm = ("${Scan}")		# DTI field mapping Images" >> $output_params_file
		echo "set DTI_FieldMapping = "\"${fm_method}\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps;  synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
		echo "set DTI_delta = ${delta}	#time between echos for the field map magnitude images" >> $output_params_file
		echo "set DTI_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
		echo "set DTI_CostFunction = corratio	#cost function to use for registering DTI to target. Used by flirt." >> $output_params_file
		echo "set DTI_FinalResolution = 1	#set the final isotropic resolution of the DTI data. Set to 0 to keep in native target space." >> $output_params_file

	endif

else if($#Scan == 0 && $?DTI_dwell && $?DTI_ped) then
	echo "Set DTI Field Mapping to synth..."

	if($?DTI_dwell) then
		echo "set DTI_dwell = ("$DTI_dwell")	#total readout time of the DTI sequences." >> $output_params_file
		echo "set DTI_ped = ("$DTI_ped")		#phase encoding direction of the DTI images in order of detection" >> $output_params_file

		echo "set DTI_fm = ("${Scan}")		# DTI field mapping Images" >> $output_params_file
		echo "set DTI_FieldMapping = "\"6dof\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
		echo "set DTI_delta = 2.46	#time between echos for the field map magnitude images" >> $output_params_file
		echo "set DTI_Reg_Target = T2	#target image to register DTI directions to." >> $output_params_file
		echo "set DTI_CostFunction = corratio	#cost function to use for registering DTI to target. Used by flirt." >> $output_params_file
		echo "set DTI_FinalResolution = 1	#set the final isotropic resolution of the DTI data. Set to 0 to keep in native target space." >> $output_params_file

	endif
else
	echo "#set DTI_dwell = ()	#total readout time of the DTI sequences." >> $output_params_file
	echo "#set DTI_ped = ()		#phase encoding direction of the DTI images in order of detection" >> $output_params_file

	echo "#set DTI_fm = ()		# field mapping Images" >> $output_params_file
	echo "#set DTI_FieldMapping = "\"6dof\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
	echo "#set DTI_delta = 0	#time between echos for the field map magnitude images" >> $output_params_file
	echo "#set DTI_Reg_Target = T2	#target image to register DTI directions to." >> $output_params_file
	echo "#set DTI_CostFunction = corratio	#cost function to use for registering DTI to target. Used by flirt." >> $output_params_file
	echo "#set DTI_FinalResolution = 1	#set the final isotropic resolution of the DTI data. Set to 0 to keep in native target space." >> $output_params_file

endif
