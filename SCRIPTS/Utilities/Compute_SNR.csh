#!/bin/csh

if($#argv != 1) then
	echo "Compute_SNR.csh <timeseries>"
	exit 1
endif

set NoiseVolume = $1:r:r"_Noise"
set SNR_Volume = $1:r:r"_SNR"

fslmaths $1 -Tmean $NoiseVolume
if($status) exit 1

fslmaths $1 -Tstd -div $NoiseVolume $SNR_Volume
if($status) exit 1

exit 0
