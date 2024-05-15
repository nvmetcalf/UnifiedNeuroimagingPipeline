#!/bin/csh

set echo

set SubjectList = ( $1 )

#need to get the pixel bandwidth and pixel dimensionns from the json
#convert the nii.gz to a 4dfp.
#unpack the 4dfp mosaic into a 3d timeseries
#compute and insert the DwellTime into the json

foreach Subject($SubjectList)
	pushd $Subject
		set Scans = ( `find . -name "*.json" `)
		set Home = $cwd
		foreach Sequence($Scans)
			pushd $Sequence:h
				set Timepoints = `fslinfo $Sequence:t:r".nii.gz" | grep dim4 | head -1 | awk '{print $2}'`
				if( $Timepoints > 1) then
					niftigz_4dfp -4 $Sequence:t:r".nii.gz" $Sequence:t:r
					if($status) exit 1

					set SliceDim = `grep "AcquisitionMatrixPE" $Sequence:t | cut -d":" -f2 | cut -d"," -f1`

					unpack_4dfp $Sequence:t:r:r $Sequence:t:r:r"_upck" -nx$SliceDim -ny$SliceDim
					if($status) exit 1

					set Bandwidth = `grep "PixelBandwidth" $Sequence:t | cut -d":" -f2 | cut -d"," -f1`

					set DwellTime = `echo $SliceDim $Bandwidth | awk '{print(1/($1 * $2)*1000)}'`

					cat $Sequence:t | sed 's/}/,"DwellTime": '$DwellTime'\n}/' >> $Sequence:t

					niftigz_4dfp -n $Sequence:t:r:r"_upck" $Sequence:t:r:r
					if($status) exit 1

					rm *4dfp*
				endif
			popd
		end
	popd
end
