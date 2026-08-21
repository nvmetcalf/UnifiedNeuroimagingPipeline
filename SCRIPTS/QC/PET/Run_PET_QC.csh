#!/bin/csh

source $1
source $2

set SubjectHome = $cwd

if(! -e ${SubjectHome}/PET/Volume) then
	echo "Not PET available."
	exit 0
endif

#run the PET QC metrics

#extract the registration displacements
#extract mean whitematter SUVR
#extract mean grey matter SUVR
#extract source image voxel dimensions
#mean movement (FD) of each tracer

if(! -e $SubjectHome/QC) mkdir QC

ftouch ${SubjectHome}/QC/PET_QC.csv

set TracersKnown = (FDG H2O O2 CO OM OEF CMRO2 GI PIB TAU FBX)

if($?day1_path) then
	set target_id = ${day1_path:t}
	set target_path = ${day1_path}
else
	set target_id = ${patid}
	set target_path = $SubjectHome
endif

echo "Modality,Registration Displacement,Mean WM SUVR,Mean GM SUVR,Analyzed X Dim,Analyzed Y Dim,Analyzed Z Dim,Mean FD, PVC" >> ${SubjectHome}/QC/PET_QC.csv

set FinalResTrailer = ${PET_FinalResolution}${PET_FinalResolution}${PET_FinalResolution}

foreach Tracer($TracersKnown)

	set displacement = "-"
	set mean_wm_suvr = "-"
	set mean_gm_suvr = "-"
	set raw_x_dim = "-"
	set raw_y_dim = "-"
	set raw_z_dim = "-"
	set mean_fd = "-"
		
	#erode the wm mask to prevent picking up on cortical uptake
	pushd ${target_path}/Masks/FreesurferMasks/
		fslmaths ${target_id}_WM_on_${target_id}_T1_${FinalResTrailer}.nii.gz -ero -ero ${target_id}_WM_on_${target_id}_T1_${FinalResTrailer}_ero.nii.gz
	popd
	
	set wm_mask = ${target_path}/Masks/FreesurferMasks/${target_id}_WM_on_${target_id}_T1_${FinalResTrailer}_ero.nii.gz
	set gm_mask = ${target_path}/Masks/FreesurferMasks/${target_id}_GM_on_${target_id}_T1_${FinalResTrailer}.nii.gz
	
	if(! -e $SubjectHome/Anatomical/Volume/${Tracer}/${patid}_${Tracer}_to_${target_id}_T1.nii.gz && -e ${SubjectHome}/PET/Volume/${patid}_${Tracer}_on_T1_${FinalResTrailer}.nii.gz) then
		set mean_wm_suvr = `fslstats ${SubjectHome}/PET/Volume/${patid}_${Tracer}_on_T1_${FinalResTrailer}.nii.gz -k $wm_mask -M`
		set mean_gm_suvr = `fslstats ${SubjectHome}/PET/Volume/${patid}_${Tracer}_on_T1_${FinalResTrailer}.nii.gz -k $gm_mask -M`
	
		set raw_x_dim = `fslinfo ${SubjectHome}/PET/Volume/${Tracer}/${patid}_${Tracer}_on_T1.nii.gz | grep -w pixdim1 | awk '{print($2)}'`
		set raw_y_dim = `fslinfo ${SubjectHome}/PET/Volume/${Tracer}/${patid}_${Tracer}_on_T1.nii.gz | grep -w pixdim2 | awk '{print($2)}'`
		set raw_z_dim = `fslinfo ${SubjectHome}/PET/Volume/${Tracer}/${patid}_${Tracer}_on_T1.nii.gz | grep -w pixdim3 | awk '{print($2)}'`

	else if(-e $SubjectHome/Anatomical/Volume/${Tracer}/${patid}_${Tracer}_to_${target_id}_T1_${FinalResTrailer}.nii.gz) then
		set displacement = `tail -1 $SubjectHome/Anatomical/Volume/${Tracer}/${patid}_${Tracer}_to_*_displacement.txt | awk '{print($NF)}'`

		set mean_wm_suvr = `fslstats ${SubjectHome}/PET/Volume/${patid}_${Tracer}_on_T1_${FinalResTrailer}_norm.nii.gz -k $wm_mask -M`
		set mean_gm_suvr = `fslstats ${SubjectHome}/PET/Volume/${patid}_${Tracer}_on_T1_${FinalResTrailer}_norm.nii.gz -k $gm_mask -M`

		set raw_x_dim = `fslinfo ${SubjectHome}/Anatomical/Volume/${Tracer}/${patid}_${Tracer}.nii.gz | grep -w pixdim1 | awk '{print($2)}'`
		set raw_y_dim = `fslinfo ${SubjectHome}/Anatomical/Volume/${Tracer}/${patid}_${Tracer}.nii.gz | grep -w pixdim2 | awk '{print($2)}'`
		set raw_z_dim = `fslinfo ${SubjectHome}/Anatomical/Volume/${Tracer}/${patid}_${Tracer}.nii.gz | grep -w pixdim3 | awk '{print($2)}'`
		
		#compute the mean fd for all the tracers
		ftouch temp
		foreach acquisition(${ScratchFolder}/${patid}/PET_temp/${Tracer}_*)
			 cat ${acquisition}/*_mcflirt.par.fd >> temp
		end
		
		set mean_fd = `cat temp | awk 'BEGIN{sum = 0; n = 0}{sum = sum + $1;n++}END{print(sum/n)}'`
		
		rm temp
		
	endif
	pushd ${SubjectHome}/PET/Volume
		set PVC_Available = (`ls -d ${Tracer}_*gtmpvc`)
	popd
	echo "${Tracer},${displacement},${mean_wm_suvr},${mean_gm_suvr},${raw_x_dim},${raw_y_dim},${raw_z_dim},${mean_fd},${PVC_Available}" >> ${SubjectHome}/QC/PET_QC.csv
	
end


