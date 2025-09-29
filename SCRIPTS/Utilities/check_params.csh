#!/bin/csh

#check subjects params file for problems
#source the subject params
source $1

set SyntaxVerbosity = 2
set SyntaxStrictness = 0

#source the processing params
source $2

if($?SkipSyntaxCheck) exit 0

    $PP_SCRIPTS/CheckSyntax $1 $SyntaxVerbosity $SyntaxStrictness
    if($status) then

        decho "Error checking syntax for subject parameters." ${DebugFile}
        set Error = 1
        goto ERROR

    endif

	decho "Checking params for completeness..." ${DebugFile}
	if(! $?patid) then
		set Error = 1
		decho "patid does not exist! - cannot continue" ${DebugFile}
		goto ERROR
	endif

	DCM_CHECK:
	if(! $?dcmroot) then
		set Error = 1
		decho "$patid - dcmroot does not exist!" ${DebugFile}
	else if($dcmroot == "") then
		set Error = 1
		decho "$patid - else  not set!" ${DebugFile}
	endif

	PATID_CHECK:
	if(! $?patid) then
		set Error = 1
		decho "$patid - patid not set!" ${DebugFile}
	else if($patid == "") then
		set Error = 1
		decho "$patid - patid not set!" ${DebugFile}
	endif

	TARGET_CHECK:
	if(! $?target) then
		set Error = 1
		decho "$patid - target not set!" ${DebugFile}
	endif

	#Check for anatomicals
	ANATOMY_CHECK:
	if(! $?T1 && (! $?day1_path) && ! -e Freesurfer/${FreesurferVersionToUse}/mri/orig.mgz) then
		set Error = 1
		decho "$patid - no anatomical images detected, nor a day1 session! Unable to perform transformations." ${DebugFile}
	endif

	MULTIDAY_CHECK:

	if($?day1_path) then
		set day1_patid = $day1_path:t
		if(! -e ${day1_path}/Anatomical/Volume/T1/${day1_patid}_T1.nii.gz && ! -e ${day1_path}/Anatomical/Volume/T1/${day1_patid}_T1.nii) then
			set Error = 1
			decho "$patid - day1 subject appears to not actually be a day1 session. Day 1 doesn't have a T1. Check the day1 params file." ${DebugFile}
		endif

		if($day1_patid == $patid) then
			set Error = 1
			decho "$patid - day1_patid equals the same subject as itself!" ${DebugFile}
		endif
	endif

	ERROR:
	if($?Error) then
		echo "${RED_B}There were one or more errors for subject ${patid}.${LF}${NORMAL}"
		goto ERROR_FOUND
	else
		echo No problems detected.
	endif


	exit 0

	ERROR_FOUND:
	exit 1
