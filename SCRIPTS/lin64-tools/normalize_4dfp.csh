#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/normalize_4dfp.csh,v 1.5 2021/03/19 08:38:54 avi Exp $
#$Log: normalize_4dfp.csh,v $
# Revision 1.5  2021/03/19  08:38:54  avi
# do not exit on unrecognized option
#
# Revision 1.4  2020/09/29  22:17:38  avi
# correct command line parsing
#
# Revision 1.3  2020/07/23  03:31:10  avi
# correct argument parsing, check input file existence, enable maksing option -m
#
# Revision 1.2  2020/05/06  05:10:59  avi
# generalize to work on single volume input
#
# Revision 1.1  2019/08/19  02:47:46  avi
# Initial revision
#
# Revision 1.3  2018/10/25  05:13:17  avi
# invoke mode1000_4dfp on $RELEASE
#
# Revision 1.2  2018/10/25  04:17:52  avi
# option -f (suppress excecution of csh initialization)
#
# Revision 1.1  2018/10/25  04:13:29  avi
# Initial revision
#
set program = $0; set program = $program:t

@ n = ${#argv}
@ nskip = 0
set mask = ""
if ($n < 1) goto USAGE
@ k = 0
@ i = 1
while ($i <= $#argv)
	@ isswitch = `echo $argv[$i] | awk '/^-/{k++;};END{print k+0}'`
	if ($isswitch) then
		set swi = `echo $argv[$i] | awk '{print substr($1,2,1)}'`
		set arg = `echo $argv[$i] | awk '{print substr($1,3)}'`
		switch ($swi)
			case h:
						breaksw:	# redundant but not an error
			case e:
			set echo;		breaksw;
			case n:
			@ nskip = $arg;		breaksw;
			case m
			set mask = $arg;	breaksw;
			default:
			echo $program warning: option -$swi not recognized
		endsw
	else
		switch ($k)
			case 0:
			set file = $argv[$i];	@ k++; breaksw;
			default:		
						breaksw;
		endsw
	endif
	@ i++
end
echo "nskip="$nskip
echo "file="$file

if ($file:e == "img")  set file = $file:r
if ($file:e == "4dfp") set file = $file:r
if (! -e $file.4dfp.img || ! -e $file.4dfp.ifh) then
	echo $file not found
	exit -1
endif
@ nframe = `cat $file.4dfp.ifh | awk '/matrix size \[4\]/{print $NF}'`
if ($nframe > 1) then
	set format = `echo $nframe $nskip | gawk '{printf("%dx%d+", $2, $1-$2);}'`
	actmapf_4dfp $format $file -aavg
	set F = ${file}_avg
else
	set F = $file
endif

if ($mask != "") then
	set mskstr = -m$mask
else
	set mskstr = ""
endif
set minval = `qnt_4dfp $F $F | gawk '/Mean/{print $NF/10}'`
echo $program "minval="$minval
img_hist_4dfp -t$minval $F -x -$mskstr		> /dev/null
set maxval = `tail -1  $F.xtile | gawk '{print $NF}'`
echo $program "maxval="$maxval
img_hist_4dfp -r${minval}to${maxval} $F -h	> /dev/null
mode1000_4dfp -r${minval}to${maxval} $F -h

if ($nframe > 1) then
#########################################################
# apply mode 1000 normalization to volumetric time series
#########################################################
	set f = `head ${F}_norm.4dfp.img.rec | awk '/original/{print 1000/$NF}'`
	scale_4dfp $file $f -anorm
endif

if ($mask != "") then
	echo mask = $mask
	set mean = `qnt_4dfp ${F}_norm $mask | gawk '/Mean/{print $NF;}'`
	echo masked image mean = $mean
endif

exit 0
USAGE:
echo "Usage:	$program <4dfp>"
echo " e.g.,	$program 1409b_b_HDIRF2_faln_dbnd_r3d_avg"
echo " e.g.,	$program SD10017_1_run1_xr3d_atl_Sfit -n4"
echo "	options"
echo "	-n<int>	specify number of pre-functional frames (default 0)"
echo "	-m<str>	evaluate normalized image mean within spoecified mask"
echo " N.B.:	$program always greates a histogram (option -h in compiled normalize_4dfp)"
exit 1
