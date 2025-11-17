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

set FM_Suffix = $3

set dwell = ($4)
set ped = ($5)
set fm = ($6)
set Reg_Target = $7

if($#argv > 7) then
	set CostFunction = $8
else
	set CostFunction = corratio
endif


set SubjectHome = $cwd

rm -rf ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
mkdir ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
pushd ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}

	#get the total readout for the AP image. MUST be the same for AP and PA. They also need to be the same dimensions
	ftouch datain.txt

	set sefm_list = ()
	set all_sefm = ()
	@ j = 1
	while($j <= $#fm)
		set TotalReadout = `cat ${SubjectHome}/dicom/$fm[$j]:r:r".json" | grep TotalReadoutTime | cut -d":" -f2 | cut -d"," -f1`
		set curr_ped = `grep \"PhaseEncodingDirection\" ${SubjectHome}/dicom/$fm[$j]:r:r".json" | cut -d: -f2 | cut -d, -f1 | sed 's/\"//g'`

		set all_sefm = ($all_sefm $curr_ped)

		if($curr_ped == "j-") then
			set curr_ped = "0 -1 0"
		else if($curr_ped == "j") then
			set curr_ped = "0 1 0"
		else if($curr_ped == "i-") then
			set curr_ped = "-1 0 0"
		else if($curr_ped == "i") then
			set curr_ped = "1 0 0"
		endif

		echo "$curr_ped $TotalReadout" >> datain.txt
		set sefm_list = ($sefm_list ${SubjectHome}/dicom/$fm[$j])

		@ j++
	end

	set num_unique_sefm = (`echo $all_sefm | tr " " "\n" | sort -u`)

	if($#num_unique_sefm < 2) then
		echo "SCRIPT: $0 : 00003 : Not enough unique phase encoding directions to perform topup..."
		echo "Set directions: $all_sefm"
		exit 1

	endif

	set NumSlices = `fslinfo ${SubjectHome}/dicom/$DTI[1] | grep -w dim3 | awk '{print$2}'`

	if(`echo $NumSlices | awk '{print($1%2)}'`) then	#odd num slices
		set TopupConfig = $PP_SCRIPTS/HCP/global/config/b02b0_noresample.cnf
	else
		set TopupConfig = $PP_SCRIPTS/HCP/global/config/b02b0.cnf
	endif

	#need to register all the maps to a common space...
	#find the one with the highest resolution and that becomes the target
	@ curr_max = 0
	set target_fm = ""
	foreach fm($sefm_list)
		@ dim = `fslinfo $fm | grep dim1 | head -1 | awk '{print $2}'` * `fslinfo $fm | grep dim2 | head -1 | awk '{print $2}'` * `fslinfo $fm | grep dim4 | head -1 | awk '{print $2}'`

		if($dim > $curr_max) then
			set target_fm = $fm
			@ curr_max = $dim
		endif
	end

	echo "Registering field maps to: $target_fm"

	set reg_sefm_list = ()

	foreach fm($sefm_list)
		if($target_fm == $fm) then
			set reg_sefm_list = ($reg_sefm_list $fm)
			continue
		endif

		flirt -in $fm -ref $target_fm -out `basename $fm:r:r"_reg.nii.gz"` -dof 6 -interp spline
		if($status) exit 1

		set reg_sefm_list = ($reg_sefm_list `basename $fm:r:r"_reg.nii.gz"`)
	end

	set sefm_list = ($reg_sefm_list)

	${FSLDIR}/bin/fslmerge -t imain $sefm_list
	if($status) exit 1

	fslmaths imain -Tmean se_ref
	if($status) exit 1

	set peds = (`echo $ped | tr " " "\n" | sort | uniq`)

	foreach direction($peds)

		#register the spin echo maps to the reference image being distorted
		flirt -in se_ref -ref ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -omat "imain_on_b0_${direction}.mat" -dof 6
		if($status) exit 1

		flirt -in imain -ref ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -out imain_on_b0_${direction}.nii.gz -init "imain_on_b0_${direction}.mat" -applyxfm
		if($status) exit 1

		#compute field map in reference image space
		${FSLDIR}/bin/topup --verbose --imain=imain_on_b0_${direction}.nii.gz --datain=datain.txt --config=${TopupConfig} --out=topupfield_${direction} --fout=${patid}_${FM_Suffix}_ref_unwarped_warpcoef_${direction}.nii.gz --iout=imain_dc_${direction}.nii.gz --jacout=${patid}_${FM_Suffix}_ref_unwarped_jacobian_${direction}.nii.gz
		if($status) exit 1

		#create the magnitude image by averaging the AP and PA images
		fslmaths imain_dc_${direction}.nii.gz -Tmean fmap_mag_${direction}
		if($status) exit 1

		#convert the HZ field map to a rad/s field map by multiplying by 2pi
		fslmaths ${patid}_${FM_Suffix}_ref_unwarped_warpcoef_${direction}.nii.gz -mul 6.2831853 fmap_rads_${direction}.nii.gz
		if($status) exit 1

		#extact the brain from the magnitude image
		bet fmap_mag_${direction} fmap_mag_${direction}_brain -f 0.2
		if($status) exit 1

		if(! $?day1_path || ! $?day1_patid) then
			set Target_Path = ${SubjectHome}/Anatomical/Volume
			set Target_Patid = ${patid}
		else
			set Target_Path = ${day1_path}/Anatomical/Volume
			set Target_Patid = ${day1_patid}
		endif

		if($direction == "-y") then
			set fugue_dir = "y-"
		else if($direction == "y") then
			set fugue_dir = "y"
		else if($direction == "-x") then
			set fugue_dir = "x-"
		else if($direction == "x") then
			set fugue_dir = "x"
		endif

		bet ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain -f 0.3 -m -R
		if($status) exit 1

		fugue --loadfmap=fmap_rads_${direction} --dwell=$dwell[1] --unwarpdir=$fugue_dir --saveshift=${patid}_${FM_Suffix}_ref_distorted_shiftmap_${direction} --unwarp=${patid}_${FM_Suffix}_ref_distorted_${direction}_unwarped_fugue --in=${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction}  --mask=${patid}_${FM_Suffix}_ref_distorted_${direction}_brain_mask
		if($status) exit 1

		convertwarp -r ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -o ${patid}_${FM_Suffix}_ref_unwarp_${direction}.nii.gz -s ${patid}_${FM_Suffix}_ref_distorted_shiftmap_${direction} -d $fugue_dir # --postmat=${patid}_${FM_Suffix}_ref_distorted_to_${patid}_T1.mat
		if($status) exit 1

		applywarp -i ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -r ${SubjectHome}/Anatomical/Volume/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -w ${patid}_${FM_Suffix}_ref_unwarp_${direction}.nii.gz -o ${patid}_${FM_Suffix}_ref_unwarped_${direction} --interp=spline
		if($status) exit 1
	end

	#make the reference image
	set Ref_STACK = ()

	foreach direction($peds)
		set Ref_STACK = ($Ref_STACK ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction})
	end

	fslmerge -t Ref_STACK $Ref_STACK
	if($status) exit 1

	fslmaths Ref_STACK -Tmean ${Target_Path}/${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref
	if($status) exit 1

	rm Ref_STACK.*

	foreach direction($peds)

		bet ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_brain -R -f 0.3
		if($status) exit 1

		flirt -in ${patid}_${FM_Suffix}_ref_unwarped_${direction} -ref ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -omat ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat -out ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target} -dof 6 -cost $CostFunction -searchcost $CostFunction
		if($status) exit 1

		#see if we want to check how far a voxel displaces
		if($MaximumRegDisplacement == 0) then
			set MaximumRegDisplacement = `fslinfo ${patid}_${FM_Suffix}_ref_unwarped_${direction}.nii.gz | grep pixdim | awk '{print $2 * 1.25}' | sort -u | tail -1`
		endif

		flirt -in ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -ref ${patid}_${FM_Suffix}_ref_unwarped_${direction} -omat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat -dof 6 -cost $CostFunction -searchcost $CostFunction
		if($status) exit 1

		set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat 0 50 0`
		decho "2 way registration displacement: $Displacement" registration_displacement.txt

		if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${patid}_${FM_Suffix}_ref_unwarped_${direction} ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} ${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat ${Target_Patid}_${Reg_Target}_to_${patid}_${FM_Suffix}_ref_unwarped_${direction}_rev.mat 0 50 0 $MaximumRegDisplacement`) then
			echo "SCRIPT: $0 : 00004 : 	Error: Registration from $FM_Suffix $direction to $Reg_Target and $Reg_Target to $FM_Suffix $direction has a displacement of "$Displacement
			exit 1
		endif


		convertwarp -r ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -w ${patid}_${FM_Suffix}_ref_unwarp_${direction}.nii.gz --midmat=${patid}_${FM_Suffix}_ref_unwarped_${direction}_to_${Target_Patid}_${Reg_Target}.mat -o ${patid}_${FM_Suffix}_ref_unwarped_${direction}_warp.nii.gz
		if($status) exit 1

	end
popd
exit 0
