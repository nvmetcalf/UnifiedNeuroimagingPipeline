#!/bin/csh

source $1
source $2

@ TypesOfSeq = 0
set PrevSeq = ""
set SubjectHome = $cwd

pushd BASL_test
if(! $?NativeMetric) then
	set NativeMetric = 0
endif

@ SkipFrames = 0

set MinPairsPerPLD = 1

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if($NonLinear) then
	set BrainMask = ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz
else
	set BrainMask = ${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz
endif

set Trailer = ""

BASL:
#make a list of T1b's based on field strength
#make list of T1's based on field strength
#allow for inversion efficiency (alpha) depending on sequence type
#need to precensor ASL timeseries based on FD
#determine if there is a M0 image in the timeseries via within brain mean - done
#collect PLDs - done
#for  --asl2struc, use identity matrix as the data will already be in target space - done
#collect TE - done

#multi PLD = --iaf=tc, else --iaf=diff

#multipld m0's, register together, then average.
#if no m0, average the control images



set PLDs = ()
set TEs = ()

set UniquePLDs = (`echo $ASL_PLD | uniq`)
set UniqueTEs = (`echo $ASL_TE | uniq`)

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

#need a look up table for the T1 of blood for different field strengths
#set FieldStrength = `grep "MagneticFieldStrength" ${SubjectHome}/dicom/$ASL[1]:r:r".json" | cut -d":" -f2 | cut -d\" -f2 | head -1`

set ASL_frames = ()
set MOs = ()

if($#UniquePLDs == 1) then
	#have as many scans as we have PLD and they are all the same
	set PLDs = `echo $ASL_PLD | sed 's/ /,/g'`
	set PLD_tag = ""
	set RPTS_tag = ""
else if($#ASL == $#ASL_PLD) then
	#make a list of the PLDs
	set PLDs = `echo $ASL_PLD | sed 's/ /,/g'`
	set PLD_tag = "--ibf rpt"
	@ i = 1
	set RPTS_tag = "--rpts 1"
	while($i < $#ASL_PLD)
		set RPTS_tag = $RPTS_tag`echo ",1"`
	end
else
	set PLDs = `echo $ASL_PLD | sed 's/ /,/g'`
	set PLD_tag = "--ibf rpt"
	@ i = 1
	if($?ASL_RPTS) then
		#get the lowest number of PLD repeats so we can keep them even when combining. In frames.
		set CommonPLD_RPT = `echo $ASL_RPTS | sed 's/ /\n/g' | sort -u | head -1 | awk '{print($1*2)}'`
		#same, but in pairs
		set CommonPLD_RPT_reps = `echo $ASL_RPTS | sed 's/ /\n/g' | sort -u | head -1 | awk '{print($1)}'`
		set CommonPLD_RPT_reps = `echo $CommonPLD_RPT_reps $SkipFrames | awk '{print($1 - ($2/2))}'`
		set RPTS = ()

		foreach pld($ASL_PLD)
			set RPTS = ($RPTS $CommonPLD_RPT_reps)
		end
		set RPTS = `echo $RPTS | sed 's/ /,/g'`

		set RPTS_tag = "--rpts "`echo $RPTS | sed 's/ /,/g'`
	else
		set RPTS_tag = ""
	endif
endif

echo $PLDs
echo $RPTS_tag

set TIs = `echo $ASL_TR | sed 's/ /,/g'`

#should only have one TE...
set TEs = $UniqueTEs

#extract the M0's and the actual perfusion volumes, skip the dummy if it exists
@ scan_index = 1

while($scan_index <= $#ASL)
	set num_frames = `fslinfo ${patid}_asl${scan_index}_upck_xr3d_dc_atl.nii.gz | grep -w dim4 | awk '{print($2)}'`

	fslmaths ${patid}_asl${scan_index}_upck_xr3d_dc_atl -Tmean ${patid}_asl${scan_index}_upck_xr3d_dc_atl"_mean"
	if($status) exit 1

	#get the mean of the mean ASL frame
	set mean_intensity = `fslstats ${patid}_asl${scan_index}_upck_xr3d_dc_atl_mean -M | awk '{print($1 * 1.15)}'`

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
	@ curr_rpt = 1
	#find frames with a mean intensity greater than the mean + 15%
	while($i < $num_frames)
		fslroi ${patid}_asl${scan_index}_upck_xr3d_dc_atl ${patid}_asl${scan_index}_upck_xr3d_dc_atl_frame${i} $j 1
		if($status) exit 1
		## detect M0's
		set frame_intensity = `fslstats ${patid}_asl${scan_index}_upck_xr3d_dc_atl_frame${i} -M`
		if(`echo $mean_intensity $frame_intensity | awk '{if($2>=$1) print("1"); else print("0");}'`) then
			set MOs = ($MOs ${patid}_asl${scan_index}_upck_xr3d_dc_atl_frame${i})
		else if($i >= $asl_start && $curr_rpt_frame_count <= $CommonPLD_RPT && $curr_rpt_frame_count > $SkipFrames) then
			set ASL_frames = ($ASL_frames ${patid}_asl${scan_index}_upck_xr3d_dc_atl_frame${i})
		endif

		if($i >= $asl_start) then
			@ curr_rpt_frame_count++
		endif

		#see if we have added all of the current pld frames and reset the used pairs
		#so we can start adding from the next pld
		if($curr_rpt_frame_count > `echo $ASL_RPTS[$curr_rpt] | awk '{printf($1 * 2)}'`) then
			@ curr_rpt_frame_count = 1
			@ curr_rpt++
		endif

		@ i++
		@ j++
	end
	@ scan_index++
end

echo $ASL_frames

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
pause
#compute CBF
echo oxford_asl -i ASL_STACK -c M0 --asl2struc $FSLDIR/etc/flirtsch/ident.mat --bolus 1.8 $PLD_tag $RPTS_tag --plds $PLDs --iaf ct --csf $cASL_flag --cmethod voxel --tr $ASL_TR[1] -o basl_cbf --bat 1.3 --t1 1.3 --t1b 1.65 --alpha 0.85 --spatial

oxford_asl -i ASL_STACK -c M0 --te $TEs[1] --asl2struc $FSLDIR/etc/flirtsch/ident.mat --bolus 1.8 $PLD_tag $RPTS_tag --plds $PLDs --iaf tc --csf $cASL_flag --cmethod voxel --tr $ASL_TR[1] -o basl_cbf --bat 1.3 --t1 1.3 --t1b 1.65 --alpha 0.85 --fixbolus --spatial
if($status) exit 1

#--tis $TIs
popd
exit 0

# identity matrix = $FSLDIR/etc/flirtsch/ident.mat
oxford_asl -i ASL_STACK --asl2struc $FSLDIR/etc/flirtsch/ident.mat --te $ASL_TE

set ASL = ("108342_WMH-MRI-20250214_tgse_pcasl_xa30_5delay_2.5mm_iso_20250214112844_34.nii.gz")		# ASL Images
set ASL_TE = (24.3)	#TE of the ASL sequence in milliseconds.
set ASL_PLD = (1.5)	#PostLabelingDelay (pcASL) or TI2 (pASL)
set ASL_TI1 = (0)	#TI1 (pASL). 0 if the sequence is pcASL
set ASL_TR = (4.3)	#TR of the sequence.


set BASE_PATH="/data/nil-bluearc/ances_prod/Projects/ABCDSU19/Analyis/basil_multipld"
set MPRAGE_FILENAME="Accelerated_Sagittal_MPRAGE_(MSV21)_.nii"
set CALIBRATION_FILENAME="Axial_3DpCASL_M0_-_Gain_.1_.nii"

    fsl_anat -i ${BASE_PATH}/${sub}/${MPRAGE_FILENAME} -o ${BASE_PATH}/${sub}/struc
    oxford_asl -i ${BASE_PATH}/${sub}/input.nii.gz --iaf ct --ibf rpt --casl --bolus 1.8 --rpts 1,1,1,1,1 --tis 3.06,3.3,3.8,4.3,4.8 -s ${BASE_PATH}/${sub}/${MPRAGE_FILENAME} --fslanat ${BASE_PATH}/${sub}/struc.anat -c ${BASE_PATH}/${sub}/${CALIBRATION_FILENAME} --cmethod voxel --tr 6.5 --cgain 10 -o ${BASE_PATH}/${sub} --bat 1.3 --t1 1.3 --t1b 1.65 --alpha 0.85 --spatial --fixbolus --mc

