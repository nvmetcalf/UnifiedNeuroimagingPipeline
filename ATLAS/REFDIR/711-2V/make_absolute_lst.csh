#!/bin/csh

foreach x (VB15688_mpr1 VB15744_mpr1 VB15792_mpr1 VB15892_mpr1 VB16110_mpr1 VB16348_mpr1 VB16350_mpr1 VB16539_mpr1 VB16283_mpr1 VB15341_mpr1 VB15452_mpr1 recog_pilot3_mpr1 recog_pilot4_mpr1 recog_pilot5_mpr1 drum33_mpr1 recall_pilot2_mpr1)
	set file = `ls -l $x.4dfp.img | awk '{print $NF}'`
#	ls -l $file.rec
	echo $file
end

exit
