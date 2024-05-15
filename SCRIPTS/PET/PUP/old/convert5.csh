#!/bin/csh

setenv PATH "${PATH}:/data/nil-bluearc/raichle/suy/PPG/scripts"

set rawdir = /data/nil-bluearc/raichle/PPGdata/rawdata

set MDS = (FDG HO OO OC)
set pid = $argv[1]
if ($#argv > 1) set MDS = $argv[2-]

set dcms = `gawk '$1=="'$pid'" {for(i=2;i<=NF;i++)print $i}' dcm_dir.txt`


pushd $pid

#@ i = 1
@ i = 2
#foreach dcm ($dcms[2-])
#foreach dcm ($dcms[2])
foreach dcm ($dcms[3-])
	foreach MD ($MDS)
	foreach cdir ($MD*_v$i)
		set img = `echo $cdir | gawk '{print "'$pid'"tolower($0)}'`
		if ($MD == "OC") then
			/data/nil-bluearc/raichle/suy/scripts/IFhdr_to_4dfp $cdir"-Converted"/$cdir"-LM-00"/$cdir"-LM-00-OP_000_000.v.hdr" $img;	if ($status) exit $status
			rm $img"fz".4dfp.img
		else
			/data/nil-bluearc/raichle/suy/PPG/scripts/sif_4dfp $cdir"-Converted"/$cdir"-LM-00"/$cdir"-LM-00-OP.mhdr" $img;			if ($status) exit $status
		endif
	end
	end
	@ i ++	
end

popd

exit 0
