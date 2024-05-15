# !!!You need fsl
#  for the installation of fsl please visit https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/

setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

source $1
source $2

set SubjectHome = $cwd

if(! -e DTI) then
	mkdir DTI
endif

echo "Parcellations Used: $DTI_Parcellation"

pushd DTI
	set DSI_install_dir = $PP_SCRIPTS/dsistudio

 	rm -rf Deterministic
 	mkdir Deterministic
	pushd Deterministic
		# datain is the file that indicate the phase of acquisition and dwell
 		touch datain.txt
 		touch eddy_index.txt
 		
		@ i = 1
 		while($i <= $#DTI_ped)
			if($DTI_ped[$i] == "-y") then
				echo "0 -1 0 $DTI_dwell[$i]" >> datain.txt
				echo 2 >> eddy_index.txt
			else
				echo "0 1 0 $DTI_dwell[$i]" >> datain.txt
				echo 1 >> eddy_index.txt
			endif
			@ i++
 		end

 		#Applying topup
 		#This distortion correction transform could have been created from any modality.
 		#so we will compute the 6dof transform from the corrected source field corrected 
 		#image to each of the images we are wanting to distortion correct. This method is 
 		#from the fsl topup documentation. Only topup type field maps are possible currently
 		#with DTI.  https://www.fmrib.ox.ac.uk/primers/intro_primer/ExBox20/IntroBox20.html
 		
 		@ i = 1
 		
 		set bvec_list = ()
 		set bval_list = ()
 		set DTI_list = ()
 		
 		while($i <= $#DWI) 
 		
			#split the DTI directions and use the vol0000.nii.gz as the target for the registration
			fslsplit ${SubjectHome}/dicom/$DWI[$i] -t
			if($status) exit 1
			
			mkdir ${SubjectHome}/Anatomical/Volume/DTI${i}_ref
			
			gunzip -f vol0000.nii.gz
			if($status) exit 1
			
			cp vol0000.nii ${SubjectHome}/Anatomical/Volume/DTI${i}_ref/${patid}_DTI${i}_ref_distorted.nii
			if($status) exit 1
			
			pushd $SubjectHome
				$PP_SCRIPTS/SurfacePipeline/ComputeDistortionCorrection.csh $1 $2 $SubjectHome DTI${i} $DTI_dwell[$i] $DTI_TE[$i] $DTI_ped[$i]
				if($status) exit 1
			popd
			
# 			flirt -in ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI${i}/Topup_DistortionCorrected_Ref.nii.gz -ref vol0000.nii.gz -omat ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI${i}/Topup_DistortionCorrected_Ref_to_DTI${i}.mat -dof 6
# 			if($status) exit 1
# 			
# 			flirt -in ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI${i}/topupfield_fieldcoef.nii.gz -ref vol0000.nii.gz -applyxfm -init ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI${i}/Topup_DistortionCorrected_Ref_to_DTI${i}.mat -interp spline -out ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI${i}/topupfield_fieldcoef_on_DTI${i}.nii.gz
# 			if($status) exit 1
# 			
# 			applytopup -i ${SubjectHome}/dicom/$DWI[$i] -t ${SubjectHome}/Anatomical/Volume/FieldMapping_DTI${i}/topupfield_fieldcoef_on_DTI${i} -a datain.txt -x 2 -m jac -n spline -o DTI${i}
# 			if($status) exit 1
			
			set bvec_list = ($bvec_list ${SubjectHome}/dicom/$DWI[$i]:r:r".bvec")
			set bval_list = ($bval_list ${SubjectHome}/dicom/$DWI[$i]:r:r".bval")
			set DTI_list = ($DTI_list DTI${i}.nii.gz)
			
			rm vol*.nii.gz
 		end
 		
 		#Concatenate the three shells B300 B1000 and B2000
 		fslmerge -t DWI_STACK $DTI_list
 		if($status) exit 1

 		#concatenate bvecs
 		paste $bvec_list >! DWI_STACK.bvec

 		#concatenate bvals
 		paste $bval_list  >! DWI_STACK.bvals

 		#create mask for DTI
 		fslmaths DWI_STACK -Tmean b0
 		if($status) exit 1

 		bet b0 b0_brain -m
 		if($status) exit 1

 		fslmaths b0_brain_mask -ero b0_eddy_brain_mask_ero
 		if($status) exit 1

		#do eddy correction
 		eddy_openmp --imain=DWI_STACK.nii.gz --mask=b0_brain_mask.nii.gz --bvecs=DWI_STACK.bvec --bvals=DWI_STACK.bvals --out=DWI_STACK_eddy --acqp=datain.txt --index=eddy_index.txt --data_is_shelled
 		if($status) exit 1

 		fslmaths DWI_STACK_eddy -Tmean b0_eddy
 		if($status) exit 1
 		
 		bet b0_eddy b0_eddy_brain -m
 		if($status) exit 1

 		fslmaths b0_eddy_brain_mask -ero b0_eddy_brain_mask_ero
 		if($status) exit 1
 		
		#register the b0 to the t1
		epi_reg --epi=b0_eddy.nii.gz --t1=${SubjectHome}/Anatomical/Volume/T1/${patid}_T1 --t1brain=${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_brain_restore.nii.gz --out=b0_eddy_to_T1 --noclean
		if($status) exit 1

		convert_xfm -omat b0_eddy_to_${AtlasName}.mat -concat ${SubjectHome}/Anatomical/Volume/T1/${patid}_T1_to_${AtlasName}.mat b0_eddy_to_T1.mat
		if($status) exit 1
		
		convert_xfm -omat ${AtlasName}_to_b0.mat -inverse b0_eddy_to_${AtlasName}.mat
		if($status) exit 1
		
		if( -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.nii.gz) then
			flirt -in ${SubjectHome}/Masks/${patid}_${MaskTrailer} -ref b0_eddy -out ${patid}_${MaskTrailer}_dwi -init ${AtlasName}_to_b0.mat -applyxfm
			if($status) exit 1
		endif

		foreach ParcelVolume ($DTI_Parcellation)
			flirt -in $ParcelVolume -ref b0_eddy -out $ParcelVolume:r:r"_dwi" -init ${AtlasName}_to_b0.mat -applyxfm 
			if($status) exit 1
		end

		#create the src file
		$DSI_install_dir/dsi_studio --action=src --source=DWI_STACK_eddy.nii.gz --bval=DWI_STACK.bvals --bvec=DWI_STACK_eddy.bvec --output=DWI_STACK_eddy.src.gz
		if(! -e DWI_STACK_eddy.src.gz) exit 1

		#Compute the models
		mkdir QSDR
		ln -s ${cwd}/DWI_STACK_eddy.src.gz QSDR/
		cd QSDR
			#QSDR - add other_files t1 registered to the diffusion and lesion registered to diffusion
			$DSI_install_dir/dsi_studio --action=rec --source=DWI_STACK_eddy.src.gz --mask=../b0_eddy_brain_mask_ero.nii.gz --method=7 --param0=1.85 --record_odf=1 --scheme_balance=1 --num_fiber=8
		cd ..

		mkdir GQI
		ln -s ${cwd}/DWI_STACK_eddy.src.gz GQI/
		cd GQI
			#GQI
			$DSI_install_dir/dsi_studio --action=rec --source=DWI_STACK_eddy.src.gz --mask=../b0_eddy_brain_mask_ero.nii.gz --method=4 --param0=1.85 --record_odf=1 --scheme_balance=1 --csf_calibration=1 --num_fiber=8 --output_rdi=1
			$DSI_install_dir/dsi_studio --action=exp --source=`ls *.gqi.* | tail -1` --export=fa0,gfa
		cd ..

		mkdir Tensor
		ln -s ${cwd}/DWI_STACK_eddy_scaled.src.gz Tensor/
		cd Tensor
			#DTI
			$DSI_install_dir/dsi_studio --action=rec --source=DWI_STACK_eddy_scaled.src.gz --mask=../b0_eddy_brain_mask_ero.nii.gz --method=1 --scheme_balance=1 --csf_calibration=1 --num_fiber=8 --check_btable=0 --output_tensor=1
			$DSI_install_dir/dsi_studio --action=exp --source=`ls *.dti.* | tail -1` --export=fa0,rd,ad,md
		cd ..

		#cycle through all the parcellations and compute the tractography
		foreach ParcelVolume ($DTI_Parcellation)

			if( -e ${SubjectHome}/Masks/${patid}_${MaskTrailer}.nii.gz) then
				#need to get and transform the GL324 parcellation to icbm2009c
				cd QSDR
					$DSI_install_dir/dsi_studio --action=trk --source=`ls DWI_STACK_eddy.*qsdr*.fib.gz | tail -1` --method=0 --roa=${SubjectHome}/Masks/${patid}_${MaskTrailer}.nii.gz --output=qsdr_tracts_`basename $ParcelVolume:r:r`.trk.gz --connectivity=$ParcelVolume --connectivity_type=end --turning_angle=60 --smoothing=0.5 --min_length=30 --max_length=400 --connectivity_value=count,mean_length --export=qa,nqa,tdi --fiber_count=500000 --step_size=1
				cd ..

				#need to compute the atlas parcellation in subject dwi space.
				cd GQI
					$DSI_install_dir/dsi_studio --action=trk --source=`ls DWI_STACK_eddy.*gqi*.fib.gz | tail -1` --method=0 --roa=${cwd}/../${patid}_${MaskTrailer}_dwi.nii.gz --output=gqi_tracts_`basename $ParcelVolume:r:r`.trk.gz --connectivity=${cwd}/../`basename $ParcelVolume:r:r`_dwi.nii.gz --connectivity_type=end --turning_angle=60 --smoothing=0.5 --min_length=30 --max_length=400 --connectivity_value=count,mean_length --export=qa,nqa,tdi --fiber_count=500000 --step_size=1
				cd ..
			else
				#$DSI_install_dir/dsi_studio --action=trk --source=`ls DWI_STACK_eddy.src.gz.*.fib.gz | tail -1` --method=0 --output=tracts_GL324.trk.gz --connectivity=${PP_SCRIPTS}/Parcellation/GLParcels/reordered/GLParcels_324_reordered_icbm_09c.nii.gz --connectivity_type=end --turning_angle=55 --smoothing=0 --min_length=20 --max_length=600 --connectivity_value=count,mean_length --export=qa,nqa,tdi
				cd QSDR
					$DSI_install_dir/dsi_studio --action=trk --source=`ls DWI_STACK_eddy.*qsdr*.fib.gz | tail -1` --method=0 --output=qsdr_tracts_`basename $ParcelVolume:r:r`.trk.gz --connectivity=$ParcelVolume --connectivity_type=end --turning_angle=60 --smoothing=0.5 --min_length=30 --max_length=400 --connectivity_value=count,mean_length --export=qa,nqa,tdi --fiber_count=500000 --step_size=1
				cd ..

				cd GQI
					$DSI_install_dir/dsi_studio --action=trk --source=`ls DWI_STACK_eddy.*gqi*.fib.gz | tail -1` --method=0 --output=gqi_tracts_`basename $ParcelVolume:r:r`.trk.gz --connectivity=${cwd}/../`basename $ParcelVolume:r:r`_dwi.nii.gz --connectivity_type=end --turning_angle=60 --smoothing=0.5 --min_length=30 --max_length=400 --connectivity_value=count,mean_length --export=qa,nqa,tdi --fiber_count=500000 --step_size=1
				cd ..
			endif
		end
	popd

popd

#do QSDR tractography
$PP_SCRIPTS/Process_DTI_deterministic_track_QSDR.csh
if($status) exit 1
