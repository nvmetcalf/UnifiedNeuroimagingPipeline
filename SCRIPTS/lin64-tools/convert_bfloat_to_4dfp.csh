#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/convert_bfloat_to_4dfp.csh,v 1.6 2018/08/17 05:34:28 avi Exp $
#$Log: convert_bfloat_to_4dfp.csh,v $
# Revision 1.6  2018/08/17  05:34:28  avi
# invoke with -f
#
# Revision 1.5  2010/08/31  21:22:16  avi
# correct ifh2hdr call
#
# Revision 1.4  2010/08/30  02:39:03  avi
# donot assume coronal acquisition
#
# Revision 1.3  2010/08/28  06:30:36  avi
# 2-argument usage
#
# Revision 1.2  2010/08/28  05:48:24  avi
# get image dimensions from BRIK
#
# Revision 1.1  2010/08/25  06:28:56  avi
# Initial revision
#
set idstr = '$Id: convert_bfloat_to_4dfp.csh,v 1.6 2018/08/17 05:34:28 avi Exp $'
echo $idstr
set program = $0
set program = $program:t

#set echo

echo $program
if ($#argv < 2) goto Usage
set root	= $1
set out		= $2

if (! -e $out.4dfp.ifh) then
	echo $out.4dfp.ifh not found
	exit -1
endif

foreach comp (_r _i f t)
	set file = ${out}$comp.4dfp.img
	echo Writing: $file
	if (-e $file) /bin/rm $file
	touch $file
	@ k = 0
	while ($k < 30)
		set str = `echo $k | awk '{printf("%03d", $1)}'`
#	echo	cat $root$comp"_"$str.bfloat
		cat $root$comp"_"$str.bfloat >> $file
		if ($status) exit $status
		@ k++
	end
	cat $out.4dfp.ifh | gawk '/matrix size \[4\]/{$NF=1};{print;}' >! ${out}$comp.4dfp.ifh
	ifh2hdr ${out}$comp -r-50to50
end

exit 0

Usage:
echo "Usage:	"$program" <bfloat root> <(4dfp) outroot>"
echo " e.g.:	"$program" allegra-VA3933-03-retinotopia-ecc-log-partialbrain+orig 88_100316CR_1-ecc-log-partial-brain"
echo "N.B.:	"$program" assumes that all bfloat files correspond to an already converted AFNI BRIK"
exit 1
