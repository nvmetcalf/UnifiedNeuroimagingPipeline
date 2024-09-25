#!/bin/csh

source $1
source $2

@ TypesOfSeq = 0
set PrevSeq = ""
set SubjectHome = $cwd

if(! $?NativeMetric) then
	set NativeMetric = 0
endif

set FinalResTrailer = "${FinalResolution}${FinalResolution}${FinalResolution}"

if($NonLinear) then
	set BrainMask = ${SubjectHome}/Masks/${patid}_used_voxels_fnirt_${FinalResTrailer}.nii.gz
else
	set BrainMask = ${SubjectHome}/Masks/${patid}_used_voxels_${FinalResTrailer}.nii.gz
endif

set Trailer = ""

pushd ASL/Volume
	rm *_cbf.nii.gz *_cbf_pairs.nii.gz
	
	@ i = 1
	while($i <= $#ASL_TI1)
	
		unset T1b
		unset pCASL
		unset Trailer
		set AcquisitionType = `grep "MRAcquisitionType" ${SubjectHome}/dicom/$ASL[$i]:r:r".json" | cut -d":" -f2 | cut -d\" -f2 | head -1`
		if(`echo $ASL[$i] | grep pasl` != "" && $AcquisitionType == "2D") then
			set T1b = 1.650
			set pCASL = 0
			set Trailer = "2dpasl"
		else if(`echo $ASL[$i] | grep pasl` != "" && $AcquisitionType == "3D") then
			echo "3D pASL detected. Sequence not supported."
			goto NEXT_RUN
			set T1b = 1.490
			set pCASL = 0
			set Trailer = "3dpasl_gse"
			
		else if($AcquisitionType == "3D") then
			set T1b = 1.490
			set pCASL = 1
			set Trailer = "3dpcasl_gse"
			
		else if($AcquisitionType == "2D") then
			set T1b = 1.650
			set pCASL = 2
			set Trailer = "2dpcasl"
		else
			goto NEXT_RUN
		endif
		
		
		matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));compute_CBF( '*_asl${i}_upck_xr3d_dc_atl.nii.gz', 'asl${i}_*.fd','${Trailer}', $ASL_PLD[$i], $T1b, $pCASL, $ASL_TI1[$i], $ASL_TR[$i], '$BrainMask', $FD_Threshold);end;exit"
		
		if($PrevSeq != $Trailer) then
			@ TypesOfSeq++
		endif
			
		set PrevSeq = $Trailer
		NEXT_RUN:
		@ i++
	end

	#make pasl mean CBF
	set images = (`ls *2dpasl*_cbf.nii.gz`)
	
	if($#images > 0) then
		fslmerge -t All_2dpasl_cbf $images
		if($status) exit 1
		
		fslmaths All_2dpasl_cbf -Tmean Mean_2dpasl_cbf
		if($status) exit 1
	endif
	
	#make pcasl mean CBF
	set images = `ls *2dpcasl*_cbf.nii.gz`
	
	if($#images > 0) then
		fslmerge -t All_2dpcasl_cbf $images
		if($status) exit 1
		
		fslmaths All_2dpcasl_cbf -Tmean Mean_2dpcasl_cbf
		if($status) exit 1
	endif
	
	set UniquePLDs = (`echo $ASL_PLD | uniq`)
	
	if($TypesOfSeq == 1 && $Trailer == "3dpcasl_gse" && $#UniquePLDs > 1) then
		echo "Detecting probably multi-PLD sequencing. Attempting to compute Weighted PLD and Mean CBF..."
		matlab -nodesktop -nosplash -softwareopengl -r "try;addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));compute_ATT_CBF( '*_asl*_upck_xr3d_dc_atl.nii.gz', [$ASL_PLD], $T1b,  '*asl*.fd', $FD_Threshold);end;exit"
	else
		#make 3D pcasl mean CBF
		set images = `ls *3dpcasl_gse*_cbf.nii.gz`
		
		if($#images >0 ) then
			fslmerge -t All_3dpcasl_gse_cbf $images
			if($status) exit 1
			
			fslmaths All_3dpcasl_gse_cbf -Tmean Mean_3dpcasl_gse_cbf
			if($status) exit 1
		endif
	endif
popd
exit 0
