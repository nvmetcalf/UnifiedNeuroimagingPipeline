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

set concroot	= $ScratchFolder/${patid}/BOLD_temp/${patid}_rsfMRI
set conc	= $concroot.conc

set SubjectHome = $cwd


if( ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz) then
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


pushd $ScratchFolder/${patid}/BOLD_temp
	decho "		Performing temporal bandpass filtering..." $DebugFile

	if($LowFrequency == 0) then
		bandpass_4dfp ${concroot}_uout.conc $BOLD_TR -bh${HighFrequency} -oh2 -EM -F$format
	else
		bandpass_4dfp ${concroot}_uout.conc $BOLD_TR -bl${LowFrequency} -ol2 -bh${HighFrequency} -oh2 -EM -F$format
	endif
	#bandpass_4dfp ${concroot}_uout_resid.conc $BOLD_TR -bh.1 -oh2 -EB -f$format
	#set High_Sigma = `echo $HighFrequency $BOLD_TR | awk '{print((1/$1)/$2)}'`
	#set Low_Sigma = `echo $LowFrequency $BOLD_TR | awk '{print((1/$1)/$2)}'`

	#fslmaths $glm_out -bptf $High_Sigma $Low_Sigma ${SubjectHome}/Functional/Volume/${glm_out}
	if ($status) then
		decho "			FAILED! bandpass_4dfp could not filter signal from ${concroot}_uout_resid_bpss.conc using a TR_vol of $TR_vol: $status" $DebugFile
		exit $status
	endif

	cp ${concroot}_uout_bpss.conc ${concroot}_uout_bpssl${LowFrequency}h${HighFrequency}.conc

	conc2nifti ${concroot}_uout_bpss.conc
	if($status) exit 1

	gzip -f ${concroot}_uout_bpss.nii
	if($status) exit 1

	mv ${concroot}_uout_bpss.nii.gz ${SubjectHome}/Functional/Volume/`basename ${concroot}`_uout_bpss.nii.gz
	if($status) exit 1

popd

exit 0
