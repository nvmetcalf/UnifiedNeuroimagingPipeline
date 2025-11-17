#!/bin/csh

if(! -e $1) then
	echo "SCRIPT: $0 : 00001 : $1 does not exist"
	exit 1
endif

if(! -e $2) then
	echo "SCRIPT: $0 : 00002 : $2 does not exist"
	exit 1
endif

source $1
source $2

if($#argv < 11) then
	echo "ComputeDistortionCorretion.csh <participant params file> <processing params file> <options>"
	echo "	Wrapper for all the distortion correction and metric modality registrations."
	echo "	Options:"
	echo "	-fm_suffix : the part of the folder name after FieldMapping_ in Anatomical/Volume. Should be unique to the modality."
	echo "	-dwell : a set of timings for distortion correction of the image list. Should be surrounding in double quotes. I.e. -dwell "\"0.0005 0.0005\"
	echo "	-ped : phase encoding directions for the image list. Should be surrounded by double quotes like with dwell."
	echo "	-fm : field map images. Can be spin echo or gradient echo. Should be surrounded by double quotes."
	echo "	-fm_method : the method of field mapping/registration. Default is 6dof."
	echo "		valid options: "
	echo "			6dof : only perform rigid body register for each phase encoding direction. No distortion correction."
	echo "			bbr : using BBR, register each phase encoding direction. No distortion correction."
	echo "			gre : using BBR, register and distortion correct each phase encoding direction using Gradient Echo field maps."
	echo "			gre_6dof : using 6dof, register and distortion correct each phase encoding direction using Gradient Echo field maps."
	echo "			appa : using BBR, register and distortion correct each phase encoding direction using spin echo field maps."
	echo "			appa_6dof : using 6dof, register and distortion correct each phase encoding direction using spin echo field maps."
	echo "			id_appa_6dof : using 6dof, register and distortion correct each phase encoding direction using the images provided to compute field maps."
	echo "	-target : target modality for the final registration. Can be itself if you want to stay in data space."
	echo "	-delta : only needed for gradient echo field mapping. Delta in seconds between echos."
	echo "	-images : list of nifti images to compute image derived distortion maps. Only needed for id_appa_6dof. Should be a double quote surrounded list."
	echo "	-reg_method : cost function to use for linear registations. Default is mutualinfo."
	echo "	-final_res : final isotropic resolution to sample the image to. 0 (target data space), 1, 2, or 3mm"
	exit 1
endif

#preinitialize variables. Will unset empty ones later
set fm = ""
set dwell = ""
set ped = ""
set Reg_Target = ""
set RegMethod = ""
set ImageStack = ""
set FinalResolution = 0

@ i = 3
while($i <= $#argv)
	switch($argv[$i])
		case "-fm_suffix":
			@ i++
			set FM_Suffix = $argv[$i]
			echo "FieldMapping Suffix: $FM_Suffix"
			breaksw
		case "-dwell":
			@ i++
			set dwell = ($argv[$i])
			echo "Dwell: $dwell"
			breaksw
		case "-ped":
			@ i++
			set ped = ($argv[$i])
			echo "Phae Encoding Directions: $fm"
			breaksw
		case "-fm":
			@ i++
			set fm = ($argv[$i])
			echo "Field Maps: $fm"
			breaksw
		case "-fm_method":
			@ i++
			set FieldMapping = ($argv[$i])
			echo "Field Mapping Method: $FieldMapping"
			breaksw
		case "-target":
			@ i++
			set Reg_Target = ($argv[$i])
			echo "Registation Target: $Reg_Target"
			breaksw
		case "-delta":
			@ i++
			set delta = ($argv[$i])
			echo "Echo Delta: $delta"
			breaksw
		case "-images":
			@ i++
			set ImageStack = ($argv[$i])
			echo "Images: $ImageStack"
			breaksw
		case "-reg_method":
			@ i++
			set RegMethod = ($argv[$i])
			echo "Registation Cost Function: $RegMethod"
			breaksw
		case "-final_res":
			@ i++
			set FinalResolution = $argv[$i]
			echo "Final Resolution: $FinalResolution"
			breaksw
		default:
			echo "Unknown option: $argv[$i]"
			exit 1
			breaksw
	endsw
	@ i++
end

if(! $?FM_Suffix) then
	echo "-fm_suffix is required. Cannot continue."
	exit 1
endif

if(! $?FieldMapping) then
	echo "-fm_method is a not set. Defaulting to 6dof."
	set FieldMapping = "6dof"
endif

if(! $?RegMethod) then
	echo "-reg_method is a not set. Defaulting to mutualinfo."
	set RegMethod = "mutualinfo"
endif

if($?dwell) then
	#check to make sure all the dwells are the same
	set uniq_dwells = `echo $dwell | tr " " "\n" | sort | uniq`
	echo $uniq_dwells
	if($#uniq_dwells > 1) then
		echo "SCRIPT: $0 : 00003 : More than 1 unique dwell detected! Unable to make generalized end to end transform."
		exit 1
	endif
endif

if($?ped) then
	#sanity check for acquisition directions
	foreach direction($ped)
		if($direction != "y" && $direction != "-y" && $direction != "-x" && $direction != "x") then
			echo "SCRIPT: $0 : 00004 : Unsupported acquisition direction detected: $direction" $DebugFile
			exit 1
		endif
	end
endif

if($#dwell == 0) then
	unset dwell
endif

if($#ped == 0) then
	unset ped
endif

if($#Reg_Target == 0) then
	unset Reg_Target
endif

if($#ImageStack == 0) then
	unset ImageStack
endif

#check for a field map. If one does not exist, then compute one using basis maps
#if one does exist, then use it
if ($?fm && $FieldMapping == "gre" && $?dwell && $?ped && $?Reg_Target && $?delta) then

	$PP_SCRIPTS/Registration/DistortionCorrection_GRE.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target $delta
	if($status) then
		echo "SCRIPT: $0 : 00005 : failed GRE distortion correction."
		exit 1
	endif
else if ($?fm && $FieldMapping == "gre_6dof" && $?dwell && $?ped && $?Reg_Target && $?delta && $?RegMethod) then

	$PP_SCRIPTS/Registration/DistortionCorrection_GRE_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target $delta $RegMethod
	if($status) then
		echo "SCRIPT: $0 : 00006 : failed 6dof gre distortion correction."
		exit 1
	endif

else if($?fm && $FieldMapping == "appa" && $?dwell && $?ped && $?Reg_Target) then

	$PP_SCRIPTS/Registration/DistortionCorrection_APPA.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target
	if($status) then
		echo "SCRIPT: $0 : 00007 : failed bbr appa spin echo distortion correction."
		exit 1
	endif

else if($?fm && $FieldMapping == "appa_6dof" && $?dwell && $?ped && $?Reg_Target && $?RegMethod) then
	$PP_SCRIPTS/Registration/DistortionCorrection_APPA_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target $RegMethod
	if($status) then
		echo "SCRIPT: $0 : 00008 : failed 6dof appa distortion correction."
		exit 1
	endif

else if($FieldMapping == "synth" && $?dwell && $?ped && $?Reg_Target) then
	$PP_SCRIPTS/Registration/DistortionCorrection_Synth.csh $1 $2 $FM_Suffix "$dwell" "$ped" $Reg_Target
	if($status) then
		echo "SCRIPT: $0 : 00009 : failed synthetic distortion correction."
		exit 1
	endif

else if($FieldMapping == "6dof" && $?dwell && $?ped && $?Reg_Target && $?RegMethod) then
	$PP_SCRIPTS/Registration/Register_6DOF.csh $1 $2 $FM_Suffix "$ped" $Reg_Target $RegMethod
	if($status) then
		echo "SCRIPT: $0 : 00010 : failed 6dof registration."
		exit 1
	endif
else if($FieldMapping == "id_appa_6dof" && $?dwell && $?ped && $?Reg_Target && $?RegMethod && $?ImageStack) then
	$PP_SCRIPTS/Registration/DistortionCorrection_IDAPPA_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$ImageStack" $Reg_Target $RegMethod
	if($status) then
		echo "SCRIPT: $0 : 00011 : failed image derived appa 6dof distortion correction."
		exit 1
	endif
else if($FieldMapping == "synth_b0" && $?dwell && $?ped && $?Reg_Target) then
	$PP_SCRIPTS/Registration/DistortionCorrection_SynthB0.csh $1 $2 $FM_Suffix "$dwell" "$ped" $Reg_Target
	if($status) then
		echo "SCRIPT: $0 : 00012 : failed synthetic appa distortion correction."
		exit 1
	endif
else if($FieldMapping == "bbr" && $?ped && $?Reg_Target) then
	$PP_SCRIPTS/Registration/Register_BBR.csh $1 $2 $FM_Suffix "$ped" $Reg_Target
	if($status) then
		echo "SCRIPT: $0 : 00013 : failed bbr registration."
		exit 1
	endif
else
	echo "Unknown Field Mapping method."
	exit 1
endif

$PP_SCRIPTS/Registration/Compute_Final_Warp.csh $1 $2 $FM_Suffix $Reg_Target $FinalResolution "$ped"
if($status) then
	echo "SCRIPT: $0 : 00014 : failed to compute final warp."
	exit 1
endif
