#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/prm2grpstr.csh,v 1.3 2018/08/17 05:52:07 avi Exp $
#$Log: prm2grpstr.csh,v $
# Revision 1.3  2018/08/17  05:52:07  avi
# invoke with -f
#
# Revision 1.2  2012/09/07  00:19:19  avi
# immunize against lines
#
# Revision 1.1  2010/08/27  00:47:54  avi
# Initial revision
#
set program = $0; set program = $program:t
set idstr = '$Id: prm2grpstr.csh,v 1.3 2018/08/17 05:52:07 avi Exp $'
echo $idstr

if ($#argv < 1) then
	echo "Usage:	"$program"	<DTI_prm_file>"
	echo " e.g.,	"$program"	17+16+15_b1200_NOreorder.prm"
	exit 1
endif

gawk '$1!~/#/ && NF>0{if (l) print;l++}' $1 >! temp$$.0
gawk '$1!~/#/ && NF>0{l++;printf("%5d%10.6f%10.6f\n",l,exp(-.001*$1),exp(-.003*$1))}' temp$$.0 >! temp$$.1

set out = $1:t; set out = $out:r
echo $program $argv[1-]						>! $out.sorted
echo $USER `date` `uname -nm`					>> $out.sorted
echo | gawk '{printf("%5s%10s%10s\n","vol","D=1","D=3")}'	>> $out.sorted
sort -r -n -k 2,2 temp$$.1					>> $out.sorted
cat								   $out.sorted
/bin/rm temp$$.*

exit 0
