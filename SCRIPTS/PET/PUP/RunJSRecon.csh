#!/bin/csh
#$Header$
#$Log$

#set echo

set idstr   = '$Id$'
echo $idstr
set program = $0
set program = $program:t

set mapdrive = z

@ i = 1
@ j = 0
while ($i <= ${#argv})
	switch ($argv[$i])
	case -ui:
		@ i ++
		set umapi = `echo $argv[$i] | gawk '{sub(/\.4dfp(\.(hdr|ifh|img(\.rec)?)?)?/,""); print $0}'`
		breaksw
	case -uo:
		@ i ++
		set umapo = `echo $argv[$i] | gawk '{sub(/\.4dfp(\.(hdr|ifh|img(\.rec)?)?)?/,""); print $0}'`
		breaksw
	case -o:
		@ i ++
		set imgo  = `echo $argv[$i] | gawk '{sub(/\.4dfp(\.(hdr|ifh|img(\.rec)?)?)?/,""); print $0}'`
		breaksw
	case -m:
		@ i ++
		set mapdrive = $argv[$i]
		breaksw
	default:
		switch ($j)
		case 0:
			@ j ++
			set indir  = $argv[$i]
			breaksw
		case 1:
			@ j ++
			set txt    = $argv[$i]
			breaksw
		endsw
		breaksw
	endsw
	@ i ++
end
if ($j != 2) then
        echo "Usage:    $program <input directory> <recon text (F18dyn|C11dyn|O15dyn|O15AC|O15NAC).txt>"
	echo " e.g.:	$program FDG_V2 O15NAC.txt -uo NP995_10fdg_v2_umap -o NP995_10fdg_v2_NAC"
	echo " e.g.:	$program FDG_V2 F18dyn.txt -ui NP995_10fdg_v2_umap -o NP995_10fdg_v2_AC"
	echo " options"
	echo " -ui <umap(4dfp)>	   overwrite umap .v file in umap subdirectory with supplied 4dfp"
	echo " -uo <umap(4dfp)>    save umap created by JSRecon12 as 4dfp in working directory"
	echo " -o  <output(4dfp)>  save converted image as 4dfp in working directory"
	echo " -m  <drive name>    name of drive mapped to /data/nil-bluearc/raichle (default: $mapdrive)"
        exit 1
endif

set mapdrive = /cygdrive/$mapdrive

setenv PATH "$mapdrive/suy/4dfp/4dfp_cygwin64:${PATH}"
#setenv PATH "$mapdrive/suy/scripts:${PATH}"
setenv PATH "$mapdrive/suy/PPG/scripts:${PATH}"
setenv RELEASE $mapdrive/suy/4dfp/4dfp_cygwin64

set outdir = $indir"-Converted"
set subdir = $indir"-LM-00"

if (! -e C:/JSRecon12/$txt) then
	echo "${program}: $txt not found in C:/JSRecon12"
	exit -1
endif

if (-d $outdir) rm -r $outdir
cscript C:/JSRecon12/JSRecon12.js $indir C:/JSRecon12/$txt;			if ($status) exit $status

if ($?umapi) then
	cp $umapi.4dfp.img $outdir/$subdir/$subdir"-umap.v";			if ($status) exit $status
endif

if ($txt == "O15dyn.txt") then
	gawk 'BEGIN{go=0;stop=0} /set cmd=/{go=1} go==1&&stop==0&&$0!~/set cmd=/{print "set cmd= %cmd% --abs"; go=0; stop=1} {print $0}' \
		  $outdir/$subdir/Run-04-$subdir"-OP.bat" >! temp$$
	mv temp$$ $outdir/$subdir/Run-04-$subdir"-OP.bat"
endif
sed -i '/Run-05/d' $outdir/$subdir/"Run-99-"$subdir"-ALL.bat";				if ($status) exit $status
chmod 777 $outdir/$subdir/"Run-99-"$subdir"-ALL.bat"
if ($txt != "O15NAC.txt") then
	sed -i '/FBP/d'    $outdir/$subdir/"Run-99-"$subdir"-ALL.bat";			if ($status) exit $status
	chmod 777 $outdir/$subdir/"Run-99-"$subdir"-ALL.bat"
	sed -i '/PSF/d'    $outdir/$subdir/"Run-99-"$subdir"-ALL.bat";			if ($status) exit $status
	chmod 777 $outdir/$subdir/"Run-99-"$subdir"-ALL.bat"
endif
#chmod 744 $outdir/$subdir/"Run-99-"$subdir"-ALL.bat";					if ($status) exit $status
$outdir/$subdir/"Run-99-"$subdir"-ALL.bat";						if ($status) exit $status
find $outdir -name '*sino*.s' -delete

if ($?imgo) then
	if (`echo $txt | gawk '/dyn/{print 1} $0!~/dyn/{print 0}'`) then
		sif_4dfp $outdir/$subdir/$subdir"-OP.mhdr" $imgo;			if ($status) exit $status
		#########Check number of frames
	else if ($txt == "O15NAC.txt") then
		IFhdr_to_4dfp $outdir/$subdir/$subdir"-FBP_000_000.v.hdr" $imgo;	if ($status) exit $status
		rm -f $imgo"fz".4dfp.*
	else
		IFhdr_to_4dfp $outdir/$subdir/$subdir"-OP_000_000.v.hdr" $imgo;		if ($status) exit $status
		rm -f $imgo"fz".4dfp.*
	endif	
endif
if ($?umapo) then
	IFhdr_to_4dfp $outdir/$subdir/$subdir"-umap.v.hdr" $umapo;		if ($status) exit $status
	rm -f $umapo"fz".4dfp.*
endif

exit 0