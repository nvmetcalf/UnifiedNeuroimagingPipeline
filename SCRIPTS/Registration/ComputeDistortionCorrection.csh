#!/bin/csh

source $1
source $2

set FM_Suffix = $3

set AtlasName = `basename $target`

set dwell = ($4)
set ped = ($5)

set fm = ($6)

set FieldMapping = $7

set Reg_Target = $8

set delta = $9

set ImageStack = (${10})

set SubjectHome = $cwd

#check to make sure all the dwells are the same
set uniq_dwells = `echo $dwell | tr " " "\n" | sort | uniq`
echo $uniq_dwells
if($#uniq_dwells > 1) then
	echo "More than 1 unique dwell detected! Unable to make generalized end to end transform."
	exit 1
endif

if(! $?Reg_Target) then
	set Reg_Target = T1
endif

#sanity check for acquisition directions
foreach direction($ped)
	if($direction != "y" && $direction != "-y" && $direction != "-x" && $direction != "x") then
		decho "Unsupported acquisition direction detected: $direction" $DebugFile
		exit 1
	endif
end

#check for a field map. If one does not exist, then compute one using basis maps
#if one does exist, then use it
if ($?fm && $FieldMapping == "gre") then

	$PP_SCRIPTS/Registration/DistortionCorrection_GRE.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target $delta
	if($status) exit 1
else if ($?fm && $FieldMapping == "gre_6dof") then

	$PP_SCRIPTS/Registration/DistortionCorrection_GRE_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target $delta
	if($status) exit 1
	
else if($?fm && $FieldMapping == "appa") then

	$PP_SCRIPTS/Registration/DistortionCorrection_APPA.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target
	if($status) exit 1
	
else if($?fm && $FieldMapping == "appa_6dof") then
	$PP_SCRIPTS/Registration/DistortionCorrection_APPA_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$fm" $Reg_Target
	if($status) exit 1
	
else if($FieldMapping == "synth") then
	$PP_SCRIPTS/Registration/DistortionCorrection_Synth.csh $1 $2 $FM_Suffix "$dwell" "$ped" $Reg_Target
	if($status) exit 1

else if($FieldMapping == "6dof") then
	$PP_SCRIPTS/Registration/Register_6DOF.csh $1 $2 $FM_Suffix "$ped" $Reg_Target
	if($status) exit 1
else if($FieldMapping == "id_appa_6dof") then 
	$PP_SCRIPTS/Registration/DistortionCorrection_IDAPPA_6DOF.csh $1 $2 $FM_Suffix "$dwell" "$ped" "$ImageStack" $Reg_Target
	if($status) exit 1
else if($FieldMapping == "synth_b0") then 
	$PP_SCRIPTS/Registration/DistortionCorrection_SynthB0.csh $1 $2 $FM_Suffix "$dwell" "$ped" $Reg_Target
	if($status) exit 1
else
	$PP_SCRIPTS/Registration/Register_BBR.csh $1 $2 $FM_Suffix "$ped" $Reg_Target
	if($status) exit 1
endif 
