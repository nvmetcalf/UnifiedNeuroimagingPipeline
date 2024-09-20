# !!!You need fsl
#  for the installation of fsl please visit https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/
#!/bin/csh

setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

source $1
source $2

set SubjectHome = $cwd

if(! -e DTI) then
	mkdir DTI
endif

#if(! $?DTI_Parcellation) then
	set DTI_Parcellation = (${PP_SCRIPTS}/Parcellation/GLParcels/reordered/MNI/GLParcels_324_reordered_w_SubCortical_volume.nii.gz ${PP_SCRIPTS}/Parcellation/SchaeferYae/MNI/Schaefer2018_100Parcels_17Networks_order_w_Subcortical_t88.nii.gz)
#endif

echo "Parcellations Used: $DTI_Parcellation"

pushd DTI
	set DSI_install_dir = /usr/local/pkg/dsistudio

 	rm -rf Deterministic
 	mkdir Deterministic
 	set DWI = $DWI[1]

 	foreach image_set($DWI)
		rm -rf tmp
 		mkdir tmp
 		echo ${SubjectHome}/dicom/${dcmroot}.${image_set}.
 		cp ${SubjectHome}/dicom/${dcmroot}.${image_set}.* tmp
 		pushd tmp
 			dcm2nii *
 			if($status) exit 1

			rm -f ${dcmroot}.${image_set}.*
 			mv * ../Deterministic
 		popd

 	end

	pushd Deterministic
 		# datain is the file that indicate the phase of acquisition
 		# 0.087 is a random number that is supposed to code the strengh of the suceptibility artefact to correct
 		# I used the same for AP and PA to indicate these distortions are equal in strengh - michelle
 		rm eddy_datain.txt
 		touch eddy_datain.txt
 		rm eddy_index.txt
 		touch eddy_index.txt
 		@ j = 1
 		foreach File(*.nii.gz)
 			echo "0 1 0 0.087" >> eddy_datain.txt
 			@ i = 1
 			set Length = `fslinfo $File | grep dim4 | head -1 | awk '{print $2}'`
 			while($i <= $Length)
 				echo $j >> eddy_index.txt
 				@ i++
 			end
 			@ j++
 		end

 		#Concatenate the three shells B300 B1000 and B2000
 		set DWI_List = (*.nii.gz)
 		fslmerge -t DWSINGLESHELL *.nii.gz
 		if($status) exit 1

 		#concatenate bvecs
 		paste *.bvec >! DWSINGLESHELL.bvecs

 		#concatenate bvals
 		paste *.bval >! DWSINGLESHELL.bvals

 		fslmaths DWSINGLESHELL -Tmean b0
 		if($status) exit 1

 		#create mask for DTI
 		fslmaths b0 -Tmean b0
 		if($status) exit 1

 		bet b0 b0_brain -m
 		if($status) exit 1

 		fslmaths b0_brain_mask -ero b0_brain_mask_ero
 		if($status) exit 1

 		niftigz_4dfp -4 b0 b0
 		if($status) exit 1

 		foreach Image($DWI_List)
 			matlab -nodesktop -nosplash -r "try;addpath(genpath('${PP_SCRIPTS}/spm12'));addpath(genpath('${PP_SCRIPTS}/matlab_scripts'));scale_DWI('b0_brain_mask_ero.nii.gz', '${Image}');end;exit"
 		end

 		fslmerge -t DWSINGLESHELL_scaled *_scaled.nii.gz

  		eddy_openmp --imain=DWSINGLESHELL.nii.gz --mask=b0_brain_mask.nii.gz --bvecs=DWSINGLESHELL.bvecs --bvals=DWSINGLESHELL.bvals --out=DWSINGLESHELL_eddy --acqp=eddy_datain.txt --index=eddy_index.txt
  		if($status) exit 1

  		eddy_openmp --imain=DWSINGLESHELL_scaled.nii.gz --mask=b0_brain_mask.nii.gz --bvecs=DWSINGLESHELL.bvecs --bvals=DWSINGLESHELL.bvals --out=DWSINGLESHELL_scaled_eddy --acqp=eddy_datain.txt --index=eddy_index.txt
  		if($status) exit 1

