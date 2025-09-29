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



############################################
# make movement regressors for each BOLD run
############################################
pushd Functional/Movement

	ftouch movement_reg_images.lst
	if($status) exit 1

	@ k = 1

	set regr_output = ${SubjectHome}/Functional/Regressors/${patid}_Movement_regressors.dat
	rm -f $regr_output
	touch $regr_output

	while ($k <= $#FCProcIndex)
		set xr3d_mat = ""
		if($?ME_ScanSets) then

			set Set_Indices = (`echo $ME_ScanSets[${FCProcIndex[$k]}] | sed -e 's/,/ /g'`)
			echo $Set_Indices

			set xr3d_mat = bold$Set_Indices[$RegisterEcho]_upck_faln_dbnd_xr3d

		else
			set xr3d_mat = bold${FCProcIndex[$k]}_upck_faln_dbnd_xr3d
		endif

		set file = ${xr3d_mat}_dat
		echo $file >> movement_reg_images.lst
		@ k++
	end
	cat movement_reg_images.lst

	conc_4dfp ${patid}_upck_faln_dbnd_xr3d_dat -lmovement_reg_images.lst -w
	if($status) exit 1

	bandpass_4dfp ${patid}_upck_faln_dbnd_xr3d_dat.conc $BOLD_TR -bh${HighFrequency} -oh2 -bl${LowFrequency} ol2 -EM -F$format
	if($status) exit 1

	4dfptoascii   ${patid}_upck_faln_dbnd_xr3d_dat.conc    $regr_output
	if($status) exit 1


popd

exit 0
