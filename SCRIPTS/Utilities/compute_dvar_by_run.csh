#!/bin/csh

if($#argv < 3) then
	echo "compute_dvar_by_run.csh <params files> <processing params file> <file trailers to use>"
	echo "file trailer to use would be like rsfMRI_uout_bpss_mov_eacsf_vent_wm_gs_resid ."
	echo "It is the part of the filename in Functional/Volume between the session ID_ and the .nii.gz"
	exit 1
endif
#source the subjects params file and the processing parameters
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

set BOLD_image = $3

set SubjectHome = $cwd

decho "		Generating dvar vals..." 

if(! $?PercentFramesRemaining) then
	set PercentFramesRemaining = 0
endif

if(! $?BOLD_Dir) then
	set BOLD_Dir  = "bold"
endif

if(! $?DVAR_Threshold) then
	decho "No DVAR threshold set. Skipping..." $DebugFile
	exit 0
endif

if($DVAR_Threshold == 0) then
	decho "DVAR threshold set to 0. Skipping..." $DebugFile
	exit 0
endif

if( ! -e QC) mkdir QC

if(! $?RunIndex || ! $?BOLD) then
	decho "No BOLD data available, skipping temporal mask computation."
	exit 0
endif

set FinalResolution = $BOLD_FinalResolution

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if(! $?DVAR_Threshold_Type) then
	set DVAR_Threshold_Type = 1	#1) hard threshold. 2)SD threshold
endif


#into scratch!
pushd $ScratchFolder/${patid}/BOLD_temp

	#set the defined voxels mask. Should be the freesrufer brain
	if($NonLinear) then
		if($?day1_path && $?day1_patid) then
			set DFNDM = ${day1_path}/Masks/${day1_patid}_used_voxels_fnirt_${FinalResTrailer}
		else
			set DFNDM = ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}
		endif
	else
		if($?day1_path && $?day1_patid) then
			set DFNDM = ${day1_path}/Masks/${day1_patid}_used_voxels_${FinalResTrailer}
		else
			set DFNDM = ${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}
		endif
	endif

	foreach run($RunIndex)
		cd bold${run}
	
			if(-e bold${run}_${BOLD_image}.4dfp.img) then
				echo "Image is already in 4dfp. Continuing."
			else if(-e {patid}_${BOLD_image}.nii.gz) then
				niftigz_4dfp -4 bold${run}_${BOLD_image}.nii.gz ${patid}_${BOLD_image}
				if($status) exit 1
			else
				nifti_4dfp -4 bold${run}_${BOLD_image}.nii {patid}_${BOLD_image}
				if($status) exit 1
			endif

			niftigz_4dfp -4 $DFNDM dfndm
			if($status) exit 1

			rm -f temp.conc
			touch temp.conc
			echo "number_of_files: 1" >> temp.conc
			echo "	file:${cwd}/bold${run}_${BOLD_image}.4dfp.img" >> temp.conc

			if($DVAR_Threshold_Type == 1) then
				set DVAR_Threshold_Method = "-x${DVAR_Threshold}"
			else if($DVAR_Threshold_Type == 2) then
				set DVAR_Threshold_Method = "-T${DVAR_Threshold}"
			else
				decho "Unknown DVAR threshold method $DVAR_Threshold_Type ."
				exit 1
			endif

			$PP_SCRIPTS/Utilities/run_dvar_4dfp temp.conc -mdfndm -n${skip} ${DVAR_Threshold_Method}
			if($status) exit 1

			mv temp.vals ${SubjectHome}/Functional/TemporalMask/bold${run}_${BOLD_image}.dvar
			mv temp.format ${SubjectHome}/Functional/TemporalMask/bold${run}_${BOLD_image}_dvar.format
			
			#make a binary dvar temporal mask
			format2lst ${SubjectHome}/Functional/TemporalMask/bold${run}_${BOLD_image}_dvar.format | awk '{if($1 == "x") print("0"); else print("1");}' >! ${SubjectHome}/Functional/TemporalMask/bold${run}_${BOLD_image}_dvar.sfbin
			rm dfndm.* ${patid}_${BOLD_image}.4dfp.* temp.*
		cd ..
	end
popd

pushd Functional/TemporalMask
	ftouch ${patid}_${BOLD_image}_dvar.sfbin
	foreach run($RunIndex)
		cat bold${run}_${BOLD_image}_dvar.sfbin >> ${patid}_${BOLD_image}_dvar.sfbin
		if($status) exit 1
	end
popd
exit 0
