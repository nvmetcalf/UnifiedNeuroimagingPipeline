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
	
	rm ${patid}_t1.nii.gz
	if(-e $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}.nii.gz) then
		cp -f $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}.nii.gz ${patid}_t1.nii.gz
		if($status) exit 1
	else
		cp -f $SubjectHome/Anatomical/Volume/T1/${patid}_T1_${FinalResTrailer}_fnirt.nii.gz ${patid}_t1.nii.gz
		if($status) exit 1
	endif
	
	#matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/ASE'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${FREESURFER_HOME}/matlab'));segment_t1('$patid','$cwd');end;exit"
	
	#run the OEF computation on each set of echo's. This assumes that the echo's are arranged in ascending repeating order.
	#i.e. scan 1 echo 1, scan 1 echo 2, scan 2 echo 1, scan 2 echo 2, ... n
	#put together the ASE scan string
	@ i = 0
	@ SetNum = 1
	while($i < $#ASE)
	
		rm -rf ase${SetNum}
		mkdir ase${SetNum}
		
		@ i = $i + 1
		set ASE_Scan_String = ("'"${SubjectHome}"/ASE/Volume/ase${SetNum}/${patid}_ase_e1_upck_xr3d_dc_atl.nii.gz'")
		set ASE_JSON_String = ("'"${SubjectHome}"/dicom/"$ASE[$i]:r:r".json'")
		ln -s ${SubjectHome}/ASE/Volume/${patid}_ase${i}_upck_xr3d_dc_atl.nii.gz ${cwd}/ase${SetNum}/${patid}_ase_e1_upck_xr3d_dc_atl.nii.gz
		
		@ i = $i + 1

		set ASE_Scan_String = ($ASE_Scan_String ",'"${SubjectHome}"/ASE/Volume/ase${SetNum}/${patid}_ase_e2_upck_xr3d_dc_atl.nii.gz'")
		set ASE_JSON_String = ($ASE_JSON_String ",'"${SubjectHome}"/dicom/"$ASE[$i]:r:r".json'")

		ln -s ${SubjectHome}/ASE/Volume/${patid}_ase${i}_upck_xr3d_dc_atl.nii.gz ${cwd}/ase${SetNum}/${patid}_ase_e2_upck_xr3d_dc_atl.nii.gz
		
		echo $ASE_Scan_String
		echo $ASE_JSON_String

		pushd ase${SetNum}
			matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/ASE'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${FREESURFER_HOME}/matlab'));process_ase('$patid', {$ASE_Scan_String}, { $ASE_JSON_String }, $ASE_HCT, '$cwd');end;exit"

			goto SKIP_PVC
			$PP_SCRIPTS/ASE/Resample_ASE_for_PVC.csh $patid $SubjectHome
			if($status) exit 1

			cp ${patid}_ase_para.dat PVC/

			matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/ASE'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${FREESURFER_HOME}/matlab'));process_ase_pvc('$patid', {$ASE_Scan_String}, { $ASE_JSON_String }, $ASE_HCT, '$cwd');end;exit"
			
			SKIP_PVC:
			
			#rename all the outputs.
			mv ${patid}_C.nii.gz ${patid}_C_run${SetNum}.nii.gz
			mv ${patid}_Error.nii.gz ${patid}_Error_run${SetNum}.nii.gz
			mv ${patid}_Error_Norm.nii.gz ${patid}_Error_Norm_run${SetNum}.nii.gz
			mv ${patid}_LAMBDA.nii.gz ${patid}_LAMBDA_run${SetNum}.nii.gz
			mv ${patid}_OEF.nii.gz ${patid}_OEF_run${SetNum}.nii.gz
			mv ${patid}_R2.nii.gz ${patid}_R2_run${SetNum}.nii.gz
			mv ${patid}_R2P.nii.gz ${patid}_R2P_run${SetNum}.nii.gz
		popd
		@ SetNum++
	end
popd
