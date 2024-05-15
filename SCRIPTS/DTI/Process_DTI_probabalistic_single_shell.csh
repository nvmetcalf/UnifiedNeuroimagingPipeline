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

pushd DTI

	rm -rf Probabalistic
	mkdir Probabalistic

	pushd Probabalistic
		# datain is the file that indicate the phase of acquisition
		# 0.087 is a random number that is supposed to code the strengh of the suceptibility artefact to correct
		# I used the same for AP and PA to indicate these distortions are equal in strengh
		
		
		#setup the files for the eddy correction
		rm eddy_datain.txt
		touch eddy_datain.txt
		rm eddy_index.txt
		touch eddy_index.txt
		@ j = 1
		foreach File(*.nii.gz)
		
			echo "0 1 0 0.087" >! eddy_datain.txt
			@ i = 1
			set Length = `fslinfo $File | grep dim4 | head -1 | awk '{print $2}'`
			while($i <= $Length)
				echo $j >> eddy_index.txt
				@ i++
			end
			@ j++
		end
		
		#Concatenate the three shells B300 B1000 and B2000
		fslmerge -t DWSINGLESHELL *.nii.gz
		if($status) exit 1

		#concatenate bvecs
		paste *.bvec >! DWSINGLESHELL.bvecs

		#concatenate bvals
		paste *.bval >! DWSINGLESHELL.bvals
		
		fslmaths DWSINGLESHELL -Tmean b0
		if($status) exit 1
		
		bet b0 b0_brain -m
		if($status) exit 1
		
		eddy_openmp --imain=DWSINGLESHELL.nii.gz --mask=b0_brain_mask.nii.gz --bvecs=DWSINGLESHELL.bvecs --bvals=DWSINGLESHELL.bvals --out=DWSINGLESHELL_eddy --acqp=eddy_datain.txt --index=eddy_index.txt
		if($status) exit 1
		
		dtifit -k DWSINGLESHELL_eddy.nii.gz -o DWI -m b0_brain_mask.nii.gz -r DWSINGLESHELL.bvecs -b DWSINGLESHELL.bvals
		if($status) exit 1
		
		rm -rf bedpostxdir
		mkdir bedpostxdir
		#bet T1wMPR.nii.gz T1wMPR_brain.nii.gz
		bet ${SubjectHome}/atlas/${patid}_mpr1.nii.gz T1wMPR_brain.nii.gz
		if($status) exit 1

		mv DWSINGLESHELL_eddy.nii.gz bedpostxdir/data.nii.gz
		mv DWSINGLESHELL.bvecs bedpostxdir/bvecs
		mv DWSINGLESHELL.bvals bedpostxdir/bvals
		mv b0_brain.nii.gz bedpostxdir/nodif_brain.nii.gz
		mv b0_brain_mask.nii.gz bedpostxdir/nodif_brain_mask.nii.gz
		cp ${SubjectHome}/atlas/${patid}_mpr1.nii.gz bedpostxdir/T1wMPR.nii.gz
		mv T1wMPR_brain.nii.gz bedpostxdir/T1wMPR_brain.nii.gz
		bedpostx bedpostxdir --nf=3 --fudge=1  --bi=1000 --model=3 --rician
		if($status) exit 1
		
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
	
		set log = ${root}_to_${patid}_t2w.log
		date >! $log
		@ ori = `awk '/orientation/{print $NF - 1}' ../../atlas/${patid}_t2wT.4dfp.ifh`
		$RELEASE/t4_inv $RELEASE/$oristr[$ori]_t4 $t4file	# assume DWI is transverse
		if ($status) exit $status

		@ k = 1
		while ($k <= ${#modes})
			echo	$RELEASE/imgreg_4dfp ../../atlas/${patid}_t2wT ../../atlas/${patid}_t2wT_mskt ${root} none $t4file $modes[$k] >> $log
				$RELEASE/imgreg_4dfp ../../atlas/${patid}_t2wT ../../atlas/${patid}_t2wT_mskt ${root} none $t4file $modes[$k] >> $log
				if ($status) exit $status
			tail -14 $log
			@ k++
		end
		
		cp ../../atlas/${patid}_t2wT_to_${target:t}_t4 .
		
		$RELEASE/t4_mul $t4file ${patid}_t2wT_to_${target:t}_t4 ${root}_to_${target:t}_t4
		if ($status) exit $status
		
		t4_inv ${root}_to_${target:t}_t4
		if($status) exit 1
	popd
popd

$PP_SCRIPTS/SurfacePipeline/Run_DTI_ProbabalisticTractography.csh $1 $2
