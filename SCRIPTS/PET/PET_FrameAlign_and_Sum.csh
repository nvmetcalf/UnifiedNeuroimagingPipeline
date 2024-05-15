#!/bin/csh

source $1

source $2

set ScratchDir = $ScratchFolder/$patid/PET_temp
set SubjectHome = $cwd

if(! $?FDG) set FDG = ()
if(! $?O2) set O2 = ()
if(! $?H2O) set H2O = ()
if(! $?CO) set CO = ()
if(! $?PIB) set PIB = ()
if(! $?TAU) set TAU = ()

pushd $ScratchDir
	#convert the available PET nifti images to 4dfp
	set PET_Images = ()
	set PET_Durations = ()
	set PET_Isotope = ()
	set PET_Modality = ()
	set PET_FrameAlign = ()
	set PET_SumMethod = ()
	
	#H2O
	@ i = 1
	foreach image($H2O)
		set PET_Images = ($PET_Images ${SubjectHome}/dicom/$image)
		set PET_Durations = ($PET_Durations $H2O_Duration[$i])
		set PET_Isotope = ($PET_Isotope O-15)
		set PET_Modality = ($PET_Modality H2O)
		set PET_SumMethod = ($PET_SumMethod $H2O_SumMethod)
		
		if(! $?H2O_FrameAlign) set H2O_FrameAlign = 1
		set PET_FrameAlign = ($PET_FrameAlign $H2O_FrameAlign)
		
		@  i++
	end
	
	#O2
	@ i = 1
	foreach image($O2)
		set PET_Images = ($PET_Images ${SubjectHome}/dicom/$image)
		set PET_Durations = ($PET_Durations $O2_Duration[$i])
		set PET_Isotope = ($PET_Isotope O-15)
		set PET_Modality = ($PET_Modality O2)
		set PET_SumMethod = ($PET_SumMethod $O2_SumMethod)
		
		if(! $?O2_FrameAlign) set O2_FrameAlign = 1
		set PET_FrameAlign = ($PET_FrameAlign $O2_FrameAlign)
		
		@  i++
	end
	
	#CO
	@ i = 1
	foreach image($CO)
		set PET_Images = ($PET_Images ${SubjectHome}/dicom/$image)
		set PET_Durations = ($PET_Durations $CO_Duration[$i])
		set PET_Isotope = ($PET_Isotope C-11)
		set PET_Modality = ($PET_Modality CO)
		set PET_SumMethod = ($PET_SumMethod $CO_SumMethod)
		
		if(! $?CO_FrameAlign) set CO_FrameAlign = 0
		set PET_FrameAlign = ($PET_FrameAlign $CO_FrameAlign)
		
		
		@  i++
	end
	
	#FDG 
	@ i = 1
	foreach image($FDG)
		set PET_Images = ($PET_Images ${SubjectHome}/dicom/$image)
		set PET_Durations = ($PET_Durations $FDG_Duration[$i])
		set PET_Isotope = ($PET_Isotope F-18)
		set PET_Modality = ($PET_Modality FDG)
		set PET_SumMethod = ($PET_SumMethod $FDG_SumMethod)
		
		if(! $?FDG_FrameAlign) set FDG_FrameAlign = 1
		set PET_FrameAlign = ($PET_FrameAlign $FDG_FrameAlign)
		
		@  i++
	end

	#PIB 
	@ i = 1
	foreach image($PIB)
		set PET_Images = ($PET_Images ${SubjectHome}/dicom/$image)
		set PET_Durations = ($PET_Durations $PIB_Duration[$i])
		set PET_Isotope = ($PET_Isotope F-18)
		set PET_Modality = ($PET_Modality PIB)
		set PET_SumMethod = ($PET_SumMethod $PIB_SumMethod)
		
		if(! $?PIB_FrameAlign) set PIB_FrameAlign = 1
		set PET_FrameAlign = ($PET_FrameAlign $PIB_FrameAlign)
		
		@  i++
	end
	
	#TAU 
	@ i = 1
	foreach image($TAU)
		set PET_Images = ($PET_Images ${SubjectHome}/dicom/$image)
		set PET_Durations = ($PET_Durations $TAU_Duration[$i])
		set PET_Isotope = ($PET_Isotope F-18)
		set PET_Modality = ($PET_Modality TAU)
		set PET_SumMethod = ($PET_SumMethod $TAU_SumMethod)
		
		if(! $?TAU_FrameAlign) set TAU_FrameAlign = 1
		set PET_FrameAlign = ($PET_FrameAlign $TAU_FrameAlign)
		
		@  i++
	end
	
	#FlorbetaX
	@ i = 1
	foreach image($FBX)
		set PET_Images = ($PET_Images ${SubjectHome}/dicom/$image)
		set PET_Durations = ($PET_Durations $FBX_Duration[$i])
		set PET_Isotope = ($PET_Isotope F-18)
		set PET_Modality = ($PET_Modality FBX)
		set PET_SumMethod = ($PET_SumMethod $FBX_SumMethod)
		
		if(! $?FBX_FrameAlign) set FBX_FrameAlign = 1
		set PET_FrameAlign = ($PET_FrameAlign $FBX_FrameAlign)
		
		@  i++
	end
	
	#Compute decay corrected sum images
	@ i = 1
	while($i <= $#PET_Images)
	
		set DurationAfterPeak = $PET_Durations[$i]
		
		rm -r $PET_Modality[$i]_${i}
		
		$PP_SCRIPTS/PET/Compute_corrected_sum.csh $PET_Images[$i] $DurationAfterPeak $PET_Isotope[$i] $PET_Modality[$i]_${i} $PET_FrameAlign[$i] $PET_SumMethod[$i]
		if ($status) exit $status
		
		mv $PET_Modality[$i]_${i}/*imings.txt ${SubjectHome}/PET/Time_Decay
		mv $PET_Modality[$i]_${i}/$PET_Modality[$i]_${i}_mcflirt*.par ${SubjectHome}/PET/Movement/$PET_Modality[$i]_${i}_mcflirt.par
		mv $PET_Modality[$i]_${i}/$PET_Modality[$i]_${i}"_sum_deco.nii.gz" ${SubjectHome}/PET/Volume/
		#mv $PET_Modality[$i]_${i}/$PET_Modality[$i]_${i}"_mcflirt.nii.gz" ${SubjectHome}/PET/Volume/
		
		@ i++
	end
popd
