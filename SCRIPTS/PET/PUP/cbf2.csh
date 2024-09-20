#!/bin/csh

set mpr  = `~larsc/bin/getroot.csh p7417/p7417_mpr.4dfp.img`
set mpr  = `basename $mpr`
set tof  = `~larsc/bin/getroot.csh p7417/EV006_fl3d1_TOF.4dfp.img`
#set pct  = p
set ev   = EV006
set pid  = p7417
set fwhm = 6.0

set larsdir = /home/usr/larsc/programs/filter
set npdir   = /data/nil-bluearc/mintunf/mintun/NP872_EV
set tofbase = `basename $tof`

set lcoords = `gawk '/'$ev'/ {for (i = 2; i <= 7;  i++) print $i}' $npdir/Artery/Artery_Coordinates.txt`
set rcoords = `gawk '/'$ev'/ {for (i = 8; i <= 13; i++) print $i}' $npdir/Artery/Artery_Coordinates.txt`
pushd Artery

set llimits = `$larsdir/make_arterial_mask.csh $npdir/$ev/$tof $lcoords ${tofbase}_lArt`
set rlimits = `$larsdir/make_arterial_mask.csh $npdir/$ev/$tof $rcoords ${tofbase}_rArt`

$larsdir/make_filters.csh ${tofbase}_lArt ${tofbase}_lArt_halo $fwhm ${tofbase}_lArt_${fwhm}_weights ${tofbase}_lArt_halo_${fwhm}_weights
$larsdir/make_filters.csh ${tofbase}_rArt ${tofbase}_rArt_halo $fwhm ${tofbase}_rArt_${fwhm}_weights ${tofbase}_rArt_halo_${fwhm}_weights
$larsdir/make_cropped_ifh.csh $npdir/$ev/${tof}.4dfp.ifh lArt.4dfp.ifh $llimits
$larsdir/make_cropped_ifh.csh $npdir/$ev/${tof}.4dfp.ifh rArt.4dfp.ifh $rlimits

popd

pushd p7417
msktgen_4dfp $mpr 400
popd

set mode = ho

# Get whole brain TAC
	foreach s (1 2 3 4)
		t4img_4dfp ${pid}/${mpr}_to_${pid}${mode}${s}_sumall_t4 ${pid}/${mpr}_mskt Artery/${mpr}_mskt_on_${pid}${mode}${s}_sumall -O${pid}/${pid}${mode}${s}_sumall -n
		qnt_4dfp ${pid}/${pid}${mode}${s} Artery/${mpr}_mskt_on_${pid}${mode}${s}_sumall | gawk '/Mean/ {print $2}' >! Artery/${pid}${mode}${s}_whole_brain_mean.txt
	end
# Get arterial TAC

set dim = `~larsc/bin/getdim.csh ${pid}/${pid}${mode}1`
foreach s (1 2 3 4)
	foreach art (lArt rArt)
		t4img_4dfp ${pid}/${pid}${mode}${s}_sumall_to_${tofbase}_t4 ${pid}/${pid}${mode}${s}_sumall Artery/${pid}${mode}${s}_sumall_on_${tofbase}_${art} -OArtery/${art}.4dfp.ifh
		gawk '$0 !~ /matrix size \[4\]/ {print $0} /matrix size \[4\]/ {printf ("matrix size [4]\t:= %d\n", '$dim[4]')}' Artery/${art}.4dfp.ifh >! Artery/${art}_${mode}.4dfp.ifh
		t4img_4dfp ${pid}/${pid}${mode}${s}_sumall_to_${tofbase}_t4 ${pid}/${pid}${mode}${s}      Artery/${pid}${mode}${s}_on_${tofbase}_${art}      -OArtery/${art}_${mode}.4dfp.ifh
		
		qnt_4dfp -W Artery/${pid}${mode}${s}_on_${tofbase}_${art} Artery/${tofbase}_${art}_${fwhm}_weights | gawk '/Total/ {print $2}' >! Artery/tmp_${art}
		
		rm Artery/${art}_${mode}.4dfp.ifh
	end
	paste Artery/tmp_lArt Artery/tmp_rArt >! Artery/${pid}${mode}${s}_Art_${fwhm}_time-series.txt
	rm Artery/tmp_lArt Artery/tmp_rArt
end

exit 0
