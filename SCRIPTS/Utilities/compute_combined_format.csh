#!/bin/csh

source $1 
source $2

if (! -e $1) then
	echo "$1 not found!"
	exit 1
endif

if (! -e $2) then
	echo "$2 not found!"
	exit 1
endif

set SubjectHome = $3
set DVAR_Trailer = $4
set FD_Trailer = $5

if($DVAR_Threshold != 0 && ! -e ${SubjectHome}/Functional/Volume/${patid}_rsfMRI_uout_bpss_resid.nii.gz) then
	decho "	WARNING: BOLD has not been denoised yet, only able to generate FD based temporal mask. Use iterative regression to also use DVAR temporal mask."
	exit 0
endif

#go through each runs generated format(s) and clear out
#frames of runs that are more than X% bad (set in study.cfg)
if($DVAR_Threshold != 0 && $FD_Threshold != 0) then
	echo " Computing DVAR and FD format..."
	#if we are combining the two types, then we need to compute the format
	#for both at the same time (sadly)
	#recompute a combined format from the source values
	#check to see if there are enough frames
	pushd ${SubjectHome}/Functional/Movement
		$RELEASE/format2lst ${SubjectHome}/Functional/TemporalMask/${patid}_${DVAR_Trailer}_dvar.format >! dvar_format.txt
		$RELEASE/format2lst ${SubjectHome}/Functional/TemporalMask/${patid}_${FD_Trailer}_fd.format >! fd_format.txt
		paste dvar_format.txt fd_format.txt  >! temp_dvar_fd
		if($status) exit 1
		
		rm dvar_format.txt fd_format.txt
		decho "Combining..."
		decho "DVAR 	FD"
		cat temp_dvar_fd
		
		cat temp_dvar_fd | awk '{if($1 == "x" || $2 == "x") { out="x";} else {out="+";} printf(out);}' >! temp_dvar_fd_combined
	popd
	
	set format = `cat ${SubjectHome}/Functional/Movement/temp_dvar_fd_combined`
	
	set RunCondensedFormat = `condense $format`
	
	echo $RunCondensedFormat >! ${SubjectHome}/Functional/TemporalMask/${patid}_${DVAR_Trailer}_dvar_fd.format
	
	rm ${SubjectHome}/Functional/Movement/temp_dvar_fd_combined ${SubjectHome}/Functional/Movement/temp_dvar_fd
else
	decho "Only one type of thresholding specified, no combination necessary." ${DebugFile}
	exit 0
endif


exit 0
