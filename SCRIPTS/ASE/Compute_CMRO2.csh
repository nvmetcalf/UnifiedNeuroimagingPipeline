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

set echo

set SubjectHome = $cwd

set AtlasName = `basename $target`

if(! $?day1_path) then
	set day1_path = ""
	set day1_patid = ""
else
	set day1_patid = $day1_path:t
endif

set out_trailer = ""

if(! $?RegisterEcho) then
	set RegisterEcho = 1
endif

set Reg_Target = $ASE_Reg_Target

if(-e $cwd/Freesurfer/${FreesurferVersionToUse}/mri) then
	set FSdir = $cwd/Freesurfer/${FreesurferVersionToUse}/mri
else
	decho "No valid freesurfer found."
	exit 1
endif

#this computes the point spread fwhm from the first pcasl image. The
#1.38 was taken from https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3587033/
# where they describe that the fwhm point spread function of 3dpCASL is 1.38
#times the voxel size dimension in the acquisition direction.

set asl_psf = `fslinfo dicom/$ASL[1] | grep pixdim2 | awk '{print $2 * 1.38}'`

ASE:
pushd ASE/Volume
	rm ${patid}_CMRO2* oef_x_cbf*

	set patid_root = $patid
	echo $patid_root

	#CAO2 = (Hgb x 1.34 * SaO2) + (0.003 * 100)
	#SaO2 = (O2hb/(O2hb + Hb)) * 100
	#SaO2 is a percentage, needs converting to the decimal form
	set cao2 = `echo $ASE_HGB $ASE_SaO2 | awk '{print(($1 * ($2 * 0.01) * 1.34) + (0.003 * 100))}'`

	echo "CaO2: $cao2"

	set cbf = ${SubjectHome}/ASL/Volume/${patid}*_cbf_mean.nii.gz
	set oef = ${SubjectHome}/ASE/Volume/${patid_root}_OEF.nii.gz

	fslmaths $oef -mul $cbf oef_x_cbf
	if($status) exit 1

	echo "fslmaths oef_x_cbf -mul $cao2 ${patid}_CMRO2"
	fslmaths oef_x_cbf -mul $cao2 ${patid}_CMRO2
	if($status) exit 1

	goto END
	#compute gtmpvc
	GTMPVC:

	decho "Creating gtm segmentation..."
	$PP_SCRIPTS/PET/.fdb.process.wmparc_py $patid $FSdir
	if($status) then
		decho "	error: .fdb.process.wmparc_py failed."
		exit 1
	endif

	#make a warp from nonlinear atlas space to orig
	convert_xfm -omat ${patid}_T1_to_${patid}_orig.mat -inverse ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat
	if($status) exit 1

	if($NonLinear) then
		convertwarp -o ${AtlasName}_to_${patid}_orig_warp -r ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig.nii --warp1=${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_invwarpfield_111.nii.gz --postmat=${patid}_T1_to_${patid}_orig.mat
		if($status) exit 1

		applywarp -i ${patid}_CMRO2 -r ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig -o ${patid}_CMRO2_on_${patid}_orig -w ${AtlasName}_to_${patid}_orig_warp --interp=spline
		if($status) exit 1
	else
		#flirt -in ${patid}_CMRO2 -ref ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig -out ${patid}_CMRO2_on_${patid}_orig -init ${AtlasName}_to_${patid}_orig.mat -applyxfm -interp spline
		flirt -in ${patid}_CMRO2.nii.gz -ref ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig -out ${patid}_CMRO2_on_${patid}_orig.nii.gz -init ${patid}_T1_to_${patid}_orig.mat -applyxfm
		if($status) exit 1
	endif

	fslmaths ${patid}_CMRO2_on_${patid}_orig -nan ${patid}_CMRO2_on_${patid}_orig
	if($status) exit 1

	lta_convert --inlta identity.nofile --src ${patid}_CMRO2_on_${patid}_orig.nii.gz --trg ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig.nii --outlta CMRO2.orig.lta --subject Freesurfer
	if ($status) exit 1

	mri_vol2vol --mov ${patid}_CMRO2_on_${patid}_orig.nii.gz --lta ../Freesurfer/mri/gtmseg.lta --targ gtmseg+wmparc.mgz --o CMRO2_to_gtm.nii.gz --nearest
	if ($status) exit 1

	mri_gtmpvc --sd $SubjectHome --i ${patid}_CMRO2_on_${patid}_orig.nii.gz --reg CMRO2.orig.lta --psf $asl_psf --seg "gtmseg+wmparc.mgz" --default-seg-merge --auto-mask PSF .01 --mgx .01 --o CMRO2_gtmpvc.output --no-rescale --rbv --rbv-res 1 --threads 6 >&! CMRO2_gtmpvc.log
	if ($status) then
		decho "$patid gtmpvc error." $ErrorLog
		goto END
	endif
#		mri_gtmpvc --i $mode.nii --reg $mode.reg.lta --psf $FWHM --seg "gtmseg+wmparc.mgz" --default-seg-merge --auto-mask PSF .01 --mgx .01 --o ${mode}_gtmpvc.output --no-rescale >&! ${mode}_gtmpvc.log; if ($status) exit $status

	python3 $PP_SCRIPTS/PET/.fdb/rbv_stats.py CMRO2_gtmpvc.output/aux/rbv.segmean.nii.gz CMRO2_gtmpvc.output/gtm.stats.dat CMRO2_gtmpvc.output/rbv.stats.dat
	if ($status) exit 1

END:
popd
exit 0
