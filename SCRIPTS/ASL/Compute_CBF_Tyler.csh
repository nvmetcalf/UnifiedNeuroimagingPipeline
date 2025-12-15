#!/bin/csh

source $1
source $2

@ TypesOfSeq = 0
set PrevSeq = ""
set SubjectHome = $cwd

pushd ASL/Volume

@ SkipFrames = 0

set MinPairsPerPLD = 1

set FinalResolution = $ASL_FinalResolution
set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if($NonLinear) then
	set BrainMask = ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz
else
	set BrainMask = ${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz
endif

if(! $?T1b) then
	set T1b = 1.650
endif

set UniquePLDs = (`echo $ASL_PLD | tr ' ' '\n' | uniq`)
set UniqueTEs = (`echo $ASL_TE | tr ' ' '\n' | uniq`)

if($#UniqueTEs > 1) then
	echo "Cannot have more than 1 TE duration."
	exit 1
endif

set AcquisitionType = `grep "pasl" ${SubjectHome}/dicom/$ASL[1]:r:r".json" | cut -d":" -f2 | cut -d\" -f2 | head -1`

if($AcquisitionType == "") then
	set cASL_flag = "--casl"
else
	set cASL_flag = ""
endif


if(! $?ASL_RPTS && $#ASL == 1) then
	echo "ASL_RPTS not present in params file, but a single ASL image exists."
	exit 1
endif

if($#ASL_TI1 != $#ASL_RPTS) then
	echo "ASL_TI1 length must match ASL_RPTS length, even if ASL_TI1 is all 0's"
	exit 1
endif
#need a look up table for the T1 of blood for different field strengths
#set FieldStrength = `grep "MagneticFieldStrength" ${SubjectHome}/dicom/$ASL[1]:r:r".json" | cut -d":" -f2 | cut -d\" -f2 | head -1`

set ASL_frames = ()
set ASL_frame_PLD = ()
set ASL_frame_TI1 = ()
set MOs = ()

if(! $?ASL_LC_CL) then
	set ASL_LC_CL = 1
	echo "ASL_LC_CL not found, defaulting to Label -> Control order."
endif

if($ASL_LC_CL) then
	set ASL_ct = ""
else
	set ASL_ct = "-ct"
endif

echo $ASL_PLD

set TIs = `echo $ASL_TR | sed 's/ /,/g'`

#extract the M0's and the actual perfusion volumes, skip the dummy if it exists
@ scan_index = 1

while($scan_index <= $#ASL)
	set num_frames = `fslinfo ${patid}_asl${scan_index}_upck_xr3d_dc_atl.nii.gz | grep -w dim4 | awk '{print($2)}'`

	fslmaths ${patid}_asl${scan_index}_upck_xr3d_dc_atl -Tmean ${patid}_asl${scan_index}_upck_xr3d_dc_atl"_mean"
	if($status) exit 1

	#get the mean of the mean ASL frame
	set mean_intensity = `fslstats ${patid}_asl${scan_index}_upck_xr3d_dc_atl_mean -M | awk '{print($1 * 1.15)}'`

	echo "Mean ASL timeseries intensity: " $mean_intensity

	#if the asl timeseries is odd, start asl extraction frames at frame 2

	@ i = 1
	@ j = 0

	if(`echo $num_frames | awk '{print($1%2)}'` == 0) then
		set asl_start = 3
	else
		set asl_start = 2
	endif

	#control the frames we will include for
	@ curr_rpt_frame_count = 1
	@ curr_rpt = $scan_index
	#find frames with a mean intensity greater than the mean + 15%
	while($i <= $num_frames)
		fslroi ${patid}_asl${scan_index}_upck_xr3d_dc_atl ${patid}_asl${scan_index}_upck_xr3d_dc_atl_frame${i} $j 1
		if($status) exit 1
		## detect M0's
		set frame_intensity = `fslstats ${patid}_asl${scan_index}_upck_xr3d_dc_atl_frame${i} -M`
		echo "Current Frame mean intensity: " $frame_intensity

		if(`echo $mean_intensity $frame_intensity | awk '{if($2>=$1) print("1"); else print("0");}'`) then
			set MOs = ($MOs ${patid}_asl${scan_index}_upck_xr3d_dc_atl_frame${i})
		else if($i >= $asl_start && $curr_rpt_frame_count > $SkipFrames) then
			set ASL_frames = ($ASL_frames ${patid}_asl${scan_index}_upck_xr3d_dc_atl_frame${i})
			set ASL_frame_PLD = ($ASL_frame_PLD $ASL_PLD[$curr_rpt])
			set ASL_frame_TI1 = ($ASL_frame_TI1 $ASL_TI1[$curr_rpt])
		endif

		if($i >= $asl_start) then
			@ curr_rpt_frame_count++
		endif

		#see if we have added all of the current pld frames and reset the used pairs
		#so we can start adding from the next pld. This is moslt for single acquisition multipld
		if($?ASL_RPTS) then
			if($curr_rpt_frame_count > `echo $ASL_RPTS[$curr_rpt] | awk '{printf($1 * 2)}'`) then
				@ curr_rpt_frame_count = 1
				@ curr_rpt++
			endif

		endif

		@ i++
		@ j++
	end
	@ scan_index++
end

echo "Perfussion Frames: " $ASL_frames
echo "Detected M0 Frames: " $MOs

#should now have all the M0's in a list and all the rest of the frames in a list
#average the M0's
if($#MOs == 0) then
	#there weren't any MO's detected, so make a fake one based on the label images.
	set i = 1
	foreach frame($ASL_frames)
		if($i) then
			set MOs = ($MOs $frame)
			set i = 0
		else
			set i = 1
		endif
	end

endif

fslmerge -t M0_STACK $MOs
if($status) exit 1

fslmaths M0_STACK -Tmean M0
if($status) exit 1

#put all the label/control frames back together without the M0's
fslmerge -t ASL_STACK $ASL_frames
if($status) exit 1

#put together the FD tmasks
@ i = 1
ftouch ASL_FD.tmask
while($i <= $#ASL)
	#if there are M0's detected, we need to remove them from all the timeseries
	if($#MOs > 0) then
		set num_frames = `wc ${SubjectHome}/ASL/Movement/asl${i}_upck_xr3d.ddat.fd.sfbin | awk '{print($1 - 2)}'`
		cat ${SubjectHome}/ASL/Movement/asl${i}_upck_xr3d.ddat.fd.sfbin | tail -$num_frames >> ASL_FD.tmask
	else
		cat ${SubjectHome}/ASL/Movement/asl${i}_upck_xr3d.ddat.fd.sfbin >> ASL_FD.tmask
	endif

	@ i++
end


#need to make a json for the asl.
ftouch ASL_STACK.json
echo "{" >> ASL_STACK.json

echo   \"PostLabelingDelay\"": [" >> ASL_STACK.json

@ i = 1
set length = `fslinfo ASL_STACK.nii.gz | grep -w dim4 | awk '{print($2)}'`

while($i <= $length)
	if($i != $length) then
		echo "	$ASL_frame_PLD[$i]," >> ASL_STACK.json
	else
		echo "	$ASL_frame_PLD[$i]" >> ASL_STACK.json
	endif
	@ i++
end
echo "]," >> ASL_STACK.json

echo   \"TI1\"": [" >> ASL_STACK.json

@ i = 1
set length = `fslinfo ASL_STACK.nii.gz | grep -w dim4 | awk '{print($2)}'`

while($i <= $length)
	if($i != $length) then
		echo "	$ASL_frame_TI1[$i]," >> ASL_STACK.json
	else
		echo "	$ASL_frame_TI1[$i]" >> ASL_STACK.json
	endif
	@ i++
end
echo "]," >> ASL_STACK.json

echo \"M0Type\": \"Seperate\" >> ASL_STACK.json

echo "}" >> ASL_STACK.json

rm -f *frame*

if($#UniquePLDs > 1 && $AcquisitionType == "") then

	#multi pld,pcasl. Put it through tylers code
	python $PP_SCRIPTS/ASL/weighted_cbf.py $ASL_ct -m0 M0.nii.gz -frame_mask ASL_FD.tmask ASL_STACK.nii.gz ASL_STACK.json ${patid}_MD_PLD_pCASL
	if($status) then
		exit 1
	endif
else if($#UniquePLDs == 1) then
	#single pld, pasl or pcasl. Use matlab

	set AcquisitionType = `grep "MRAcquisitionType" ${SubjectHome}/dicom/$ASL[1]:r:r".json" | cut -d":" -f2 | cut -d\" -f2 | head -1`
	if(`echo $ASL[1] | grep pasl` != "" && $AcquisitionType == "2D") then

		matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${FREESURFER_HOME}/matlab'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));cbf_pasl('ASL_STACK.nii.gz', 'M0.nii.gz', 'ASL_STACK.json', $T1b, $ASL_TR[1], 'ASL_FD.tmask', $ASL_LC_CL, '${patid}_pASL_cbf.nii.gz');end;exit"

	else if(`echo $ASL[1] | grep pasl` != "" && $AcquisitionType == "3D") then
		echo "3D pASL detected. Sequence not supported."
	else
		matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${FREESURFER_HOME}/matlab'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));cbf_3d_pcasl('ASL_STACK.nii.gz', 'M0.nii.gz', 'ASL_STACK.json', $T1b, 'ASL_FD.tmask', $ASL_LC_CL, '${patid}_pCASL_cbf.nii.gz');end;exit"
	endif

endif



popd

exit 0
