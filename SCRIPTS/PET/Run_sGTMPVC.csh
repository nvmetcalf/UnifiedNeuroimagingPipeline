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
setenv SUBJECTS_DIR $cwd/Freesurfer

if($?day1_patid) then
	set target = $day1_path:t
	set target_path = $day1_path
	set target_patid = $day1_path:t
else
	set target = $patid
	set target_path = $SubjectHome
	set target_patid = $patid
endif

echo "Running sGTM and RBV on available PET modalities..."

#this makes a lta for petsurfer to use. It should come back as identity
mri_coreg --s ${FreesurferVersionToUse} --mov ${target_path}/Masks/FreesurferMasks/${target_patid}_orig.nii --reg ${target_path}/Masks/FreesurferMasks/${target_patid}_orig.reg.lta --dof 6
if ($status) then
	echo "SCRIPT: $0 : 00003 : mri_coreg failed"
	exit $status
endif


pushd PET/Volume

	#find out which modalities we have to work with

	set modes_available = ()
	set modes_fwhm = ()
	set modes_image = ()

	if(-e ${patid}_FDG_on_orig.nii.gz) then
		set modes_available = ($modes_available FDG)
		set modes_image = ($modes_image ${patid}_FDG_on_orig.nii.gz)
		#collect the scanners point spread function full width half maximum
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$FDG[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00004 : JSON for FDG does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif

		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f3`)
	endif

	if(-e ${patid}_H2O_on_orig.nii.gz) then
		set modes_available = ($modes_available H2O)
		set modes_image = ($modes_image ${patid}_H2O_on_orig.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00005 : JSON for H2O does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)

	endif

	if(-e ${patid}_O2_on_orig.nii.gz) then
		set modes_available = ($modes_available O2)
		set modes_image = ($modes_image ${patid}_O2_on_orig.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$O2[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00006 : JSON for O2 does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)
	endif

	if(-e ${patid}_CO_on_orig.nii.gz) then	#also CBV
		set modes_available = ($modes_available CO)
		set modes_image = ($modes_image ${patid}_CO_on_orig.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$CO[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00007 : JSON for CO does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)
	endif

	if(-e ${patid}_OM_on_orig.nii.gz) then	#also CMRO2
		set modes_available = ($modes_available OM)
		set modes_image = ($modes_image ${patid}_OM_on_orig.nii.gz)

		#is a derivative that must have a water, so use water
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00008 : JSON for OM does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)
	endif

	if(-e ${patid}_OE_on_orig.nii.gz) then
		set modes_available = ($modes_available OE)
		set modes_image = ($modes_image ${patid}_OE_on_orig.nii.gz)

		#is a derivative that must have a water, so use water
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00009 : JSON for OE does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)
	endif

	if(-e ${patid}_GI_on_orig.nii.gz) then
		set modes_available = ($modes_available GI)
		set modes_image = ($modes_image ${patid}_GI_on_orig.nii.gz)

		#is a derivative that must have a water, so use water
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00010 : JSON for GI does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)
	endif

	if(-e ${patid}_OEF_on_orig.nii.gz) then
		set modes_available = ($modes_available OEF)
		set modes_image = ($modes_image ${patid}_OEF_on_orig.nii.gz)

		#is a derivative that must have a water, so use water
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00011 : JSON for OEF does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)
	endif

	if(-e ${patid}_CMRO2_on_orig.nii.gz) then
		set modes_available = ($modes_available CMRO2)
		set modes_image = ($modes_image ${patid}_CMRO2_on_orig.nii.gz)

		#is a derivative that must have a water, so use water
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00012 : JSON for CMRO2 does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)
	endif

	if(-e ${patid}_PIB_on_orig.nii.gz) then
		set modes_available = ($modes_available PIB)
		set modes_image = ($modes_image ${patid}_PIB_on_orig.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$PIB[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00013 : JSON for PIB does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f3`)

	endif

	if(-e ${patid}_TAU_on_orig.nii.gz) then
		set modes_available = ($modes_available TAU)
		set modes_image = ($modes_image ${patid}_TAU_on_orig.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$TAU[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00014 : JSON for TAU does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f5`)

	endif

	if(-e ${patid}_FBX_on_orig.nii.gz) then
		set modes_available = ($modes_available FBX)
		set modes_image = ($modes_image ${patid}_FBX_on_orig.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$FBX[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "SCRIPT: $0 : 00015 : JSON for FBX does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f4`)

	endif

	if($#modes_image != $#modes_fwhm) then
		echo "SCRIPT: $0 : 00016 : Number of scanner psf differs from the number of modalities. One or more modalities do not have a scanner in their source json."
		exit 1
	endif

	#does the parcellation exist and is it not a file?
	if(! $?ParcellationName) then
		#default if nothing is set
		set ParcellationName = "gtmseg_wmparc"
		set ParcellationFilename = "${SubjectHome}/PET/Parcellations/${FreesurferVersionToUse}/gtmseg+wmparc_orig.nii.gz"
	else if($?ParcellationName && $ParcellationName:e == "" ) then
		#assume its a surface and embed
		pushd $SubjectHome
			$PP_SCRIPTS/Utilities/Generate_Volume_Parcellation_From_Gifti.csh $1 $2
			if($status) then
				echo "SCRIPT: $0 : 00017 : Failed to generate volume parcellation from surfaces."
				exit 1
			endif
		popd
		set ParcellationFilename = "${SubjectHome}/PET/Parcellations/$ParcellationName/${ParcellationName}_orig.nii.gz"
	else if($?ParcellationName && $ParcellationName:e != "") then
		#parcellation name is set and it is an actual file
		set ParcellationFilename = "${SubjectHome}/PET/Parcellations/${ParcellationName}"
		set ParcellationName = $ParcellationName:r:r
	else
		#use the default gtmseg + fs wm if everything else fails
		set ParcellationName = "gtmseg_wmparc"
		set ParcellationFilename = "${SubjectHome}/PET/Parcellations/${FreesurferVersionToUse}/gtmseg+wmparc_orig.nii.gz"
	endif

	@ i = 1
	while($i <= $#modes_available)
		set mode = $modes_image[$i]
		set FWHM = $modes_fwhm[$i]

		#gtmpvc can only use LTA style matrices... so make an identity LTA
		lta_convert --inlta identity.nofile --src $mode --trg ${target_path}/Masks/FreesurferMasks/${target_patid}_orig.nii --outlta $mode:r:r".orig.lta" --subject ${FreesurferVersionToUse}
		if ($status) then
			echo "SCRIPT: $0 : 00018 : failed to convert identity lta."
			exit 1
		endif

		mri_concatenate_lta -subject ${FreesurferVersionToUse} $mode:r:r".orig.lta" ${target_path}/Masks/FreesurferMasks/${target_patid}_orig.reg.lta $mode:r:r".reg.lta"
		if ($status) then
			echo "SCRIPT: $0 : 00019 : failed to concat identity to orig lta"
			exit 1
		endif
		#this is for QC and making sure the orig images get to gtm space properly
		mri_vol2vol --mov ${mode} --lta ${target_path}/Freesurfer/${FreesurferVersionToUse}/mri/gtmseg.lta --targ $ParcellationFilename --o ${mode:r:r}_on_gtm.nii.gz --nearest
		if ($status) then
			echo "SCRIPT: $0 : 00020 : failed to transform $mode to gtm space."
			exit 1
		endif

		echo "mri_gtmpvc --sd ${SubjectHome}/Freesurfer --i $mode --reg $mode:r:r".reg.lta" --psf $FWHM --seg $ParcellationFilename --default-seg-merge --auto-mask PSF .01 --mgx .01 --o $modes_available[$i]"_${ParcellationName}_gtmpvc" --no-rescale --no-reduce-fov --rbv --rbv-res 1 --threads 6"
		
		 
		
		mri_gtmpvc --sd ${SubjectHome}/Freesurfer --i $mode --reg $mode:r:r".reg.lta" --psf $FWHM --seg $ParcellationFilename --default-seg-merge --auto-mask PSF .01 --mgx .01 --o $modes_available[$i]"_${ParcellationName}_gtmpvc" --no-rescale --no-reduce-fov --rbv --rbv-res 1 --threads 6
		if ($status) then
			echo "SCRIPT: $0 : 00021 : failed to complete sGTM pvc"
			exit 1
		endif

		python3 $PP_SCRIPTS/PET/python3/rbv_stats.py $modes_available[$i]_${ParcellationName}_gtmpvc/aux/rbv.segmean.nii.gz $modes_available[$i]_${ParcellationName}_gtmpvc/gtm.stats.dat $modes_available[$i]_${ParcellationName}_gtmpvc/rbv.stats.dat
		if ($status) then
			echo "SCRIPT: $0 : 00022 : failed to extract RBV stats."
			exit 1
		endif
		cd $modes_available[$i]_${ParcellationName}_gtmpvc

			#apply registrations to get back to the T1
			mri_vol2vol --mov rbv.nii.gz --lta ${target_path}/Freesurfer/${FreesurferVersionToUse}/mri/gtm_to_orig.lta --targ ${target_path}/Freesurfer/${FreesurferVersionToUse}/mri/orig.mgz --o rbv_to_orig.nii.gz --nearest
			if($status) then
				echo "SCRIPT: $0 : 00023 : failed to transform rbv to orig space."
				exit 1
			endif
# 			flirt -in rbv_to_orig.nii.gz -ref ${reg_target_path}/Anatomical/Volume/T1/${reg_patid}_T1 -out rbv_to_${patid}_T1 -init ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat -applyxfm
			#if($status) exit 1

			if(-e ${target_path}/Anatomical/Surface/fsaverage_LR${LowResMesh}k) then
				$PP_SCRIPTS/Surface/volume_to_surface.csh rbv_to_orig.nii.gz ${target_path}/Anatomical/Surface/fsaverage_LR${LowResMesh}k $modes_available[$i]"_RBV" ${LowResMesh} ribbon midthickness
				if($status) then
					echo "SCRIPT: $0 : 00024 : failed to project the rbv volume to surfaces."
					exit 1
				endif
			endif
		cd ..
		@ i++
	end
popd

exit 0
