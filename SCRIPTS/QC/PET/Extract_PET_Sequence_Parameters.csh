#!/bin/csh


set OutputCSV = $1

echo "ParticipantID,AcquisitionPatientID,JSON,ManufacturersModelName,StudyDescription,SeriesDescription,Radiopharmaceutical,InjectedRadioactivityUnits,RadionuclideHalfLife,ReconstructionMethod,DecayFactor,FrameTimesStart,FrameDuration,FrameReferenceTime,PixelDimX,PixelDimY,PixelDimZ,NumberofVolumes" >! $OutputCSV

set ParticipantID = $cwd:t
foreach image(dicom/*.json)
	set JSON = $image:t
	set AcquisitionPatientID = `$PP_SCRIPTS/Utilities/GetJSON_Value $image PatientID` 
	set ManufacturersModelName = `$PP_SCRIPTS/Utilities/GetJSON_Value $image ManufacturersModelName`	#, Biograph128_Vision 600 Edge
	set StudyDescription = `$PP_SCRIPTS/Utilities/GetJSON_Value $image StudyDescription`	#, Head^CCIR_0970_QuadPack (Adult)
	set SeriesDescription = `$PP_SCRIPTS/Utilities/GetJSON_Value $image SeriesDescription`	#, Oxygen2 Dynamic
	set Radiopharmaceutical = `$PP_SCRIPTS/Utilities/GetJSON_Value $image Radiopharmaceutical`	#, Oxygen
	set InjectedRadioactivityUnits = `$PP_SCRIPTS/Utilities/GetJSON_Value $image InjectedRadioactivityUnits`	#, MBq
	set RadionuclideHalfLife = `$PP_SCRIPTS/Utilities/GetJSON_Value $image RadionuclideHalfLife`	#, 122.24
	set ReconstructionMethod = `$PP_SCRIPTS/Utilities/GetJSON_Value $image ReconstructionMethod`	#, OSEM3D+TOF 8i5s
	set DecayFactor = `$PP_SCRIPTS/Utilities/GetJSON_Value $image DecayFactor`	#, [list of factors]
	set FrameTimesStart = `$PP_SCRIPTS/Utilities/GetJSON_Value $image FrameTimesStart`	#,[frame start times in seconds]
	set FrameDuration = `$PP_SCRIPTS/Utilities/GetJSON_Value $image FrameDuration`	#, [how long each frame lasts in seconds]
	set FrameReferenceTime = `$PP_SCRIPTS/Utilities/GetJSON_Value $image FrameReferenceTime`	#,[mid times in seconds]    
	
	set PixelDimX = `fslinfo $image:r:r".nii.gz" | grep -w pixdim1 | awk '{print($2)'}`	
	set PixelDimY = `fslinfo $image:r:r".nii.gz" | grep -w pixdim2 | awk '{print($2)'}`
	set PixelDimZ = `fslinfo $image:r:r".nii.gz" | grep -w pixdim3 | awk '{print($2)'}`
	set NumberofVolumes = `fslinfo $image:r:r".nii.gz" | grep -w dim4 | awk '{print($2)'}`
	
	echo "${ParticipantID},${AcquisitionPatientID},${JSON},$ManufacturersModelName,$StudyDescription,$SeriesDescription,$Radiopharmaceutical,$InjectedRadioactivityUnits,$RadionuclideHalfLife,$ReconstructionMethod,$DecayFactor,$FrameTimesStart,$FrameDuration,$FrameReferenceTime,$PixelDimX,$PixelDimY,$PixelDimZ,$NumberofVolumes" >> $OutputCSV
end
