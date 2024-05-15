#!/bin/csh

set mapdrive = z

setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/4dfp/4dfp_cygwin64"
setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/scripts"
setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/PPG/scripts"
setenv RELEASE /cygdrive/$mapdrive/suy/4dfp/4dfp_cygwin64

set rawdir = /cygdrive/$mapdrive/PPGdata/rawdata

set MDS = (FDG HO OO OC)
set pid = $argv[1]
if ($#argv > 1) set MDS = $argv[2-]

set dcms = `gawk '$1=="'$pid'" {for(i=2;i<=NF;i++)print $i}' dcm_dir.txt`

pushd $pid

#@ i = 1
@ i = 2
#foreach dcm ($dcms[2-])
foreach dcm ($dcms[3-])
	foreach MD ($MDS)
	foreach cdir ($MD*_v$i)
#		set txt = `echo $cdir | gawk '/^FDG/{print "F18dyn"} /^[HO]O/{print "O15dyn"} /^OC/{print "O15OC"}'`
		set txt = `echo $cdir | gawk '/^FDG/{print "F18dyn"} /^[HO]O/{print "O15dyn"} /^OC/{print "O15AC"}'`
#		set txt = F18QC
		set img = `echo $cdir | gawk '{print "'$pid'"tolower($0)}'`

		if (-d $cdir"-Converted") rm -r $cdir"-Converted"
		cscript C:/JSRecon12/JSRecon12.js $cdir C:/JSRecon12/$txt.txt
		cp $img"_umap".4dfp.img $cdir"-Converted"/$cdir"-LM-00"/$cdir"-LM-00-umap.v"
		if (`echo $cdir | gawk '{if ($0~/^[HO]O/) print 1; else print 0}'`) then
			gawk 'BEGIN{go=0;stop=0} /set cmd=/{go=1} go==1&&stop==0&&$0!~/set cmd=/{print "set cmd= %cmd% --abs"; go=0; stop=1} {print $0}' $cdir"-Converted"/$cdir"-LM-00/Run-04-"$cdir"-LM-00-OP.bat" >! temp$$
			mv temp$$ $cdir"-Converted"/$cdir"-LM-00/Run-04-"$cdir"-LM-00-OP.bat"
		endif
		sed -i '/Run-05/d' $cdir"-Converted"/$cdir"-LM-00"/"Run-99-"$cdir"-LM-00-ALL.bat"
		sed -i '/FBP/d'    $cdir"-Converted"/$cdir"-LM-00"/"Run-99-"$cdir"-LM-00-ALL.bat"
		sed -i '/PSF/d'    $cdir"-Converted"/$cdir"-LM-00"/"Run-99-"$cdir"-LM-00-ALL.bat"
		$cdir"-Converted"/$cdir"-LM-00"/"Run-99-"$cdir"-LM-00-ALL.bat"
		find . -name '*sino*.s' -delete
	end
	end
	@ i ++	
end

popd

exit 0
