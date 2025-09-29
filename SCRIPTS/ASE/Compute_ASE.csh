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

set SubjectHome = $cwd

set FinalResolution = $ASE_FinalResolution

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

pushd ASE/Volume

	if(-e $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}.nii.gz) then
		ln -sf $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}.nii.gz ${patid}_t1.nii.gz
		if($status) exit 1
	else
		ln -sf $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}_fnirt.nii.gz ${patid}_t1.nii.gz
		if($status) exit 1
	endif
	#put together the ASE scan string
	@ i = 1
	set ASE_Scan_String = ("'"${SubjectHome}"/ASE/Volume/${patid}_ase${i}_upck_xr3d_dc_atl.nii.gz'")
		set ASE_JSON_String = ("'"${SubjectHome}"/dicom/"$ASE[$i]:r:r".json'")
	@ i = 2
	while($i <= $#ASE)
		set ASE_Scan_String = ($ASE_Scan_String ",'"${SubjectHome}"/ASE/Volume/${patid}_ase${i}_upck_xr3d_dc_atl.nii.gz'")
		set ASE_JSON_String = ($ASE_JSON_String ",'"${SubjectHome}"/dicom/"$ASE[$i]:r:r".json'")
		@ i++
	end

	echo $ASE_Scan_String
	echo $ASE_JSON_String

	matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/ASE'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${FREESURFER_HOME}/matlab'));segment_t1('$patid','$cwd');end;exit"

	matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/ASE'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${FREESURFER_HOME}/matlab'));process_ase('$patid', {$ASE_Scan_String}, { $ASE_JSON_String }, $ASE_HCT, '$cwd');end;exit"

	goto SKIP_PVC
	$PP_SCRIPTS/ASE/Resample_ASE_for_PVC.csh $patid $SubjectHome
	if($status) exit 1

	cp ${patid}_ase_para.dat PVC/

	matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/ASE'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${FREESURFER_HOME}/matlab'));process_ase_pvc('$patid', {$ASE_Scan_String}, { $ASE_JSON_String }, $ASE_HCT, '$cwd');end;exit"
	SKIP_PVC:
popd
