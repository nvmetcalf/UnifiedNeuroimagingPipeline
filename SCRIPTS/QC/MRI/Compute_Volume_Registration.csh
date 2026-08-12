#!/bin/csh


source $1
source $2

set SubjectHome = $cwd

#combine all the registration displacements into a single file.
#Registration Displacements in mm will be written to this file
ftouch ${SubjectHome}/QC/RegistrationDisplacements.txt

foreach modality(${SubjectHome}/Anatomical/Volume/*)
	if(-e $modality/registration_displacement.txt) then
		set Mode = $modality:t
		set Displacement = `tail -1 $modality/registration_displacement.txt | awk '{print($NF)}'`
			
		echo $Mode" : "$Displacement >> ${SubjectHome}/QC/RegistrationDisplacements.txt
	endif
end

#the spatial correlations will be added to this file
ftouch QC/SpatialCorrelation.txt

$PP_SCRIPTS/QC/MRI/VolumeRegQC/Compute_T1_Registration_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/VolumeRegQC/Compute_T2_Registration_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/VolumeRegQC/Compute_FLAIR_Registration_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/VolumeRegQC/Compute_BOLD_Registration_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/VolumeRegQC/Compute_ASL_Registration_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/VolumeRegQC/Compute_DTI_Registration_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/VolumeRegQC/Compute_SWI_Registration_QC.csh $1 $2
if($status) exit 1

$PP_SCRIPTS/QC/MRI/VolumeRegQC/Compute_ASE_Registration_QC.csh $1 $2
if($status) exit 1
