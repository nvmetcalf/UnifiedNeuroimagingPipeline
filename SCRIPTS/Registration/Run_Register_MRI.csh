#!/bin/csh

if($#argv != 2) then
	echo "SCRIPT: $0 : 00000 : incorrect number of arguments"
	exit 1
endif

if (${#argv} < 1) then
	echo "usage:	"$0" params_file processing_params_file"
	exit 1
endif

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

if(! $?ContinueRegFail) set ContinueRegFail = 0

if(! $?day1_patid) set day1_patid = ""
if(! $?day1_path) set day1_path = ""

set SubjectHome = $cwd

if(! $?T1 && -e Freesurfer/mri/nu.mgz) then
	decho "No T1 set in params file, but freesurfer has an orig. Using the orig..."

	mri_convert Freesurfer/mri/nu.mgz dicom/${patid}_T1.nii.gz
	if($status) then
		echo "SCRIPT: $0 : 00003 : cannot convert freesurfer anatomy to be used as a T1."
		exit 1
	endif
	set T1 = "${patid}_T1_orig.nii.gz"
else
	set T1 = ""
endif

if($#argv > 2) goto $3

if($day1_patid != "" || $day1_path != "") then
	decho "This session is part of a multisession dataset. Skipping anatomical processing and alignment and preparing first session masks for this session."
	$PP_SCRIPTS/Utilities/Prepare_Multisession.csh $1 $2
	if($status) then
		echo "SCRIPT: $0 : 00004 : Unable to prepare the current session as a multisession."
		exit 1
	endif
	goto BOLD_PROC
endif

ANATOMICAL:

######################
#	T1
######################
if(! $?T1) then
	echo "SCRIPT: $0 : 00006 : Unable to find T1 image in params file, skipping."
	goto SKIP_T1
endif

$PP_SCRIPTS/Registration/Run_Register_T1.csh $1 $2
if($status && ! $ContinueRegFail) then
	echo "SCRIPT: $0 : 00007 : Could not register T1 to target atlas."
	exit 1
endif

SKIP_T1:

#################
#	T2
#################

if(! $?T2) then
	decho "Unable to find a T2 in the params file, skipping."
	goto SKIP_T2
endif

$PP_SCRIPTS/Registration/Run_Register_T2.csh $1 $2
if($status && ! $ContinueRegFail) then
	echo "SCRIPT: $0 : 00008 : Could not register T2 to target atlas."
	exit 1
endif

SKIP_T2:

###########################
#	FLAIR
###########################
if(! $?FLAIR) then
	decho "Unable to find a FLAIR in the params file, skipping."
	goto SKIP_FLAIR
endif

$PP_SCRIPTS/Registration/Run_Register_FLAIR.csh $1 $2
if($status && ! $ContinueRegFail) then
	echo "SCRIPT: $0 : 00009 : Could not register FLAIR to target atlas."
	exit 1
endif

SKIP_FLAIR:


FREESURFER:
###########################
#	Recon-all
###########################
$PP_SCRIPTS/RunFreesurfer.csh $1 $2
if($status) then
	echo "SCRIPT: $0 : 00005 : Freesurfer failed to complete. Check Freesurfer/${FreesurferVersion}/scripts/recon-all.log."
	exit 1
endif

SKIP_RECON:
#convert the dwi to diffusion - or try
if(! $?DWI) then
	echo "Unable to find DWI in params file, skipping."
	goto SKIP_DWI
endif

$PP_SCRIPTS/Registration/Register_DWI.csh $1 $2
if($status && ! $ContinueRegFail) then
	echo "SCRIPT: $0 : 00010 : Error converting DTI to diffusion."
	exit 1
endif

SKIP_DWI:

if(! $?SWI) then
	decho "Unable to find a SWI in the params file, skipping."
	goto SKIP_SWI
endif

$PP_SCRIPTS/Registration/Run_Register_SWI.csh $1 $2
if($status && ! $ContinueRegFail) then
	echo "SCRIPT: $0 : 00011 : Could not register SWI to target atlas."
	exit 1
endif

SKIP_SWI:

if(! $?ASE) then
	decho "Unable to find a ASE in the params file, skipping."
	goto SKIP_ASE
endif

$PP_SCRIPTS/Registration/Run_Register_ASE.csh $1 $2
if($status && ! $ContinueRegFail) then
	echo "SCRIPT: $0 : 00012 : Could not register ASE to target atlas."
	exit 1
endif

SKIP_ASE:

###########################
#	Create brain masks
###########################
$PP_SCRIPTS/Utilities/Generate_UsedVoxels_Masks.csh $1 $2
if($status) then
	echo "SCRIPT: $0 : 00013 : Unable to generate UsedVoxels Masks."
	exit 1
endif

SKIP_MASK_GEN:

###########################
#	BOLD alignment and registration
###########################
BOLD:
if(! $?BOLD) then
	echo "Unable to find BOLD in params file, skipping."
	goto SKIP_BOLD
endif

$PP_SCRIPTS/Registration/Run_Register_BOLD.csh $1 $2
if($status && ! $ContinueRegFail) then
	echo "SCRIPT: $0 : 00014 : failed to register BOLD."
	exit 1
endif

SKIP_BOLD:

#perform basically the same operations on the ASL
if(! $?ASL) then
	echo "Unable to find ASL in params file, skipping."
	goto SKIP_ASL
endif

$PP_SCRIPTS/Registration/Run_Register_ASL.csh $1 $2
if($status && ! $ContinueRegFail) then
	echo "SCRIPT: $0 : 00015 : failed to register ASL."
	exit 1
endif

SKIP_ASL:

exit 0
