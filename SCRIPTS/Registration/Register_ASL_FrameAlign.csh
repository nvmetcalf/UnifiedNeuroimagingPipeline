#!/bin/csh

if($#argv != 2) then
	echo "SCRIPT: $0 : 00000 : incorrect number of arguments"
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


set SubjectHome = $cwd

set AtlasName = $target:t

rm -rf ${SubjectHome}/Anatomical/Volume/ASL_ref ${SubjectHome}/ASL ${SubjectHome}/ASL/Movement
mkdir ${SubjectHome}/ASL
mkdir ${SubjectHome}/ASL/Movement

if(! -e $ScratchFolder/${patid}) mkdir -p $ScratchFolder/${patid}

if(! $?BrainRadius) then
	set BrainRadius = 50
endif

pushd $ScratchFolder/${patid}

	rm -rf ASL_temp
	mkdir ASL_temp

	cd ASL_temp

	ftouch $patid"_xr3d".lst
	ftouch $patid"_anat".lst

	@ Run = 0
	while($#ASL > $Run)	#these are labels if nifti and numbers if dicom
		@ Run++
		mkdir asl${Run}
		cd asl${Run}

			if( -e $SubjectHome/dicom/$ASL[$Run]) then
				if($ASL[$Run]:e == "gz") then
					$RELEASE/niftigz_4dfp -4 $SubjectHome/dicom/$ASL[$Run] asl${Run}_upck
				else
					$RELEASE/nifti_4dfp -4 $SubjectHome/dicom/$ASL[$Run] asl${Run}_upck
				endif
			else
				$RELEASE/dcm_to_4dfp -q -b asl${Run} $SubjectHome/dicom/$dcmroot.$Run.*
				if($status) exit $status

				$RELEASE/unpack_4dfp asl${Run} asl${Run}_upck -nx$asl_nx -ny$asl_ny -V
				if($status) then
					echo "SCRIPT: $0 : 00003 : could not unpack asl"
					exit 1
				endif
			endif

			switch(`grep orientation asl${Run}_upck.4dfp.ifh | awk '{print$3}'`)
				case 2:
					echo "ASL already transverse"
					breaksw
				case 3:
					echo "ASL is coronal, transforming to transverse."
					$RELEASE/C2T_4dfp asl${Run}_upck asl${Run}_upck
					if($status) exit 1
					breaksw
				case 4:
					echo "ASL is sagital, transforming to transverse."
					$RELEASE/S2T_4dfp asl${Run}_upck asl${Run}_upck
					if($status) exit 1
					breaksw
				default:
					echo "SCRIPT: $0 : 00004 : ERROR: UNKNOWN ASL ORIENTATION!!!"
					exit 1
					breaksw
			endsw

			ASL_FRAME_ALIGN:
			#add this asl run to the list to be included in cross run alignment and anat_ave
			echo asl${Run}/asl${Run}_upck >>		../$patid"_xr3d".lst
			echo asl${Run}/asl${Run}_upck_xr3d >>	../$patid"_anat".lst

			$RELEASE/cross_realign3d_4dfp -n1 -r3 -f -Zcq -v0 asl${Run}_upck
			if($status) then
				echo "SCRIPT: $0 : 00005 : Unable to perform run realignment." ${DebugFile}
				exit 1
			endif

		cd ..
	end


	cat $patid"_xr3d".lst

	@ Run = 0
	while($#ASL > $Run)
	#outputs the ddat files with the acquisition direction (linear y translation) low passed (<0.1hz)
		@ Run++
		pushd asl$Run
			$RELEASE/mat2dat asl${Run}_upck_xr3d.mat -RD -n0 -l${MovementLowpass} TR_vol=$ASL_TR[$Run]
			if($status) exit 1

			mv *"_xr3d".*dat *"_xr3d.mat" *"xr3d.fd" ${SubjectHome}/ASL/Movement
			pushd ${SubjectHome}/ASL/Movement
				$PP_SCRIPTS/Utilities/compute_fd.csh asl${Run}_upck_xr3d.ddat $BrainRadius 0 0 $FD_Threshold
				if($status) then
					echo "SCRIPT: $0 : 00006 : 	Could not compute fd on ASL data set." $DebugFile
					exit 1
				endif
				#we want to denote pairs. so starting at the end, set the previous value to the same as the current frame, then skip the previous frame.
				set bin_fd = (`cat asl${Run}_upck_xr3d.ddat.fd.sfbin`)

				@ i = $#bin_fd

				while($i > 0)
					@ k = $i - 1
					set bin_fd[$k] = $bin_fd[$i]
					@ i = $i - 2
				end

				ftouch asl${Run}_upck_xr3d.ddat.fd.sfbin

				foreach frame($bin_fd)
					echo $frame >> asl${Run}_upck_xr3d.ddat.fd.sfbin
				end
			popd

		popd
	end

popd

exit 0
