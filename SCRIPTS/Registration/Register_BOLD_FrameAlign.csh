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

set SubjectHome = $cwd

set AtlasName = `basename $target`

if (! ${?interleave}) set interleave = ""
if(! $?RunNORDIC) set RunNORDIC = 0

if($?BOLD_MB_Factor) then
	set MB = "-m "$BOLD_MB_Factor
else
	set MB = ""
endif

if(! $?BOLD_SIO) then
	set BOLD_SIO = ""
endif

if(! $?MovementLowpass) then
	set MovementLowpass = 2
endif

rm -r $SubjectHome/Anatomical/Volume/BOLD_ref
mkdir -p $SubjectHome/Anatomical/Volume/BOLD_ref

if(! -e $SubjectHome/Functional/Movement) then
	mkdir -p $SubjectHome/Functional/Movement
endif

if(! -e $ScratchFolder/${patid}) mkdir -p $ScratchFolder/${patid}

pushd $ScratchFolder/${patid}

	rm -rf BOLD_temp
	mkdir BOLD_temp

	cd BOLD_temp

	ftouch $patid"_xr3d".lst
	ftouch $patid"_anat".lst
	
	foreach Run($RunIndex)	#these are labels if nifti and numbers if dicom
		
		mkdir bold${Run}
		cd bold${Run}

			if( -e $SubjectHome/dicom/$BOLD[$Run] || -e $SubjectHome/dicom/$BOLD[$Run]:r) then
				if($BOLD[$Run]:e == "gz") then
					$RELEASE/niftigz_4dfp -4 $SubjectHome/dicom/$BOLD[$Run] bold${Run}_upck -N
				else
					$RELEASE/nifti_4dfp -4 $SubjectHome/dicom/$BOLD[$Run] bold${Run}_upck -N
				endif
				
				if($status) exit $status
				
			else
				#BOLD is in a 2D mosaic, break it into 3D volumes
				decho "RAW data is not BIDS or file ( $SubjectHome/dicom/$BOLD[$Run] ) does not exist." $DebugFile
				
				$RELEASE/dcm_to_4dfp -q -b bold${Run} $SubjectHome/dicom/$dcmroot.$BOLD[$Run].*
				if($status) exit $status
				
				$RELEASE/unpack_4dfp -V bold${Run} bold${Run}_upck -nx$nx -ny$ny
				if(! $status) goto FRAME_ALIGN

				decho "nx or ny is incorrect. Attempting nx nx." ${DebugFile}
				$RELEASE/unpack_4dfp -V bold${Run} bold${Run}_upck -nx$nx -ny$nx
				if(! $status) goto FRAME_ALIGN

				decho "nx or ny is incorrect. Attempting ny ny." ${DebugFile}
				$RELEASE/unpack_4dfp -V bold${Run} bold${Run}_upck -nx$ny -ny$ny
				if($status) then
					decho "Could not break apart mosaic, check nx and ny." ${DebugFile}
					exit 1
				endif
			endif

			if($?NORDIC_BOLD) then
			
				#sanity check to make sure every echo/run has a matching nordic phase
				if($#BOLD != $#NORDIC_BOLD) then
					decho "Number of BOLD runs and number of NORDIC phase images are not the same." $DebugFile
					exit 1
				endif
				niftigz_4dfp -n bold${Run}_upck bold${Run}_upck
				if($status) exit 1
				
				matlab -nodesktop -nosplash -r "addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts')); addpath(genpath('$FREESURFER_HOME/matlab')) ;ARG.noise_volume_last=${NORDIC_BOLD_NoiseVol};ARG.temporal_phase=1;ARG.phase_filter_width=10; NIFTI_NORDIC_V2('bold${Run}_upck.nii.gz','${SubjectHome}/dicom/${NORDIC_BOLD[$Run]}','bold${Run}_upck.nii.gz',ARG);exit" || exit $status
				
				niftigz_4dfp -4 bold${Run}_upck bold${Run}_upck
				if($status) exit 1
				
			else if($RunNORDIC) then
				niftigz_4dfp -n bold${Run}_upck bold${Run}_upck
				if($status) exit 1
				
				matlab -nodesktop -nosplash -r "addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts')); addpath(genpath('$FREESURFER_HOME/matlab'));ARG.magnitude_only = 1; NIFTI_NORDIC_V2('bold${Run}_upck.nii.gz','bold${Run}_upck.nii.gz','bold${Run}_upck.nii.gz',ARG);exit" || exit $status
				
				niftigz_4dfp -4 bold${Run}_upck bold${Run}_upck
				if($status) exit 1
			else
				decho "Using original BOLD timeseries." $DebugFile
			endif
			
			switch(`grep orientation bold${Run}_upck.4dfp.ifh | awk '{print$3}'`)
				case 2:
					echo "BOLD already transverse"
					breaksw
				case 3:
					echo "BOLD is coronal, transforming to transverse."
					$RELEASE/C2T_4dfp bold${Run}_upck bold${Run}_upck
					if($status) exit 1
					breaksw
				case 4:
					echo "BOLD is sagital, transforming to transverse."
					$RELEASE/S2T_4dfp bold${Run}_upck bold${Run}_upck
					if($status) exit 1
					breaksw
				default:
					echo "ERROR: UNKNOWN BOLD ORIENTATION!!!"
					exit 1
					breaksw
			endsw

			if($BOLD_SIO != "") then
				set interleave = "-seqstr $BOLD_SIO"
			else if(`grep "matrix size \[3\]" bold${Run}_upck.4dfp.ifh | awk '{print($5%2)}'` == 1) then	#odd number of slices
				set interleave = ""
			else
				set interleave = "-N"
			endif
			
			$RELEASE/frame_align_4dfp bold${Run}_upck $skip -TR_vol $BOLD_TR -d $epidir $interleave $MB
			
			if($status) then
				decho "Unable to perform within-run frame alignment/slice timing correction." ${DebugFile}
				exit 1
			endif

			$RELEASE/deband_4dfp -n$skip bold${Run}_upck_faln
			if($status) then
				decho "Unable to perform debanding." ${DebugFile}
				exit 1
			endif

		cd ..
	end

	#get a list of uniq phase encoding directions so we can properly register things
	set peds = (`echo $BOLD_ped | tr " " "\n" | sort | uniq`)
	foreach ped($peds)
		ftouch $patid"_func_vols_${ped}.lst"
	end

	set xr3d_Runs = ()
	if($?ME_ScanSets) then
		if (! $?ME_reg) @ ME_reg = 0

		@ k = 1
		while ($k <= $#ME_ScanSets)
			
			set ME_set = (`echo $ME_ScanSets[$k] | sed -r 's/,/ /g'`)
				
			echo $ME_set
			echo $RegisterEcho
			
			echo bold$ME_set[$RegisterEcho]/bold$ME_set[$RegisterEcho]_upck_faln_dbnd >>		$patid"_xr3d.lst"
			
			set scan_ped = $BOLD_ped[$ME_set[$RegisterEcho]]
			echo bold$ME_set[$RegisterEcho]/bold$ME_set[$RegisterEcho]_upck_faln_dbnd_xr3d >>	$patid"_func_vols_${scan_ped}.lst"
			set xr3d_Runs = ($xr3d_Runs $ME_set[$RegisterEcho])
			@ k++
		end
		
	else
		foreach Run($RunIndex)
			#add this bold run to the list to be included in cross run alignment and anat_ave
			echo bold${Run}/bold${Run}_upck_faln_dbnd >>		$patid"_xr3d.lst"
			
			set scan_ped = $BOLD_ped[$Run]
			echo bold${Run}/bold${Run}_upck_faln_dbnd_xr3d >>	$patid"_func_vols_${scan_ped}.lst"
		end
		
		set xr3d_Runs = ($RunIndex)
	endif
	
	echo $xr3d_Runs
	
	cat $patid"_xr3d".lst
	
	#perform bias field correction before cross realignment
	foreach Run($xr3d_Runs)
		decho "Bias correcting run: $Run"
		pushd bold${Run} # compute bias field for each run
			
			#make a run average without the hyperintense frames
			set NumFrames = `cat bold${Run}_upck_faln_dbnd.4dfp.ifh | grep "matrix size \[4\]" | gawk '{print $NF-1}'`
			actmapf_4dfp x${NumFrames}+ bold${Run}_upck_faln_dbnd -aavg
			if($status) exit 1
			
			nifti_4dfp -n bold${Run}_upck_faln_dbnd_avg bold${Run}_upck_faln_dbnd_avg
			if($status) exit 1
			
			bet bold${Run}_upck_faln_dbnd_avg bold${Run}_upck_faln_dbnd_avg_brain -f 0.3
			if($status) exit 1

			$FSLDIR/bin/fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -B -o bold${Run}_upck_faln_dbnd_avg_brain bold${Run}_upck_faln_dbnd_avg_brain
			if($status) exit 1
			
			niftigz_4dfp -4 bold${Run}_upck_faln_dbnd_avg_brain_restore bold${Run}_upck_faln_dbnd_avg_brain_restore 
			if($status) exit 1
			

			extend_fast_4dfp -G bold${Run}_upck_faln_dbnd_avg bold${Run}_upck_faln_dbnd_avg_brain_restore bold${Run}_upck_faln_dbnd_avg_BF
			if($status) exit 1
			
			niftigz_4dfp -n bold${Run}_upck_faln_dbnd_avg_BF bold${Run}_upck_faln_dbnd_avg_BF 
			if($status) exit 1
			
			imgopr_4dfp -pbold${Run}_upck_faln_dbnd_BC bold${Run}_upck_faln_dbnd bold${Run}_upck_faln_dbnd_avg_BF
			if($status) exit 1
			
			mv bold${Run}_upck_faln_dbnd_BC.4dfp.ifh bold${Run}_upck_faln_dbnd.4dfp.ifh
			mv bold${Run}_upck_faln_dbnd_BC.4dfp.hdr bold${Run}_upck_faln_dbnd.4dfp.hdr
			mv bold${Run}_upck_faln_dbnd_BC.4dfp.img bold${Run}_upck_faln_dbnd.4dfp.img
			
			rm bold${Run}_upck_faln_dbnd_avg_brain.* bold${Run}_upck_faln_dbnd_avg.4dfp.*
			
		popd
	end
	
	#Avi says the movement between echos is measurement error. Only do
	#the first echo for each ME run
 	$RELEASE/cross_realign3d_4dfp -n$skip -qv0 -l$patid"_xr3d.lst"
 	if($status) then
 		decho "Unable to perform across run realignment." ${DebugFile}
 		exit 1
 	endif

	foreach Run($xr3d_Runs)
		#outputs the ddat files with the acquisition direction (linear y translation) low passed (<0.1hz) 
		$RELEASE/mat2dat bold${Run}/bold${Run}_upck_faln_dbnd_xr3d.mat -I -R -D -n$skip -l$MovementLowpass TR_vol=$BOLD_TR
		if($status) exit 1
		$RELEASE/mat2dat bold${Run}/bold${Run}_upck_faln_dbnd_xr3d -I
		if($status) exit 1
		mv bold${Run}/*"_xr3d".*dat bold${Run}/*"_xr3d.mat" bold${Run}/*_upck_faln_dbnd_xr3d_dat.* ${SubjectHome}/Functional/Movement
	end
	
	######################################
	# make EPI first frame (Anatomical) image
	######################################
	foreach ped($peds)
		decho $patid"_func_vols_${ped}.lst" $DebugFile
		cat $patid"_func_vols_${ped}.lst" >> $DebugFile
	
		#######################################
		# make func_vols_ave using actmapf_4dfp
		#######################################
		$RELEASE/conc_4dfp ${patid}_func_vols_${ped} -l$patid"_func_vols_${ped}.lst"
		if ($status) exit $status

		set  format = `conc2format ${patid}_func_vols_${ped}.conc $skip`
		echo $format >! ${patid}_func_vols_${ped}.format
		
		#compute initial bold_ref for masking generation
		$RELEASE/actmapf_4dfp $format ${patid}_func_vols_${ped}.conc -ainit_ave
		if ($status) exit $status
			
		niftigz_4dfp -n ${patid}_func_vols_${ped}_init_ave ${patid}_func_vols_${ped}_init_ave
		if($status) exit 1
			
		#generate brain mask for the unfiltered initial bold anatomy 
		bet ${patid}_func_vols_${ped}_init_ave ${patid}_func_vols_${ped}_init_ave_brain -m -R
		if($status) exit 1
			
		niftigz_4dfp -4 ${patid}_func_vols_${ped}_init_ave_brain_mask ${patid}_func_vols_${ped}_init_ave_brain_mask
		if($status) exit 1
			
		#compute the, relatively, high noise frames on the realigned bold timeseries
		$RELEASE/run_dvar_4dfp ${patid}_func_vols_${ped}.conc -m${patid}_func_vols_${ped}_init_ave_brain_mask -n$skip -T2
		if ($status) then
			niftigz_4dfp -4 ${patid}_func_vols_${ped}_init_ave ${patid}_func_vols_${ped}_ave
			if($status) exit 1
			goto FINISH
		endif
		set format = `cat ${patid}_func_vols_${ped}.format`
		set str = `format2lst -e $format | gawk '{k=0;l=length($1);for(i=1;i<=l;i++)if(substr($1,i,1)=="x")k++;}END{print k, l;}'`
		echo $str[1] out of $str[2] frames fail dvar criterion $anat_avet
		@ j = $str[2] - $str[1]; #if ($j < $min_frames) exit 1	# require at least $min_frames with dvar < $anat_avet to proceed
		
		#create the low noise bold reference anatomy image
		$RELEASE/actmapf_4dfp ${patid}_func_vols_${ped}.format ${patid}_func_vols_${ped}.conc -aave
		if ($status) exit $status
			
		FINISH:
		ifh2hdr -r2000 ${patid}_func_vols_${ped}_ave
		if ($status) exit $status
		
		niftigz_4dfp -n ${patid}_func_vols_${ped}_ave $SubjectHome/Anatomical/Volume/BOLD_ref/${patid}_BOLD_ref_distorted_${ped}
		if($status) then
			decho "Could not generate BOLD anatomy reference for phase encoding direction ${ped}." $DebugFile
			exit 1
		endif
	end
	
popd

exit 0
