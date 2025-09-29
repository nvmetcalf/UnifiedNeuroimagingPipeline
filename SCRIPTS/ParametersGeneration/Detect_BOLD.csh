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

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$BOLD_List" "$BOLD_Exclude_List" ${DICOM_Dir}`)

##################################
## Index the BOLD's
##################################
echo "Set BOLD..."

set GoodScans = ()
foreach Image($Scan)
	if($Image:e == "gz") set BOLD_json = ${DICOM_Dir}/$Image:r:r".json"
	if($Image:e == "nii") set BOLD_json = ${DICOM_Dir}/$Image:r".json"

	if(! -e $BOLD_json) then
		decho "Could not find a json to go with $Image. BIDS conversion must have failed or been done improperly."
		continue
	endif

	if(`grep ORIGINAL $BOLD_json` == "") then
		decho "${Image} is not an original series. Skipping..."
		continue
	endif

	if(`fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'` <= 10) then
		decho "${Image} does not have enough frames. Ignoring."
		continue
	endif

	#check if the scan is a nordic component

	set IsNordic = 0
	@ i = 1
	while($i <= $#NORDIC_BOLD_List)
		echo $Image >! temp

		if(`echo $Image | grep "$NORDIC_BOLD_List[$i]"` != "") then
			decho "${Image} is probably a NORDIC phase image."
			set IsNordic = 1
			break
		endif

		@ i++
	end

	if($IsNordic) then
		continue
	endif

	set GoodScans = ($GoodScans \"$Image\")
end

if($#GoodScans > 0) then

	set IsMultiecho = 0

	set BOLD_dwell = ()
	set BoldIndices = ()
	unset BOLD_json
	@ i = 1
	while($i <= $#GoodScans)
		set BoldIndices = ($BoldIndices $i)
		set json = `echo ${DICOM_Dir}/$GoodScans[$i]:r:r".json" | sed 's/\"//g'`

		if(`grep \"EchoNumber\" $json` != "") then
			echo "data is multiecho"
			set IsMultiecho = 1
			set BOLD_json = $json
		endif

		@ i++
	end

	if(! $?BOLD_json) then
		set BOLD_json = `echo ${DICOM_Dir}/$GoodScans[1]:r:r".json" | sed 's/\"//g'`
	endif

	echo "Using $BOLD_json for BOLD timings."

	#check the BOLD to see if it is MultiEcho
	if($IsMultiecho) then

		set ME_ScanSets = ()
		set BOLD_TE = ()
		set BOLD_ORDER = ()
		@ i = 1
		set ScanOrder = ($GoodScans)

		#go through each bold run and put the TE  and run in order from lowest echo to highest

		while($i <= $#ScanOrder)
			@ lowest_te = 10000
			@ lowest_te_index = 1
			@ j = 1
			while($j <= $#ScanOrder)

				if($ScanOrder[$j] != "") then
					set BOLD_Scan = `echo ${DICOM_Dir}/$ScanOrder[$j] | sed -r 's/"//g'`
					set BOLD_Scan = $BOLD_Scan:r:r".json"

					set curr_te = `$PP_SCRIPTS/Utilities/GetJSON_Value $BOLD_Scan EchoTime | awk '{print $1 * 1000}'`

					if(`echo $curr_te $lowest_te | awk '{if($1 < $2) print 1}'`) then
						set lowest_te = $curr_te
						@ lowest_te_index = $j
					endif
				endif
				@ j++
			end

			set BOLD_ORDER =($BOLD_ORDER $ScanOrder[$lowest_te_index])
			set BOLD_TE = ($BOLD_TE $lowest_te)
			set ScanOrder[$lowest_te_index] = ""

			@ i++
		end

		#trim off duplicate echos
		set BOLD_TE = (`echo $BOLD_TE | sed 's/ /\n/g' | uniq`)

		echo $BOLD_TE

		set ME_ScanIndices = (`echo $BOLD_ORDER | sed -r 's/ /\n/g' | grep _e | grep .nii | sed -r 's/_/\t/g' | awk '{print $(NF-1)}'`)
		echo $ME_ScanIndices
		rm -f temp
		touch temp
		foreach Run($ME_ScanIndices)
			echo $Run >> temp
		end

		sort temp | uniq

		set ME_ScanIndices = (`sort temp | uniq | awk '{printf $1" "}'`)

		rm temp

		@ i = 1
		@ Assignment = 1
		while($i <= $#ME_ScanIndices)
			set ME_SetLength = ""
			@ j = 1
			while($j <= $#BOLD_TE)
				set ME_SetLength = `echo $ME_SetLength$Assignment`

				if($j < $#BOLD_TE) then
					set ME_SetLength = `echo $ME_SetLength","`
				endif
				@ j++
				@ Assignment++
			end
			set ME_ScanSets = ($ME_ScanSets $ME_SetLength)
			@ i++
		end

		echo $ME_ScanSets

		set ME_ScanSets_Reordered = ()
		#now reorder the ME_ScanSets by TE
		foreach ME($ME_ScanSets)

			set curr_me_indices = (`echo $ME | sed -r 's/,/ /g'`)

			#read each json and do like before where we found all the TE's
			set ScanOrder = ()
			echo $#GoodScans

			foreach SetScan($curr_me_indices)
				set ScanOrder = ($ScanOrder $GoodScans[$SetScan])
			end

			@ i = 1
			set SET_ORDER = ()
			while($i <= $#ScanOrder)

				@ lowest_te = 1000
				@ lowest_te_index = 1
				@ j = 1
				while($j <= $#ScanOrder)

					if($ScanOrder[$j] != "") then
						set BOLD_Scan = `echo ${DICOM_Dir}/$ScanOrder[$j] | sed -r 's/"//g'`
						set BOLD_Scan = $BOLD_Scan:r:r".json"

						set curr_te = `$PP_SCRIPTS/Utilities/GetJSON_Value $BOLD_Scan EchoTime | awk '{print $1 * 1000}'`

						if(`echo $curr_te $lowest_te | awk '{if($1 < $2) print 1}'`) then
							set lowest_te = $curr_te
							@ lowest_te_index = $j
						endif
					endif
					@ j++
				end

				set SET_ORDER = ($SET_ORDER$curr_me_indices[$lowest_te_index]",")
				set ScanOrder[$lowest_te_index] = ""

				@ i++
			end

			set ME_ScanSets_Reordered = ($ME_ScanSets_Reordered $SET_ORDER)
		end

		set RegisterEcho = `echo $#SET_ORDER | awk '{printf("%3.0f",$1/2)}'`

		echo $ME_ScanSets_Reordered
		set ME_ScanSets = ($ME_ScanSets_Reordered)
		echo $ME_ScanSets

		set ME_SetIndices = ()
		@ i = 1
		while($i <= $#ME_ScanSets)
			set ME_SetIndices = ($ME_SetIndices $i)
			@ i++
		end

	else
		set BOLD_TE = `$PP_SCRIPTS/Utilities/GetJSON_Value $BOLD_json EchoTime`
	endif

	echo "set BOLD = ($GoodScans)		# filenames of the bold runs" >> $output_params_file
	echo "set RunIndex = ("$BoldIndices")		# BOLD RunID" >> $output_params_file

	if($?ME_ScanSets) then
		echo "set FCProcIndex = ("$ME_SetIndices")		# Multiecho Set ID's to functionally preprocess" >> $output_params_file
	else
		echo "set FCProcIndex = ("$BoldIndices")		# BOLD RunID's to functionally preprocess" >> $output_params_file
	endif

	echo "BOLD Scans: "$GoodScans

	##################
	# fcMRI parameters
	##################

	#Parameters from the JSON
	#SliceTiming = order and time of a slice
	#EchoTime = TE
	#RepetitionTime = TR
	#EffectiveEchoSpacing = dwell we will use
	#PhaseEncodingDirection = direction of encoding (j- = -y)
	#ParallelReductionFactorInPlane = GRAPPA/SENSE accelleration factor

	set BOLD_dwell = ()

	foreach Scan($GoodScans)

		set curr_scan = `echo $Scan | sed 's/\"//g'`

		set DWELL = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$curr_scan:r:r".json" EffectiveEchoSpacing`

		if($#DWELL == 0) then
			set DWELL = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$curr_scan:r:r".json" DwellTime | awk '{printf("%.14f",$1)}'`
		endif

		if($#DWELL == 0) then
			#try to compute it
			set bandwidth = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$curr_scan:r:r".json" PixelBandwidth`
			set matrix = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$curr_scan:r:r".json" ReconMatrixPE`
			set factor = 1
			set DWELL = `echo $bandwidth $matrix $factor | awk '{printf("%s",((1/($1 * $2))/$3) * 1000)}'`

			if($DWELL == "") then
				set DWELL = "-"
			endif
		endif

		set BOLD_dwell = ($BOLD_dwell $DWELL)
	end

	echo $BOLD_dwell

	if($#BOLD_dwell == 0) then
		set BOLD_dwell = `printf "%.8f" $BOLD_dwell`
	endif

	set BOLD_TR = `$PP_SCRIPTS/Utilities/GetJSON_Value $BOLD_json RepetitionTime | awk '{if($1 > 20) print($1/1000); else print($1);'}`

	set BOLD_PED = ()
	foreach Scan($GoodScans)

		set curr_scan = `echo $Scan | sed 's/\"//g'`

		set PED = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$curr_scan:r:r".json" PhaseEncodingDirection`

		if($#PED == 0) then
			set PED = `$PP_SCRIPTS/Utilities/GetJSON_Value ${DICOM_Dir}/$curr_scan:r:r".json" PhaseEncodingAxis`
		endif

		set BOLD_PED = ($BOLD_PED `$PP_SCRIPTS/Utilities/AcqDir_to_PhDir $PED`)

	end

	set BOLD_MB_Factor = `$PP_SCRIPTS/Utilities/GetJSON_Value $BOLD_json MultibandAccelerationFactor`

	if($#BOLD_MB_Factor == 0) then
		set BOLD_MB_Factor = 1
	endif

	#extracts the interleave timings
	echo "set BOLD_SIO = `$PP_SCRIPTS/Utilities/slice_interleave_order.csh "\"$BOLD_json\""`	# Slice interleave order" >> $output_params_file

	if(`echo $BOLD_TR | awk '{if($1 >= 0.3) print 1; else print 0;}'` == 1) then
		echo "set BOLD_TR	= "${BOLD_TR}"		# time per frame in seconds" >> $output_params_file
		echo "set BOLD_TE	= ("${BOLD_TE}")		# epi echo time(s) in ms" >> $output_params_file
		echo "@ epidir	= 0		# 0 for inf->sup (product sequence default); 1 for sup->inf acquisition (Erbil sequence);" >> $output_params_file
	else
		echo "Assuming Allegra Erbil BOLD Data."
		echo "set BOLD_TR	= 2.064		# time per frame in seconds" >> $output_params_file
		echo "set BOLD_TE	= 0.0645		# time per slice in seconds (0 => will be computed assuming even spacing)" >> $output_params_file
		echo "@ epidir	= 1		# 0 for inf->sup (product sequence default); 1 for sup->inf acquisition (Erbil sequence);" >> $output_params_file
	endif

	if($?ME_ScanSets)  then
		echo "set ME_ScanSets = (" $ME_ScanSets ")	# the scan index for each multi echo run. Ordered by increasing TE." >> $output_params_file
	else
		echo "#set ME_ScanSets = ()	# the scan index for each multi echo run.  Ordered by increasing TE." >> $output_params_file
	endif

	echo "@ skip		= 4		# pre-functional BOLD frames for Generic Cross Bold" >> $output_params_file

	if($#BOLD_MB_Factor == 1) then
		echo "set BOLD_MB_Factor = "$BOLD_MB_Factor"		#set the multiband factor of the BOLD" >> $output_params_file
	endif
else
	echo "#set BOLD = ()		# filenames of the bold runs" >> $output_params_file
	echo "#set RunIndex = ()		# BOLD RunID" >> $output_params_file
	echo "#set FCProcIndex = ()		# BOLD RunID's to functionally preprocess" >> $output_params_file
	echo "#set BOLD_TR	= 		# time per frame in seconds" >> $output_params_file
	echo "#set BOLD_TE	= 		# epi echo time in ms" >> $output_params_file
	echo "#@ epidir	= 0		# 0 for inf->sup (product sequence default); 1 for sup->inf acquisition (Erbil sequence);" >> $output_params_file
	echo "#set imaflip	= 0		# 0 | x | y | xy" >> $output_params_file
	echo "#@ skip		= 4		# pre-functional BOLD frames for Generic Cross Bold" >> $output_params_file
	echo "#set BOLD_MB_Factor = 1		#set the multiband factor of the BOLD" >> $output_params_file
endif

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$NORDIC_BOLD_List" ${DICOM_Dir}`)

if($#Scan > 0) then
	##################################
	## Index the NORDIC BOLD's phase
	##################################
	echo "Set NORDIC BOLD..."

	set GoodScans = ()
	foreach Image($Scan)
		if($Image:e == "gz") set BOLD_json = ${DICOM_Dir}/$Image:r:r".json"
		if($Image:e == "nii") set BOLD_json = ${DICOM_Dir}/$Image:r".json"

		if(! -e $BOLD_json) then
			decho "Could not find a json to go with $Image. BIDS conversion must have failed or been done improperly."
			continue
		endif

		if(`grep ORIGINAL $BOLD_json` == "") then
			decho "${Image} is not an original series. Skipping..."
			continue
		endif

		if(`fslinfo ${DICOM_Dir}/$Image | grep dim4 | head -1 | awk '{print $2}'` <= 10) then
			decho "${Image} does not have enough frames. Ignoring."
			continue
		endif

		set GoodScans =($GoodScans \"$Image\")

	end

	echo "set NORDIC_BOLD = ($GoodScans)	#NORDIC BOLD phase timeseries" >> $output_params_file
	echo "set NORDIC_BOLD_NoiseVol = 3	#The noise volumes in the NORDIC BOLD phase timeseries" >> $output_params_file
endif

set Scan = (`$PP_SCRIPTS/Utilities/detect_scan.csh "$BOLD_FM_List" ${DICOM_Dir}`)

if($#Scan > 1) then
	echo "Set BOLD Field Mapping..."
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

	if($?BOLD_dwell && $?BOLD_PED) then
		echo "set BOLD_dwell = (${BOLD_dwell})	#1/( (0019,1028) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
		echo "set BOLD_ped		= ($BOLD_PED)" >> $output_params_file
	else
		echo "set BOLD_dwell = 0	#1/( (0019,1028) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
		echo "set BOLD_ped		= (-y)" >> $output_params_file
	endif

	echo "set BOLD_fm = ("${Scan}")		# BOLD field mapping Images" >> $output_params_file
	echo "set BOLD_FieldMapping = "\"${fm_method}\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration; id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps;  synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
	#need to be auto calculated in the future
	echo "set BOLD_delta = ${delta}	#time between echos for the field map magnitude images" >> $output_params_file
	echo "set BOLD_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
	echo "set BOLD_CostFunction = corratio	#Cost function to use to register BOLD to target. flirt uses this.." >> $output_params_file
	echo "set BOLD_FinalResolution = 2	#set the final isotropic resolution of the BOLD data. Set to 0 to keep in native target space." >> $output_params_file
else if($#Scan == 0 && $?BOLD_dwell && $?BOLD_PED) then
	echo "Set BOLD Field Mapping to synth..."

	if($?BOLD_dwell && $?BOLD_PED) then
		echo "set BOLD_dwell = (${BOLD_dwell})	#1/( (0019,1028) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
		echo "set BOLD_ped		= ($BOLD_PED)" >> $output_params_file
	else
		echo "set BOLD_dwell = 0	#1/( (0019,1028) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
		echo "set BOLD_ped		= (-y)" >> $output_params_file
	endif

	echo "#set BOLD_fm = ()		# BOLD field mapping Images" >> $output_params_file
	echo "set BOLD_FieldMapping = "\"6dof\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
	#need to be auto calculated in the future
	echo "set BOLD_delta = 2.46	#time between echos for the field map magnitude images" >> $output_params_file
	echo "set BOLD_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
	echo "set BOLD_CostFunction = corratio	#Cost function to use to register BOLD to target. flirt uses this.." >> $output_params_file
	echo "set BOLD_FinalResolution = 2	#set the final isotropic resolution of the BOLD data. Set to 0 to keep in native target space." >> $output_params_file
else
	echo "#set BOLD_dwell = 0	#1/( (0019,1028) * (0051,100b) )*1000 / grappa factor NOTE: This is in ms." >> $output_params_file
	echo "#set BOLD_ped		= (-y)" >> $output_params_file
	echo "#set BOLD_fm = ()		# BOLD field mapping Images" >> $output_params_file
	echo "#set BOLD_FieldMapping = "\"6dof\""# gre: gradient echo fieldmapping; appa: ap pa spin echo field mapping using bbr; appa_6dof: ap pa field mapping using 6 dof registration;  id_appa_6dof: ap pa field mapping using 6 dof registration and deriving distortion from opposing phase encoded images. Does not rely on seperate field maps; synth: compute field mapping and use 6dof registration; 6dof: no field mapping, use 6dof registration; none: no field mapping, use bbr registration" >> $output_params_file
	echo "#set BOLD_delta = 0	#time between echos for the field map magnitude images" >> $output_params_file
	echo "#set BOLD_Reg_Target = T1	#Set the anatomical image to register metric modalities to (T1/T2/FLAIR)." >> $output_params_file
	echo "#set BOLD_CostFunction = corratio	#Cost function to use to register BOLD to target. flirt uses this.." >> $output_params_file
	echo "#set BOLD_FinalResolution = 2	#set the final isotropic resolution of the BOLD data. Set to 0 to keep in native target space." >> $output_params_file
endif

