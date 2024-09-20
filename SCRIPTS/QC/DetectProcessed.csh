#!/bin/csh

#detect and output to a csv the processing that has been completed.
#this will only detect the end result file
# 1 means the result exists, 0 means it does not, -1 it does not exist but can

set SubjectList = $1

set Date = `date | tr '[ ]' '[_]'`

echo "ParticipantID,T1_Atl,T2_Atl,FLAIR_Atl,Myelin_Map,fMRI_Atl,fMRI_Resid_Vol,ALFF,Surfaces,Surface_fMRI,DTId_eddy,DTId_Tracts_QSDR,DTId_Tracts_GQI,DTId_Tracts_Tensor,DTIp_eddy,DTIp_modeling,DTIp_SC,ASL_Atl,ASL_CBF,LagMap,SeedCorr,Task,BOLD_Rest_6minutes,Task_80p_Resp,Task_50p_Resp,Task_20p_Resp" >! CompletedProcessing_${Date}.csv

foreach Subject($SubjectList)
	#ParticipantID
	set Row = $Subject
	unset mprs
	unset tse
	unset flair
	unset DWI
	unset ASL
	unset fstd
	
	source ${Subject}/${Subject}.params
	
	#T1_Atl
	if(-e ${Subject}/atlas/${Subject}_mpr_n1_111_t88_fnirt.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?mprs) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#T2_Atl
	if(-e ${Subject}/atlas/${Subject}_t2wT_t88_111_fnirt.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?tse) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#FLAIR_Atl
	if(-e ${Subject}/atlas/${Subject}_flair_t2wT_t88_111_fnirt.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?flair) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#Myelin_Map
	if(-e ${Subject}/atlas/$target:t/${Subject}.L.MyelinMap.32k_fs_LR.func.gii && -e ${Subject}/atlas/$target:t/${Subject}.R.MyelinMap.32k_fs_LR.func.gii) then
		set Row = ${Row}",1"
	else
		if($?mprs && $?tse) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#fMRI_Atl
	if(-e ${Subject}/FCmaps_uwrp/${Subject}_faln_dbnd_xr3d_uwrp_atl.conc) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#fMRI_Resid_Vol
	if(-e ${Subject}/FCmaps_uwrp/${Subject}_faln_dbnd_xr3d_uwrp_atl_uout_resid.conc) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#ALFF
	if(-e ${Subject}/FCmaps_uwrp/${Subject}_ALFF.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#Surfaces
	if(-e ${Subject}/atlas/$target:t/${Subject}.R.midthickness.32k_fs_LR.surf.gii && -e ${Subject}/atlas/$target:t/${Subject}.R.midthickness.32k_fs_LR.surf.gii) then
		set Row = ${Row}",1"
	else
		if($?mprs) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#Surface_fMRI
	if(-e ${Subject}/FCmaps_uwrp/${Subject}_faln_dbnd_xr3d_uwrp_atl_uout_sr_bpss.ctx.dtseries.nii) then
		set Row = ${Row}",1"
	else
		if($?fstd && $?mprs) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#DTId_eddy
	if(-e ${Subject}/DTI/Deterministic/DWIMULTISHELL_scaled_eddy.nii.gz || -e ${Subject}/DTI/Deterministic/DWSINGLESHELL_scaled.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?DWI) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#DTId_Tracts_QSDR
	if(-e ${Subject}/DTI/Deterministic/QSDR/qsdr_tracts_GL324.trk.gz.tdi.nii.gz || -e ${Subject}/DTI/Deterministic/QSDR/qsdr_tracts_GLParcels_324_reordered_w_SubCortical_volume.trk.gz.tdi.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?DWI) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#DTId_Tracts_GQI
	if(-e ${Subject}/DTI/Deterministic/GQI/gqi_tracts_GL324.trk.gz.tdi.nii.gz || -e ${Subject}/DTI/Deterministic/GQI/gqi_tracts_GLParcels_324_reordered_w_SubCortical_volume.trk.gz.tdi.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?DWI) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#DTId_Tracts_Tensor
	if(-e ${Subject}/DTI/Deterministic/Tensor/DWIMULTISHELL_scaled.src.gz.dti.fib.gz.rd.nii.gz || -e ${Subject}/DTI/Deterministic/Tensor/DWSINGLESHELL_scaled.src.gz.dti.fib.gz.md.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?DWI) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#DTIp_eddy
	if(-e ${Subject}/DTI/Probabalistic/DWIMULTISHELL_eddy.eddy_movement_rms) then
		set Row = ${Row}",1"
	else
		if($?DWI) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#DTIp_modeling
	if(-e ${Subject}/DTI/Probabalistic/bedpostxdir.bedpostX/merged_f1samples.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?DWI) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#DTIp_SC
	if(-e ${Subject}/DTI/Probabalistic/bedpostxdir.bedpostX/GLParcels_324_reordered_w_SubCortical_volume_dwi_SC/fdt_network_matrix) then
		set Row = ${Row}",1"
	else
		if($?DWI) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#ASL_Atl
	if(-e `ls ${Subject}/ASL/Volume/${Subject}_*_atl.nii.gz | tail -1`) then
		set Row = ${Row}",1"
	else
		if($?ASL) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#ASL_CBF
	if(-e `ls ${Subject}/ASL/Volume/${Subject}_*_atl_cbf.nii.gz | tail -1`) then
		set Row = ${Row}",1"
	else
		if($?ASL) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#LagMap
	if(-e ${Subject}/GS_lagmap_r8.nii) then
		set Row = ${Row}",1"
	else
		if($?DWI) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#SeedCorr
	if(-e ${Subject}/QC/${Subject}_seed_corr.mat) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#Task
	if(-e ${Subject}/Task_sm6/All_Events.nii.gz) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#BOLD_Rest_6minues
	if(`cat ${Subject}/movement/rest_frames_remaining.txt | awk '{if($1 > 360) print("1"); else print("0");}'` == 1) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#Task_80p_Resp
	set Run1 = `cat ../Behavioral_Data/Task/${Subject}/score_${Subject}_parameters_run1_log.txt | head -1 | cut -f4 | cut -d" " -f1`
	set Run2 = `cat ../Behavioral_Data/Task/${Subject}/score_${Subject}_parameters_run2_log.txt | head -1 | cut -f4 | cut -d" " -f1`
	set Average = `echo $Run1 $Run2 | awk '{if($1 > 0 && $2 > 0) print(($1+$2)/2); else print($1+$2);}'`
	
	set Result = `echo $Average | awk '{if($1 > 80) print("1");}'`
	
	if( $Result == 1) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#Task_50p_Resp
	set Result = `echo $Average | awk '{if($1 > 50) print("1");}'`
	
	if( $Result == 1) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	#Task_20p_Resp
	set Result = `echo $Average | awk '{if($1 > 20) print("1");}'`
	
	if( $Result == 1) then
		set Row = ${Row}",1"
	else
		if($?fstd) then
			set Row = ${Row}",-1"
		else
			set Row = ${Row}",0"
		endif
	endif
	
	echo $Row >> CompletedProcessing_${Date}.csv
end