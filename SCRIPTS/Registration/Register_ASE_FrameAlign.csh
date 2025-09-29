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

rm -rf ${SubjectHome}/Anatomical/Volume/ASE_ref ${SubjectHome}/ASE ${SubjectHome}/ASE/Movement
mkdir ${SubjectHome}/ASE
mkdir ${SubjectHome}/ASE/Movement

if(! -e $ScratchFolder/${patid}) mkdir -p $ScratchFolder/${patid}

if(! $?BrainRadius) then
	set BrainRadius = 50
endif

pushd $ScratchFolder/${patid}

	rm -rf ASE_temp
	mkdir ASE_temp

	cd ASE_temp

	ftouch $patid"_xr3d".lst
	ftouch $patid"_anat".lst

	@ Run = 0
	while($#ASE > $Run)	#these are labels if nifti and numbers if dicom
		@ Run++
		mkdir ase${Run}
		cd ase${Run}

			if( -e $SubjectHome/dicom/$ASE[$Run]) then
				if($ASE[$Run]:e == "gz") then
					$RELEASE/niftigz_4dfp -4 $SubjectHome/dicom/$ASE[$Run] ase${Run}_upck
				else
					$RELEASE/nifti_4dfp -4 $SubjectHome/dicom/$ASE[$Run] ase${Run}_upck
				endif
			else
				$RELEASE/dcm_to_4dfp -q -b ase${Run} $SubjectHome/dicom/$dcmroot.$Run.*
				if($status) exit $status

				$RELEASE/unpack_4dfp ase${Run} ase${Run}_upck -nx$ase_nx -ny$ase_ny -V
				if($status) then
					echo "SCRIPT: $0 : 00003 : could not unpack ase"
					exit 1
				endif
			endif

			switch(`grep orientation ase${Run}_upck.4dfp.ifh | awk '{print$3}'`)
				case 2:
					echo "ASE already transverse"
					breaksw
				case 3:
					echo "ASE is coronal, transforming to transverse."
					$RELEASE/C2T_4dfp ase${Run}_upck ase${Run}_upck
					if($status) exit 1
					breaksw
				case 4:
					echo "ASE is sagital, transforming to transverse."
					$RELEASE/S2T_4dfp ase${Run}_upck ase${Run}_upck
					if($status) exit 1
					breaksw
				default:
					echo "SCRIPT: $0 : 00004 : ERROR: UNKNOWN ASE ORIENTATION!!!"
					exit 1
					breaksw
			endsw

			#add this ase run to the list to be included in cross run alignment and anat_ave
			echo ase${Run}/ase${Run}_upck >>		../$patid"_xr3d".lst
			echo ase${Run}/ase${Run}_upck_xr3d >>	../$patid"_anat".lst

			$RELEASE/cross_realign3d_4dfp -n1 -r3 -f -Zcq -v0 ase${Run}_upck
			if($status) then
				echo "SCRIPT: $0 : 00005 : Unable to perform run realignment."
				exit 1
			endif

		cd ..
	end

	cat $patid"_xr3d".lst

	@ Run = 0
	while($#ASE > $Run)
	#outputs the ddat files with the acquisition direction (linear y translation) low passed (<0.1hz)
		@ Run++
		pushd ase$Run
			$RELEASE/mat2dat ase${Run}_upck_xr3d.mat -RD -n0
			if($status) exit 1

			mv *"_xr3d".*dat *"_xr3d.mat" *"xr3d.fd" ${SubjectHome}/ASE/Movement
			pushd ${SubjectHome}/ASE/Movement
				$PP_SCRIPTS/Utilities/compute_fd.csh ase${Run}_upck_xr3d.ddat $BrainRadius 0 0 $FD_Threshold
				if($status) then
					echo "SCRIPT: $0 : 00006 : 	Could not compute fd on ASE data set."
					exit 1
				endif
			popd

		popd
	end

popd

exit 0
