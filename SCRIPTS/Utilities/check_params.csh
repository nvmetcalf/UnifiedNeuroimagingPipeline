#!/bin/csh

#check subjects params file for problems
#source the subject params
source $1

set SyntaxVerbosity = 2
set SyntaxStrictness = 0

#source the processing params
source $2

    #Run dos2unix on the file to strip any windows characters which might be there for some reason.
    dos2unix $1 -o -s -F

    #check subjects params file for problems
    #First check to see if there are any csh syntax error or parameters that do not adhere to the rules in:
    #TemplateParams.json.
    decho "Checking params file syntax for ${1}" ${DebugFile}
    $PP_SCRIPTS/fsl/fslpython/bin/python3 $PP_SCRIPTS/python3/CheckParamsSyntax.py $1 $SyntaxVerbosity $SyntaxStrictness
    if($status) then
        switch ( $status )
            case 1:
                decho "Could not find regex template file." ${DebugFile}
            breaksw
            case 2:
                decho "csh syntax error detected." ${DebugFile}
            breaksw
            case 3:
                decho "Could not find params file: %s." ${1} ${DebugFile}
            breaksw
            case 4:
                decho "Syntax error detected." ${DebugFile}
            breaksw
            case 5:
                decho "File arguments incorrectly supplied to CheckParamsSyntax.py, check check_params.csh" ${DebugFile}
            breaksw
            case 6:
                decho "Unable to load rule module." ${DebugFile}
            breaksw
            case 7:
                decho "Required parameter not found." ${DebugFile}
            breaksw
            case 8:
                decho "File path or symlink does not exist." ${DebugFile}
            breaksw
            case 9:
                decho "Parameter boundry specification JSON does not exist." ${DebugFile}
            breaksw
            case 10:
                decho "Parameter not in bounds." ${DebugFile}
            breaksw
        endsw
        
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
	if(! $?mprs && (! $?day1_path || ! $?day1_patid) && ! -e Freesurfer/mri/orig.mgz) then
		set Error = 1
		decho "$patid - no anatomical images detected, nor a day1 session! Unable to perform transformations." ${DebugFile}
	endif

	MULTIDAY_CHECK:

	if($?day1_path && ! $?day1_patid) then
		set Error = 1
		decho "$patid - day1_path set, but day1_patid is not set in params file!" ${DebugFile}
	else if(! $?day1_path && $?day1_patid) then
		set Error = 1
		decho "$patid - day1_path is not set, but day1_patid is set in params file!" ${DebugFile}
	else if($?day1_path && $?day1_patid) then
		if(! -e ${day1_path}/Anatomical/Volume/T1/${day1_patid}_T1_111.nii.gz) then
			set Error = 1
			decho "$patid - day1 subject appears to not actually be a day1 session. Check the day1 params file." ${DebugFile}
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
