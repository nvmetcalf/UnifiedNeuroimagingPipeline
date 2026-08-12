#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

if(! $?BOLD_FinalResolution) then
	set FinalResTrailer = 2
else
	set FinalResTrailer = $BOLD_FinalResolution
endif

#set the temporal mask folder
if($?FD_Threshold && $FD_Threshold != 0) then
	set FD_File = "'${SubjectHome}/Functional/Movement/${patid}_all_bold_runs.fd'"
else
	set FD_File = "[]"
endif

if($?DVAR_Threshold && $DVAR_Threshold != 0) then
	set DVAR_File = "'${SubjectHome}/Functional/TemporalMask/${patid}_rsfMRI_uout_bpss_mov_eacsf_vent_wm_gs_resid.nii.gz.dvar'"
else
	set DVAR_File = "[]"
endif

if($target != "") then
	set AtlasName = `basename $target`
else
	set AtlasName = T1
endif

set Residual_Trailer = ""
if(${ComputeMOVERegressor}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_mov`
	else
		set Residual_Trailer = "mov"
	endif
endif

if(${ComputeEACSFRegressor}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_eacsf`
	else
		set Residual_Trailer = "eacsf"
	endif
endif

if(${ComputeVENT}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_vent`
	else
		set Residual_Trailer = "vent"
	endif
endif

if(${ComputeWM}) then
	if($Residual_Trailer != "") then
		set Residual_Trailer = `echo ${Residual_Trailer}_wm`
	else
		set Residual_Trailer = "wm"
	endif
endif

if(${ComputeWBRegressor}) then
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

#goto NOISE


#do movement QC
if( $?RunIndex) then
	pushd ${SubjectHome}/Functional/Movement
		#generate movement timeseries for each axis.
			matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/QC'));DoMovementQC;end;exit"
		mv *.pdf ${SubjectHome}/QC
		if($status) exit 1
	popd
	pushd ${SubjectHome}/Functional/TemporalMask
		#make our stacked format binary files for comparison later
		
		ftouch ${SubjectHome}/QC/${patid}_BOLD_FD_Thresholding_frame_count.txt
		if($status) exit 1
		
		echo "Run#,#BadFrames,#GoodFrames,%Remaining,SecondsRemaining" >> ${SubjectHome}/QC/${patid}_BOLD_FD_Thresholding_frame_count.txt
		
		if($DVAR_Threshold != 0) then
			ftouch ${SubjectHome}/QC/${patid}_BOLD_DVAR_Thresholding_frame_count.txt
			if($status) exit 1
			
			echo "Run#,#BadFrames,#GoodFrames,%Remaining,SecondsRemaining" >> ${SubjectHome}/QC/${patid}_BOLD_DVAR_Thresholding_frame_count.txt
		
			ftouch ${SubjectHome}/QC/${patid}_BOLD_FD_DVAR_Thresholding_frame_count.txt
			echo "Run#,#BadFrames,#GoodFrames,%Remaining,SecondsRemaining" >> ${SubjectHome}/QC/${patid}_BOLD_FD_DVAR_Thresholding_frame_count.txt
		
		endif
		
		#compute how many frames were censored based on FD and by DVAR independently.
		
		foreach run($RunIndex) 
			cat bold${run}_upck_faln_dbnd_xr3d.ddat.fd.sfbin | awk -v TR=${BOLD_TR} -v RunIndex=${run} -f $PP_SCRIPTS/Utilities/frame_count.awk >> ${SubjectHome}/QC/${patid}_BOLD_FD_Thresholding_frame_count.txt
			if($status) exit 1
			
			if($DVAR_Threshold != 0 && -e bold${run}_upck_faln_dbnd_xr3d_dc_atl_uout_bpss_${Residual_Trailer}_dvar.sfbin) then
				cat bold${run}_upck_faln_dbnd_xr3d_dc_atl_uout_bpss_${Residual_Trailer}_dvar.sfbin | awk -v TR=${BOLD_TR} -v RunIndex=${run} -f $PP_SCRIPTS/Utilities/frame_count.awk >> ${SubjectHome}/QC/${patid}_BOLD_DVAR_Thresholding_frame_count.txt
				
				if($status) exit 1
				#combine both sfbins and output the frames remaining after combining both
				paste bold${run}_upck_faln_dbnd_xr3d.ddat.fd.sfbin bold${run}_upck_faln_dbnd_xr3d_dc_atl_uout_bpss_${Residual_Trailer}_dvar.sfbin | awk '{if($1 && $2) print("1"); else print("0");}' | awk -v TR=${BOLD_TR} -v RunIndex=${run} -f $PP_SCRIPTS/Utilities/frame_count.awk >> ${SubjectHome}/QC/${patid}_BOLD_FD_DVAR_Thresholding_frame_count.txt
				
				if($status) exit 1
			endif			
		end
	popd
	#extract rms movement
	ftouch ${SubjectHome}/QC/RMS_movements.txt
	@ i = 1
	while($i <= $#RunIndex)
		tail -1 ${SubjectHome}/Functional/Movement/bold${i}_upck_faln_dbnd_xr3d.ddat >> ${SubjectHome}/QC/RMS_movements.txt
		@ i++
	end

else
	echo "BOLD realignment not computed. Skipping movement plots."
endif