#		cp DWSINGLESHELL.nii.gz DWSINGLESHELL_eddy.nii.gz
#		cp DWSINGLESHELL_scaled.nii.gz DWSINGLESHELL_scaled_eddy.nii.gz

		#register the b0 to the t2 so we can get to the atlas
		set oristr = (T C S)
		set modes = (0 0 0 0 0)
		@ modes[1] = 4096 + 3
		@ modes[2] = 3072 + 3
		@ modes[3] = 2048 + 3
		@ modes[4] = 2048 + 3 + 4
		@ modes[5] = 2048 + 3 + 4

		set root = b0
		set t4file = ${root}_to_${patid}_t2wT_t4


		if($?day1_path) then
			set T2 = $day1_path/${day1_patid}_t2wT

			if(-e $day1_path/${day1_patid}_t2wT_mskt.4dfp.img) then
				set T2_mask = $day1_path/${day1_patid}_t2wT_mskt
			else
				set T2_mask = $day1_path/${day1_patid}_t2wT_brain_mask
			endif
			set MPR = $day1_path/${day1_patid}_mpr_n1_111_t88_bc
		else
			set T2 = ${SubjectHome}/atlas/${patid}_t2wT
			set T2_mask = ${SubjectHome}/atlas/${patid}_t2wT_mskt
			set MPR = ${SubjectHome}/atlas/${patid}_mpr_n1_111_t88_bc
		endif

		set log = ${root}_to_${patid}_t2w.log
		date >! $log
		@ ori = `awk '/orientation/{print $NF - 1}' ${T2}.4dfp.ifh`
		$RELEASE/t4_inv $RELEASE/$oristr[$ori]_t4 $t4file	# assume DWI is transverse
		if ($status) exit $status

		@ k = 1
		while ($k <= ${#modes})
			echo	$RELEASE/imgreg_4dfp $T2 $T2_mask ${root} none $t4file $modes[$k] >> $log
				$RELEASE/imgreg_4dfp $T2 $T2_mask ${root} none $t4file $modes[$k] >> $log
				if ($status) exit $status
			tail -14 $log
			@ k++
		end

		cp ${T2}_to_${target:t}_t4 .

		$RELEASE/t4_mul $t4file ${T2}_to_${target:t}_t4 ${root}_to_${target:t}_t4
		if ($status) exit $status

		t4_inv ${root}_to_${target:t}_t4
		if($status) exit 1

		if( -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.nii.gz) then
			niftigz_4dfp -4 ${SubjectHome}/Masks/${patid}_${MaskTrailer} ${patid}_${MaskTrailer}
			if($status) exit 1

			t4img_4dfp ${AtlasName}_to_b0_t4 ${patid}_${MaskTrailer} ${patid}_${MaskTrailer}_dwi -Ob0 -n
			if($status) exit 1

			niftigz_4dfp -n ${patid}_${MaskTrailer}_dwi ${patid}_${MaskTrailer}_dwi
			if($status) exit 1

		endif

		t4img_4dfp ${AtlasName}_to_b0_t4 $MPR ${patid}_mpr_n1_111_t88_bc_dwi -Ob0
		if($status) exit 1

		niftigz_4dfp -n ${patid}_mpr_n1_111_t88_bc_dwi ${patid}_mpr_n1_111_t88_bc_dwi
		if($status) exit 1


		foreach ParcelVolume ($DTI_Parcellation)
			niftigz_4dfp -4 $ParcelVolume:r:r `basename $ParcelVolume:r:r`
			if($status) exit 1

			t4img_4dfp ${AtlasName}_to_b0_t4 `basename $ParcelVolume:r:r` `basename $ParcelVolume:r:r`_dwi -Ob0 -n
			if($status) exit 1

			niftigz_4dfp -n `basename $ParcelVolume:r:r`_dwi `basename $ParcelVolume:r:r`_dwi
			if($status) exit 1
		end

		#create the src file
		$DSI_install_dir/dsi_studio --action=src --source=DWSINGLESHELL.nii.gz --bval=DWSINGLESHELL.bvals --bvec=DWSINGLESHELL.bvecs --output=DWSINGLESHELL.src.gz
		if(! -e DWSINGLESHELL.src.gz) exit 1

		$DSI_install_dir/dsi_studio --action=src --source=DWSINGLESHELL_scaled.nii.gz --bval=DWSINGLESHELL.bvals --bvec=DWSINGLESHELL.bvecs --output=DWSINGLESHELL_scaled.src.gz
		if(! -e DWSINGLESHELL.src.gz) exit 1

		#Compute the models
		mkdir QSDR
		ln -s ${cwd}/DWSINGLESHELL.src.gz QSDR/
		cd QSDR
			#QSDR - add other_files t1 registered to the diffusion and lesion registered to diffusion
			$DSI_install_dir/dsi_studio --action=rec --source=DWSINGLESHELL.src.gz --mask=../b0_brain_mask_ero.nii.gz --method=7 --param0=1.85 --record_odf=1 --scheme_balance=1 --num_fiber=8
		cd ..

		mkdir GQI
		ln -s ${cwd}/DWSINGLESHELL.src.gz GQI/
		cd GQI
			#GQI
			$DSI_install_dir/dsi_studio --action=rec --source=DWSINGLESHELL.src.gz --mask=../b0_brain_mask_ero.nii.gz --method=4 --param0=1.85 --record_odf=1 --scheme_balance=1 --csf_calibration=1 --num_fiber=8 --output_rdi=1
			$DSI_install_dir/dsi_studio --action=exp --source=`ls *.gqi.* | tail -1` --export=fa0,gfa
		cd ..

		mkdir Tensor
		ln -s ${cwd}/DWSINGLESHELL_scaled.src.gz Tensor/
		cd Tensor
			#DTI
			$DSI_install_dir/dsi_studio --action=rec --source=DWSINGLESHELL_scaled.src.gz --mask=../b0_brain_mask_ero.nii.gz --method=1 --scheme_balance=1 --csf_calibration=1 --num_fiber=8 --check_btable=0 --output_tensor=1
			$DSI_install_dir/dsi_studio --action=exp --source=`ls *.dti.* | tail -1` --export=fa0,rd,ad,md
		cd ..

		#cycle through all the parcellations and compute the tractography
		foreach ParcelVolume ($DTI_Parcellation)

			if( -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.nii.gz) then
				#need to get and transform the GL324 parcellation to icbm2009c
				cd QSDR
					$DSI_install_dir/dsi_studio --action=trk --source=`ls DWSINGLESHELL.*qsdr*.fib.gz | tail -1` --method=0 --roa=${cwd}/../../../Masks/${patid}_${MaskTrailer}.nii.gz --output=qsdr_tracts_`basename $ParcelVolume:r:r`.trk.gz --connectivity=$ParcelVolume --connectivity_type=end --turning_angle=60 --smoothing=0.5 --min_length=30 --max_length=400 --connectivity_value=count,mean_length --export=qa,nqa,tdi --fiber_count=500000 --step_size=1
				cd ..

				#need to compute the atlas parcellation in subject dwi space.
				cd GQI
					$DSI_install_dir/dsi_studio --action=trk --source=`ls DWSINGLESHELL.*gqi*.fib.gz | tail -1` --method=0 --roa=${cwd}/../${patid}_${MaskTrailer}_dwi.nii.gz --output=gqi_tracts_`basename $ParcelVolume:r:r`.trk.gz --connectivity=${cwd}/../`basename $ParcelVolume:r:r`_dwi.nii.gz --connectivity_type=end --turning_angle=60 --smoothing=0.5 --min_length=30 --max_length=400 --connectivity_value=count,mean_length --export=qa,nqa,tdi --fiber_count=500000 --step_size=1
				cd ..
			else
				#$DSI_install_dir/dsi_studio --action=trk --source=`ls DWSINGLESHELL.src.gz.*.fib.gz | tail -1` --method=0 --output=tracts_GL324.trk.gz --connectivity=${PP_SCRIPTS}/Parcellation/GLParcels/reordered/GLParcels_324_reordered_icbm_09c.nii.gz --connectivity_type=end --turning_angle=55 --smoothing=0 --min_length=20 --max_length=600 --connectivity_value=count,mean_length --export=qa,nqa,tdi
				cd QSDR
					$DSI_install_dir/dsi_studio --action=trk --source=`ls DWSINGLESHELL.*qsdr*.fib.gz | tail -1` --method=0 --output=qsdr_tracts_`basename $ParcelVolume:r:r`.trk.gz --connectivity=$ParcelVolume --connectivity_type=end --turning_angle=60 --smoothing=0.5 --min_length=30 --max_length=400 --connectivity_value=count,mean_length --export=qa,nqa,tdi --fiber_count=500000 --step_size=1
				cd ..

				cd GQI
					$DSI_install_dir/dsi_studio --action=trk --source=`ls DWSINGLESHELL.*gqi*.fib.gz | tail -1` --method=0 --output=gqi_tracts_`basename $ParcelVolume:r:r`.trk.gz --connectivity=${cwd}/../`basename $ParcelVolume:r:r`_dwi.nii.gz --connectivity_type=end --turning_angle=60 --smoothing=0.5 --min_length=30 --max_length=400 --connectivity_value=count,mean_length --export=qa,nqa,tdi --fiber_count=500000 --step_size=1
				cd ..
			endif
		end
	popd
popd

#do QSDR tractography
$PP_SCRIPTS/Process_DTI_deterministic_track_QSDR.csh
if($status) exit 1
