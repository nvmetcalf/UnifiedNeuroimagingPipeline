#!/bin/csh
set echo
set newatl	= 711-2V
set patlst	= $newatl.lst
set paths	= (/data/emotion2/data27/EEG_fMRI /data/emotion2/data31/EEG_fMRI /data/touch2/data5/exp3 /data/braille/data2/drum/drum_sight)
set patpath	= (      1       1       2       2       2       2       2       2       2       1       1            3            3            3      4             3)
set patid	= (VB15688 VB15744 VB15792 VB15892 VB16110 VB16348 VB16350 VB16539 VB16283 VB15341 VB15452 recog_pilot3 recog_pilot4 recog_pilot5 drum33 recall_pilot2)
set mpruse	= (      1       1       1       1       1       1       1       1       1       1       1            1            1            1      1             1)
# gender	  (      F       F       F       F       F       F       F       F       M       M       M            M            M            M      M             M)

@ n = ${#patid}
if (-e $patlst) /bin/rm $patlst
touch $patlst
###############
# find all data
###############
@ k = 1
while ($k <= $n)
	set dir = $paths[$patpath[$k]]/$patid[$k]/atlas
	echo $dir
#	ls $dir/*t4
	set t4file = $dir/*mpr*$mpruse[$k]_to_711-2B_t4
	echo "t4file="$t4file
	set mpr = `echo $t4file:t | awk '{l=index($1,"_to_");print substr($1,1,l-1)}'`
	echo "mpr="$mpr
	foreach x ($dir/$mpr.4dfp*)
		if ($patpath[$k] >= 3) then
			cp $x .
		else
			ln -s $x .
		endif
	end
	/bin/cp $t4file $mpr"_to_"$newatl"_t4"
	echo $mpr"	t4="$mpr"_to_"$newatl"_t4"	>> $patlst
	echo
	@ k++
end
cat $patlst

set echo
t4imgs_4dfp $patlst	$patlst:r"_111" -O111
ifh2hdr			$patlst:r"_111" -r1300
exit
