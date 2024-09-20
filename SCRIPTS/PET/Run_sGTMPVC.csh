#!/bin/csh

source $1
source $2

set SubjectHome = $cwd
setenv SUBJECTS_DIR $cwd

echo "Running sGTM and RBV on available PET modalities..."

#if(! -e ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig.reg.lta) then	
	#this makes a lta for petsurfer to use. It should come back as identity
	mri_coreg --s Freesurfer --mov ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig.nii --reg ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig.reg.lta --dof 6
	if ($status) exit $status
#endif

pushd PET/Volume
	
	#find out which modalities we have to work with
	
	set modes_available = ()
	set modes_fwhm = ()
	set modes_image = ()
	
	if(-e ${patid}_FDG_on_orig_norm.nii.gz) then
		set modes_available = ($modes_available FDG)
		set modes_image = ($modes_image ${patid}_FDG_on_orig_norm.nii.gz)
		#collect the scanners point spread function full width half maximum
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$FDG[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for FDG does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
			
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)
	endif

	if(-e ${patid}_H2O_on_orig_norm.nii.gz) then
		set modes_available = ($modes_available H2O)
		set modes_image = ($modes_image ${patid}_H2O_on_orig_norm.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for H2O does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)
		
	endif

	if(-e ${patid}_O2_on_orig_norm.nii.gz) then
		set modes_available = ($modes_available O2)
		set modes_image = ($modes_image ${patid}_O2_on_orig_norm.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$O2[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for O2 does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)
	endif

	if(-e ${patid}_CO_on_orig_norm.nii.gz) then
		set modes_available = ($modes_available CO)
		set modes_image = ($modes_image ${patid}_CO_on_orig_norm.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$CO[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for CO does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)
	endif

	if(-e ${patid}_OM_on_orig.nii.gz) then
		set modes_available = ($modes_available OM)
		set modes_image = ($modes_image ${patid}_OM_on_orig.nii.gz)
		
		#is a derivative that must have a water, so use water
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for OM does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)
	endif

	if(-e ${patid}_GI_on_orig.nii.gz) then
		set modes_available = ($modes_available GI)
		set modes_image = ($modes_image ${patid}_GI_on_orig.nii.gz)
		
		#is a derivative that must have a water, so use water
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$H2O[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for GI does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)
	endif

	if(-e ${patid}_PIB_on_orig_norm.nii.gz) then
		set modes_available = ($modes_available PIB)
		set modes_image = ($modes_image ${patid}_PIB_on_orig_norm.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$PIB[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for PIB does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)

	endif

	if(-e ${patid}_TAU_on_orig_norm.nii.gz) then
		set modes_available = ($modes_available TAU)
		set modes_image = ($modes_image ${patid}_TAU_on_orig_norm.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$TAU[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for TAU does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)

	endif
	
	if(-e ${patid}_FBX_on_orig_norm.nii.gz) then
		set modes_available = ($modes_available FBX)
		set modes_image = ($modes_image ${patid}_FBX_on_orig_norm.nii.gz)
		set ScannerName = `grep ManufacturersModelName ${SubjectHome}/dicom/$FBX[1]:r:r".json" | cut -d\" -f4`
		if($#ScannerName == 0) then
			echo "JSON for FBX does not have a ManufacturersModelName tag. Cannot detect scanner point spread function."
			exit 1
		endif
		set modes_fwhm = ($modes_fwhm `grep "$ScannerName" $PP_SCRIPTS/Config/scanner_psf_fwhm.csv | head -1 | cut -d, -f2`)

	endif
	
	if($#modes_image != $#modes_fwhm) then
		echo "Number of scanner psf differs from the number of modalities. One or more modalities do not have a scanner in their source json."
		exit 1
	endif
	
	if($?ParcellationName) then
		pushd $SubjectHome
			$PP_SCRIPTS/Utilities/Generate_Volume_Parcellation_From_Gifti.csh ${SubjectHome}/$1 ${SubjectHome}/$2
			if($status) exit 1
		popd
		set ParcellationFilename = "${SubjectHome}/PET/Parcellations/$ParcellationName/${ParcellationName}_orig.nii.gz"
	else
		set ParcellationName = "gtmseg_wmparc"
		set ParcellationFilename = "${SubjectHome}/PET/Parcellations/gtmseg+wmparc_orig.nii.gz"
	endif
		
	@ i = 1
	while($i <= $#modes_available)
		set mode = $modes_image[$i]
		set FWHM = $modes_fwhm[$i]
		
		lta_convert --inlta identity.nofile --src $mode --trg ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig.nii --outlta $mode:r:r".orig.lta" --subject Freesurfer
		if ($status) exit 1
		
		mri_concatenate_lta -subject Freesurfer $mode:r:r".orig.lta" ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig.reg.lta $mode:r:r".reg.lta"
		if ($status) exit 1
		
		#this is for QC and making sure the orig images get to gtm space properly
		mri_vol2vol --mov ${mode} --lta ${SubjectHome}/Freesurfer/mri/gtmseg.lta --targ $ParcellationFilename --o ${mode:r:r}_on_gtm.nii.gz --nearest
		if ($status) exit 1
		
		mri_gtmpvc --sd ${SubjectHome} --i $mode --reg $mode:r:r".reg.lta" --psf $FWHM --seg $ParcellationFilename --default-seg-merge --auto-mask PSF .01 --mgx .01 --o $modes_available[$i]"_${ParcellationName}_gtmpvc" --no-rescale --no-reduce-fov --rbv --rbv-res 1 --threads 6
		if ($status) exit 1
		
		python3 $PP_SCRIPTS/PET/python3/rbv_stats.py $modes_available[$i]_${ParcellationName}_gtmpvc/aux/rbv.segmean.nii.gz $modes_available[$i]_${ParcellationName}_gtmpvc/gtm.stats.dat $modes_available[$i]_${ParcellationName}_gtmpvc/rbv.stats.dat
		if ($status) exit 1
		cd $modes_available[$i]_${ParcellationName}_gtmpvc
		
			#apply registrations to get back to the T1
			mri_vol2vol --mov rbv.nii.gz --lta ${SubjectHome}/Freesurfer/mri/gtm_to_orig.lta --targ ${SubjectHome}/Freesurfer/mri/orig.mgz --o rbv_to_orig.nii.gz --nearest
			if($status) exit 1
			
			if($?day1_path) then
				set reg_target_path = $day1_path
				set reg_patid = $day1_patid
			else
				set reg_target_path = $SubjectHome
				set reg_patid = $patid
			endif
			
			flirt -in rbv_to_orig.nii.gz -ref ${reg_target_path}/Anatomical/Volume/T1/${reg_patid}_T1 -out rbv_to_${patid}_T1 -init ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat -applyxfm
			if($status) exit 1
			
			if(-e ${SubjectHome}/Anatomical/Surface/fsaverage_LR${LowResMesh}k) then
				$PP_SCRIPTS/Surface/volume_to_surface.csh rbv_to_orig.nii.gz ${SubjectHome}/Anatomical/Surface/fsaverage_LR${LowResMesh}k $modes_available[$i]"_RBV" ${LowResMesh} ribbon midthickness
				if($status) exit 1
			endif
		cd ..
		@ i++
	end
popd

exit 0
