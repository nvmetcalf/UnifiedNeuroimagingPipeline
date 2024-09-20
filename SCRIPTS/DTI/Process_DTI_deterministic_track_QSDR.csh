#!/bin/csh
set echo
set DSI_install_dir = /usr/local/pkg/dsistudio
setenv MKL_THREADING_LAYER GNU
setenv OMP_NUM_THREADS 6

set SubjectHome = $cwd

if(! -e DTI/Deterministic/QSDR) then
	echo "Cannot perform QSDR tracking as QSDR folder does not exist!"
	exit 1
endif

pushd DTI/Deterministic/QSDR

	set Source = ${cwd}/`ls *.fib.gz | tail -1`

	echo "Using Source: $Source"

	rm -rf Tracking
	mkdir Tracking
	cd Tracking

		@ i = 0
		while($i <= 79)

			if($i < 10) then
				set TrackIndex = "0"$i
			else
				set TrackIndex = $i
			endif

			set ParcelName = `grep $TrackIndex $PP_SCRIPTS/SurfacePipeline/HCP842_tractography.txt | cut -f2`
			set ParcelName = `echo $ParcelName`

			echo $ParcelName
			set OutputFile = "${TrackIndex}_${ParcelName}.trk.gz"
			echo "Outputfile: $OutputFile"

			echo "/usr/local/pkg/dsistudio/dsi_studio --action=trk --source=${Source} --seed_count=1000000 --track_id=${TrackIndex} --output=$OutputFile"

			$DSI_install_dir/dsi_studio --action=trk --source=${Source} --seed_count=1000000 --track_id=${TrackIndex} --output=${cwd}/${OutputFile}

			@ i ++
		end
	cd ..
popd
