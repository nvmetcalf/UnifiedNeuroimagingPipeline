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

set FM_Suffix = $3

set AtlasName = $target:t

set dwell = ($4)
set ped = ($5)

set fm = ($6)

set FieldMapping = $7

set Reg_Target = $8

set delta = $9

set ImageStack = (${10})

set RegMethod = ${11}

set SubjectHome = $cwd

#check to make sure all the dwells are the same
set uniq_dwells = `echo $dwell | tr " " "\n" | sort | uniq`
echo $uniq_dwells
if($#uniq_dwells > 1) then
	echo "SCRIPT: $0 : 00003 : More than 1 unique dwell detected! Unable to make generalized end to end transform."
	exit 1
endif

if(! $?Reg_Target) then
	set Reg_Target = T1
endif

#sanity check for acquisition directions
foreach direction($ped)
	if($direction != "y" && $direction != "-y" && $direction != "-x" && $direction != "x") then
		echo "SCRIPT: $0 : 00004 : Unsupported acquisition direction detected: $direction" $DebugFile
		exit 1
	endif
end

#check for a field map. If one does not exist, then compute one using basis maps
#if one does exist, then use it
if ($?fm && $FieldMapping == "gre") then

	$PP_SCRIPTS/Registration/DistortionCorrection_GRE.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target $delta
	if($status) then
		echo "SCRIPT: $0 : 00005 : failed GRE distortion correction."
		exit 1
	endif
else if ($?fm && $FieldMapping == "gre_6dof") then

	$PP_SCRIPTS/Registration/DistortionCorrection_GRE_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target $delta $RegMethod
	if($status) then
		echo "SCRIPT: $0 : 00006 : failed 6dof gre distortion correction."
		exit 1
	endif

else if($?fm && $FieldMapping == "appa") then

	$PP_SCRIPTS/Registration/DistortionCorrection_APPA.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target
	if($status) then
		echo "SCRIPT: $0 : 00007 : failed bbr appa spin echo distortion correction."
		exit 1
	endif

else if($?fm && $FieldMapping == "appa_6dof") then
	$PP_SCRIPTS/Registration/DistortionCorrection_APPA_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target $RegMethod
	if($status) then
		echo "SCRIPT: $0 : 00008 : failed 6dof appa distortion correction."
		exit 1
	endif

else if($FieldMapping == "synth") then
	$PP_SCRIPTS/Registration/DistortionCorrection_Synth.csh $1 $2 $FM_Suffix "$dwell" "$ped" $Reg_Target
	if($status) then
		echo "SCRIPT: $0 : 00009 : failed synthetic distortion correction."
		exit 1
	endif

else if($FieldMapping == "6dof") then
	$PP_SCRIPTS/Registration/Register_6DOF.csh $1 $2 $FM_Suffix "$ped" $Reg_Target $RegMethod
	if($status) then
		echo "SCRIPT: $0 : 00010 : failed 6dof registration."
		exit 1
	endif
else if($FieldMapping == "id_appa_6dof") then
	$PP_SCRIPTS/Registration/DistortionCorrection_IDAPPA_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$ImageStack" $Reg_Target $RegMethod
	if($status) then
		echo "SCRIPT: $0 : 00011 : failed image derived appa 6dof distortion correction."
		exit 1
	endif
else if($FieldMapping == "synth_b0") then
	$PP_SCRIPTS/Registration/DistortionCorrection_SynthB0.csh $1 $2 $FM_Suffix "$dwell" "$ped" $Reg_Target
	if($status) then
		echo "SCRIPT: $0 : 00012 : failed synthetic appa distortion correction."
		exit 1
	endif
else
	$PP_SCRIPTS/Registration/Register_BBR.csh $1 $2 $FM_Suffix "$ped" $Reg_Target
	if($status) then
		echo "SCRIPT: $0 : 00013 : failed bbr registration."
		exit 1
	endif
endif
