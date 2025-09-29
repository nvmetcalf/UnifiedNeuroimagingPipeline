#!/bin/csh

##############################
# fcMRI-specific preprocessing
##############################
set program = $0
set program = $program:t
set rcsid = '$Id: fcMRI_preproc_130715.csh,v 1.12 2014/08/23 06:05:30 avi Exp $'
echo $rcsid

if (${#argv} < 1) then
	echo "Usage:	$program <parameters file> [options]"
	echo "e.g.,	$program VB16168.params"
	echo "-debug_file	specify a debug information file"
	echo "-format		speficy a format file for excluding frames"
	echo "-debug		enable verbose output."
	echo ""
	echo "NOTE: All regressors are always computed. However, only those that are not skipped via options are"
	echo "		included in the nuisance_regressors.dat file."
	echo "-options		Use options from a parameters file."
	exit 1
endif
date
uname -a

#set default variables. These will be overridden by the params file.
set SubjectHome = $cwd
set DoVolumeRegression = 1
set NonLinear = 0
set DoVolumeBPSS = 1
set options = ""
set VolSmoothingFWHM = 0

set Residual_Trailer = ""

#Source the params file. These settings will be overridden by [options]
set prmfile = $1
if (! -e $prmfile) then
	decho "$prmfile not found" $DebugFile
	exit 1
endif

source $prmfile
if($status) exit 1

@ i = 2
while($i <= $#argv)

	@ k = $i + 1
	switch(${argv[$i]})
		case -debug_file:
			set DebugFile = $argv[$k]
			echo "DebugFile = $DebugFile"
			@ i = $k
			breaksw
		case -format:
			set format = `cat $argv[$k]`
			echo "Using format: $format"
			@ i = $k

			breaksw
		case -options:
			echo "Sourced options from $argv[$k]"
			set options = $argv[$k]
			source $argv[$k]
			@ i = $k
			breaksw
		default:
			echo "$argv[$i] not a valid option!"
			exit 1
			breaksw
	endsw
	@ i++
end

set FinalResolution = $BOLD_FinalResolution

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if(! $?RegisterEcho) then
	set RegisterEcho = 1
endif

if(! $?FCProcIndex) then
	decho "Cannot run rsfMRI preprocessing unless there is data available to process." $DebugFile
	exit 1
endif

#this is to check that the final result of the previous module exists
if (! -e Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz) then
	decho "Cannot find atlas aligned BOLD ( Functional/Volume/${patid}_upck_faln_dbnd_xr3d_dc_atl.nii.gz)." $DebugFile
	exit 1
endif

if( ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz) then
	set DVAR_Threshold = 0
	decho "WARNING: Disabling DVAR threshold as denoised timeseries does not exist!"
endif

#do a sanity check on the runs we want to functionally preprocess. They must be
#	a part of the set that has been atlas registered
foreach Run($FCProcIndex)
	set found = 0
	foreach AlignedRun($RunIndex)
		if($Run == $AlignedRun) then
			set found = 1
			break
		endif
	end

	if(! $found) then
		decho "$Run has not been atlas aligned. Cannot continue." $DebugFile
		exit 1
	endif
end

if(! -e $ScratchFolder/${patid}/BOLD_temp) then
	mkdir $ScratchFolder/${patid}/BOLD_temp
endif

#create a conc file if we do not provide one
set concroot	= $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI
set conc	= $concroot.conc

# set the normal BOLD timeseries we will want to do smoothing on, if requested.
set SmoothTS = ${SubjectHome}/Functional/Volume/`basename ${concroot}`_uout_bpss_resid

#goto GLM
#make a list of the bolds that we are going to functionally preprocess
pushd $ScratchFolder/${patid}/BOLD_temp

	ftouch rsfMRI_preproc.lst
	if($status) exit 1

	foreach Run($FCProcIndex)
		echo bold${Run}/bold${Run}_upck_faln_dbnd_xr3d_dc_atl.4dfp.img >> rsfMRI_preproc.lst
	end

	$RELEASE/conc_4dfp $conc -lrsfMRI_preproc.lst
	if($status) exit 1

	echo `conc2format $conc $skip` >! ${SubjectHome}/Functional/TemporalMask/${patid}_AllVolumes_rsfMRI_preproc.format
	if ($status) exit $status
popd

#####################
# check prerequisites
#####################

if (! -e Functional/TemporalMask/${patid}_AllVolumes_rsfMRI_preproc.format && ! $?format) then
	decho "Functional/TemporalMask/${patid}_AllVolumes_rsfMRI_preproc.format not found." $DebugFile
	exit 1
endif

if(! $?format) then
	set format = `cat Functional/TemporalMask/${patid}_AllVolumes_rsfMRI_preproc.format`
endif

decho "Using format: $format" $DebugFile

#######################
# run Generate_FS_Masks
#######################
EXTRACT_FS:
if(! -e ${SubjectHome}/Masks/${patid}_used_voxels.nii.gz) then
	decho "Unable to find ${SubjectHome}/Masks/${patid}_used_voxels.nii.gz! This is generated during atlas registration, so atlas registration may have failed." $DebugFile
	exit 1
endif

if($NonLinear && ! -e ${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz) then
	decho "Unable to find ${SubjectHome}/Masks/${patid}_used_voxels_fnirt.nii.gz! This is generated during atlas registration if non linear registration is requested, so atlas registration may have failed." $DebugFile
	exit 1
endif

$PP_SCRIPTS/Utilities/Generate_FS_Masks_AZS_NM.csh $prmfile $options
if ($status) exit $status

pushd Functional/TemporalMask
#make a format that encodes for the start of each run
	format2lst `conc2format $conc 1` | awk '{if($1 == "x") {printf("\t0");} else {printf("\t1");}}' >! run_boundaries_tmask.txt
popd

$PP_SCRIPTS/fMRI/Compute_Defined_Demean_InitSD.csh $prmfile $options
if($status) exit 1

MOVEMENT:
if(${ComputeMOVERegressor}) then
	$PP_SCRIPTS/fMRI/Compute_Movement_Regressor.csh $prmfile $options
	if($status) exit 1

	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_mov`
	else
		set Residual_Trailer = "mov"
	endif
endif

BANDPASS:
$PP_SCRIPTS/fMRI/Compute_SpectralFiltering.csh $prmfile $options
if($status) exit 1

CSF:
if(${ComputeEACSFRegressor}) then
	$PP_SCRIPTS/fMRI/Compute_eaCSF_Regressor.csh $prmfile $options
	if($status) exit 1

	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_eacsf`
	else
		set Residual_Trailer = "eacsf"
	endif
endif


VENTRICLE:
if(${ComputeVENT}) then
	$PP_SCRIPTS/fMRI/Compute_Ventricle_Regressor.csh $prmfile $options
	if($status) exit 1

	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_vent`
	else
		set Residual_Trailer = "vent"
	endif
endif


WM:
if(${ComputeWM}) then
	$PP_SCRIPTS/fMRI/Compute_WhiteMatter_Regressor.csh $prmfile $options
	if($status) exit 1

	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_wm`
	else
		set Residual_Trailer = "wm"
	endif
endif


GSR:
if(${ComputeWBRegressor}) then
	$PP_SCRIPTS/fMRI/Compute_GlobalSignalRegressor.csh $prmfile $options
	if($status) exit 1

	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_gs`
	else
		set Residual_Trailer = "gs"
	endif
endif

if($Residual_Trailer != "") then
	set Residual_Trailer = `echo ${Residual_Trailer}_resid`
else
	set Residual_Trailer = "resid"
endif

####################################
# paste nuisance regressors together and compute SVD
####################################
PASTE:
$PP_SCRIPTS/fMRI/Generate_Nuissance_Regressors.csh $prmfile $options
if($status) exit 1

##########################################################################
# run glm_4dfp to remove nuisance regressors out of volumetric time series
##########################################################################
GLM:
if($DoVolumeRegression) then

	decho "Performing Volume Linear Regression of Nuissance Regressors - NOT WELL TESTED!" $DebugFile

	pushd $ScratchFolder/${patid}/BOLD_temp


		if( ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_${Residual_Trailer}.nii.gz) then
			set DVAR_Threshold = 0
			decho "WARNING: Disabling DVAR threshold as denoised timeseries does not exist!"
		endif

		if($DVAR_Threshold != 0 && $FD_Threshold == 0) then
			set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_dvar.format
		else if($DVAR_Threshold == 0 && $FD_Threshold != 0) then
			set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_fd.format
		else if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
			set format = ${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_resid_dvar_fd.format
		else
			decho "Unknown combination of format criteria. Iterative rsfMRI processing not possible." ${DebugFile}
			exit 1
		endif


		glm_4dfp $format ${SubjectHome}/Functional/Regressors/${patid}_all_regressors.dat ${concroot}_uout_bpss.conc -r${Residual_Trailer} -o
		#fsl_glm -i ${SubjectHome}/Functional/Volume/`basename ${concroot}`.nii.gz -o $glm_out
		if ($status) then
			decho "Failed to perform linear regression of nuissance regressors!" $DebugFile
			exit 1
		endif
		conc2nifti ${concroot}_uout_bpss_${Residual_Trailer}.conc
		gzip -fc ${concroot}_uout_bpss_${Residual_Trailer}.nii > ${SubjectHome}/Functional/Volume/`basename ${concroot}`_uout_bpss_${Residual_Trailer}.nii.gz
		if($status) exit 1
		#mv ${concroot}_uout_bpss_resid.nii.gz ${SubjectHome}/Functional/Volume/`basename ${concroot}`_uout_bpss_resid.nii.gz
	popd
endif

#perform spatial smoothing
if($VolSmoothingFWHM != "0") then

	if(! -e $SmoothTS ) then
		set SmoothTS = ${SubjectHome}/Functional/Volume/`basename ${concroot}`_uout_bpss_${Residual_Trailer}
		decho "Residual timeseries does not exist. Assuming user wants to smooth denoised data." $DebugFile
	endif

	decho "Smoothing functional BOLD volumes: $VolSmoothingFWHM mm FWHM" $DebugFile

	set SmoothingSigma = `echo $VolSmoothingFWHM | awk '{print($1/2.3548);}'`
	pushd ${SubjectHome}/Functional/Volume/

 		#smooth the bold, 0ing voxels outside the mask
 		fslmaths $SmoothTS -kernel gauss $SmoothingSigma -fmean $SmoothTS:r:r"_sm${VolSmoothingFWHM}"
 		if($status) exit 1
	popd
endif

pushd $ScratchFolder/${patid}/BOLD_temp
	find . -name "*_rsfMRI_uout.nii*" -exec rm {} \;
	find . -name "*_uout.4dfp.*" -exec rm {} \;
	find . -name "*_uout_bpss.4dfp.*" -exec rm {} \;
popd

#clean up 4dfp files
pushd Masks/FreesurferMasks
	rm -f *.4dfp.* ${SubjectHome}/Functional/Volume/*dfnd.4dfp.*
popd

exit 0
