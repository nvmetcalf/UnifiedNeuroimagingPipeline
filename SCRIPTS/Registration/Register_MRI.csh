#!/bin/csh

if (${#argv} < 1) then
	echo "usage:	"$program" params_file processing_params_file"
	exit 1
endif

if (! -e $1) then
	echo "$1 not found!"
	exit 1
endif

if (! -e $2) then
	echo "$2 not found!"
	exit 1
endif

#get all the participant and processing variables
source $1
source $2

if(! $?day1_patid) set day1_patid = ""
if(! $?day1_path) set day1_path = ""

set SubjectHome = $cwd

if(! $?mprs && -e Freesurfer/mri/nu.mgz) then
	decho "No T1 set in params file, but freesurfer has an orig. Using the orig..." $DebugFile
	
	mri_convert Freesurfer/mri/nu.mgz dicom/${patid}_T1.nii.gz
	if($status) exit 1
	set mprs = "${patid}_T1_orig.nii.gz"
else
	set mprs = ""
endif

if(! $?tse) set tse = ""
if(! $?flair) set flair = ""
if(! $?SWI) set SWI = ""

if($day1_patid != "" || $day1_path != "") then
	decho "This session is part of a multisession dataset. Skipping anatomical processing and alignment and preparing first session masks for this session."
	$PP_SCRIPTS/Utilities/Prepare_Multisession.csh $1 $2
	if($status) then
		decho "Unable to prepare the current session as a multisession." $DebugFile
		exit 1
	endif
	goto BOLD_PROC
endif

ANATOMICAL:

if($#argv > 2) goto $3

#goto MASK
######################
#	T1
######################
if(! $?mprs || $#mprs == 0 ) then
	decho "Unable to find T1 image in params file, unable to continue." ${DebugFile}
	exit 1
endif

$PP_SCRIPTS/Registration/Register_T1.csh $1 $2 $SubjectHome
if($status) then
	decho "Could not register T1 to target atlas." $DebugFile
	exit 1
endif

#convert the dwi to diffusion - or try
if($?DWI && ! $?day1_patid && ! $?day1_path) then
	$PP_SCRIPTS/Registration/Register_DWI.csh $1 $2
	if($status) then
		decho "Error converting DTI to diffusion." $DebugFile
		exit 1
	endif
endif
SKIP_DWI:

#################
#	T2
#################

if($#tse == 0) then
	decho "Unable to find a T2 in the params file, skipping."
	goto SKIP_T2
endif

$PP_SCRIPTS/Registration/Register_T2.csh $1 $2 $SubjectHome
if($status) then
	decho "Could not register T2 to target atlas." $DebugFile
	exit 1
endif

SKIP_T2:

###########################
#	flair
###########################
if($#flair == 0) then
	decho "Unable to find a FLAIR in the params file, skipping."
	goto SKIP_FLAIR
endif

$PP_SCRIPTS/Registration/Register_FLAIR.csh $1 $2 $SubjectHome
if($status) then
	decho "Could not register FLAIR to target atlas." $DebugFile
	exit 1
endif

SKIP_FLAIR:

if($#SWI == 0) then
	decho "Unable to find a SWI in the params file, skipping."
	goto SKIP_SWI
endif

$PP_SCRIPTS/Registration/Register_SWI.csh $1 $2 $SubjectHome
if($status) then
	decho "Could not register SWI to target atlas." $DebugFile
	exit 1
endif

SKIP_SWI:

###########################
#	Recon-all
###########################
$PP_SCRIPTS/RunFreesurfer.csh $1 $2
if($status) then
	decho "Freesurfer failed to complete. Check Freesurfer/scripts/recon-all.log." $DebugFile
	exit 1
endif

SKIP_RECON:

if($NonLinear) then
	$PP_SCRIPTS/Registration/Register_T1_NonLinear.csh $1 $2 $SubjectHome
	if($status) then
		decho "Unable to Nonlinearly Register T1 to target." $DebugFile
		exit 1
	endif
	
	if($#tse != 0) then
		$PP_SCRIPTS/Registration/Register_T2_NonLinear.csh $1 $2 $SubjectHome
		if($status) then
			decho "Unable to create Nonlinearly Register T2 to target." $DebugFile
			exit 1
		endif
	endif
	
	if($#flair != 0) then
		$PP_SCRIPTS/Registration/Register_FLAIR_NonLinear.csh $1 $2 $SubjectHome
		if($status) then
			decho "Unable to create Nonlinearly Register FLAIR to target." $DebugFile
			exit 1
		endif
	endif
	
	if($#SWI != 0) then
		$PP_SCRIPTS/Registration/Register_SWI_NonLinear.csh $1 $2 $SubjectHome
		if($status) then
			decho "Unable to create Nonlinearly Register SWI to target." $DebugFile
			exit 1
		endif
	endif
endif

###########################
#	Create brain masks
###########################
$PP_SCRIPTS/Utilities/Generate_UsedVoxels_Masks.csh $1 $2 $SubjectHome
if($status) then
	decho "Unable to generate UsedVoxels Masks." $DebugFile
	exit 1
endif

###########################
#	BOLD alignment and registration
###########################
BOLD_PROC:
if($?BOLD && $?RunIndex) then
	$PP_SCRIPTS/Registration/Register_BOLD_FrameAlign.csh $1 $2 $SubjectHome
	if($status) then
		decho "Unable to perform BOLD frame alignment and normalization." $DebugFile
		exit 1
	endif

	$PP_SCRIPTS/Registration/Register_BOLD_Transform.csh $1 $2 $SubjectHome
	if($status) then
		decho "Unable to perform BOLD atlas transformations." $DebugFile
		exit 1
	endif

endif

#perform basically the same operations on the ASL
ASL_ALIGN:
if($?ASL) then
	###########################
	#	ASL alignment
	###########################
	$PP_SCRIPTS/Registration/Register_ASL_FrameAlign.csh $1 $2 $SubjectHome
	if($status) then
		decho "Unable to perform ASL frame alignment" $DebugFile
		exit 1
	endif

	$PP_SCRIPTS/Registration/Register_ASL_Transform.csh $1 $2 $SubjectHome
	if($status) then
		decho "Unable to perform ASL atlas transformations." $DebugFile
		exit 1
	endif
endif

exit 0
