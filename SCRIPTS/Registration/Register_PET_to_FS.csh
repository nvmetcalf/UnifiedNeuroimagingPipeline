#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

if($?day1_patid) then
	set target = $day1_patid
else
	set target = $patid
endif

if(! -e ${SubjectHome}/Masks/FreesurferMasks/${patid}_T1_to_${patid}_orig.mat && ! -e ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat) then
	echo "Cannot find registration from T1 to Orig in Masks/FreesurferMasks."
	exit 1
else if(! -e ${SubjectHome}/Masks/FreesurferMasks/${patid}_T1_to_${patid}_orig.mat && -e ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat) then
	echo "Inverting orig to T1 matrix."
	
	convert_xfm -omat ${SubjectHome}/Masks/FreesurferMasks/${patid}_T1_to_${patid}_orig.mat -inverse ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig_to_${patid}_T1.mat
	if($status) exit 1
endif

set modes_available = ()
echo "Registering PET modalities to freesurfer..."



if($?FDG && -e ${SubjectHome}/Anatomical/Volume/FDG/${patid}_FDG_to_${target}_T1.mat) then
	set modes_available = ($modes_available FDG)
endif
	
if($?O2 && -e ${SubjectHome}/Anatomical/Volume/O2/${patid}_O2_to_${target}_T1.mat) then
	set modes_available = ($modes_available O2)
endif
	
if($?CO && -e ${SubjectHome}/Anatomical/Volume/CO/${patid}_CO_to_${target}_T1.mat) then
	set modes_available = ($modes_available CO)
endif
	
if($?H2O && -e ${SubjectHome}/Anatomical/Volume/H2O/${patid}_H2O_to_${target}_T1.mat) then
	set modes_available = ($modes_available H2O)
endif
		
if($?PIB && -e ${SubjectHome}/Anatomical/Volume/PIB/${patid}_PIB_to_${target}_T1.mat) then
	set modes_available = ($modes_available PIB)
endif

if($?TAU && -e ${SubjectHome}/Anatomical/Volume/TAU/${patid}_TAU_to_${target}_T1.mat) then
	set modes_available = ($modes_available TAU)
endif

if($?FBX && -e ${SubjectHome}/Anatomical/Volume/FBX/${patid}_FBX_to_${target}_T1.mat) then
	set modes_available = ($modes_available FBX)
endif

foreach mode($modes_available)
	convert_xfm -omat ${SubjectHome}/Anatomical/Volume/$mode/${patid}_${mode}_to_${patid}_orig.mat -concat ${SubjectHome}/Masks/FreesurferMasks/${patid}_T1_to_${patid}_orig.mat ${SubjectHome}/Anatomical/Volume/${mode}/${patid}_${mode}_to_${target}_T1.mat
	if($status) exit 1
	
	flirt -in ${SubjectHome}/Anatomical/Volume/${mode}/${patid}_${mode} -ref ${SubjectHome}/Masks/FreesurferMasks/${patid}_orig -out ${SubjectHome}/PET/Volume/${patid}_${mode}_on_orig -init ${SubjectHome}/Anatomical/Volume/$mode/${patid}_${mode}_to_${patid}_orig.mat -applyxfm
	if($status) exit 1
end
