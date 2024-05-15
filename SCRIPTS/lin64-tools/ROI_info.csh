#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/ROI_info.csh,v 1.9 2018/08/17 05:27:15 avi Exp $
#$Log: ROI_info.csh,v $
# Revision 1.9  2018/08/17  05:27:15  avi
# invoke with -f
#
# Revision 1.8  2014/08/06  01:44:37  avi
# handle multi-volume ROI files
#
# Revision 1.7  2010/04/22  03:06:15  avi
# correct voxel count computaion in peak_4dfp case
#
# Revision 1.6  2010/04/16  03:41:19  avi
# correct missing "case " string
#
# Revision 1.5  2010/04/15  03:37:27  avi
# automate determination of ROI_type
#
# Revision 1.4  2010/04/15  02:18:13  avi
# option -r (analyze ROI_resolve_4dfp output)
#
# Revision 1.3  2009/10/06  04:05:15  avi
# correct -b option logic
#
# Revision 1.2  2009/10/06  01:34:44  avi
# option -b
#
# Revision 1.1  2009/10/05  23:47:31  avi
# Initial revision
#
set rcsid = '$Id: ROI_info.csh,v 1.9 2018/08/17 05:27:15 avi Exp $'
#echo $rcsid
set program = $0; set program = $program:t
if (${#argv} < 1) goto USAGE

@ debug = 0
#set echo

@ ivol = 1
@ k = 0
@ m = 1
while ($m <= ${#argv})
	set swi = `echo $argv[$m] | awk '{print substr($1,1,2)}'`
	set arg = `echo $argv[$m] | awk '{print substr($0,3)}'`
	switch ($swi)
	case -b:
		set ROI_type = burn_sphere_4dfp;	breaksw;
	case -r:
		set ROI_type = ROI_resolve_4dfp;	breaksw;
	case -p:
		set ROI_type = peak_4dfp;		breaksw;
	case -f:
		@ ivol = $arg;				breaksw;
	default:
		if (! $k) set file = $argv[$m];
		if ($file:e == "ifh")	set file = $file:r
		if ($file:e == "img")	set file = $file:r
		if ($file:e == "4dfp")	set file = $file:r
		@ k++
		breaksw;
	endsw
	@ m++
end
if ($k < 1) goto USAGE

if (! -e $file.4dfp.img || ! -e $file.4dfp.ifh || ! -e $file.4dfp.img.rec) then
	echo $program": "$file not found
	exit -1
endif

if (! ${?ROI_type}) then
	set prog = `head -2 $file.4dfp.img.rec | tail -1 | awk '{print $1}'`
	switch ($prog)
		case peak_4dfp:
		case paste_4dfp:
		case burn_sphere_4dfp:
		case ROI_resolve_4dfp:
			set ROI_type = $prog;
			breaksw;
		default:
			set ROI_type = paste_4dfp;
			breaksw;
	endsw
endif

switch ($ROI_type)
case peak_4dfp:
	set loci = `echo $file:t | gawk '{match($1,/_[\+-][0-9][0-9]_[\+-][0-9][0-9]_[\+-][0-9][0-9]/);s=substr($0,RSTART+1,11);print s;}'`
	if ($loci == "") then
		echo $program":	filename format error"
		exit -1
	endif
	echo $loci | gawk '{printf("%s\t", $1)}'
	set coords = (`echo $loci | gawk '{split($1,a,"_");print a[1], a[2], a[3];}'`)

	#echo "coords="$coords
	gawk 'BEGIN{nr=10000};/N\.B\./{exit};/index_x/{nr=NR;};NR>nr{print}' $file.4dfp.img.rec >! $$.rec
	gawk 'BEGIN{dmin=1000;};{d=(x-$5)^2+(y-$6)^2+(z-$7)^2;if(d<dmin){dmin=d;x1=$5;y1=$6;z1=$7;n=$10}}END{printf("%10.4f%10.4f%10.4f",x1,y1,z1)}' x=$coords[1] y=$coords[2] z=$coords[3] $$.rec
	/bin/rm $$.*
	cluster_4dfp $file | gawk 'BEGIN{nr=10^6};/^region/{nr=NR};NR>nr{n+=$2};END{printf("\t%d\n",n);}'
	breaksw;
case ROI_resolve_4dfp:
	set loci = `echo $file:t | gawk '{match($1,/_[\+-][0-9][0-9]_[\+-][0-9][0-9]_[\+-][0-9][0-9]/);s=substr($0,RSTART+1,11);print s;}'`
	if ($loci == "") then
		echo $program":	filename format error"
		exit -1
	endif
	echo $loci | gawk '{printf("%s\t", $1)}'
	grep '^center of mass' $file.4dfp.img.rec | head -1 | gawk '{printf("%10.4f%10.4f%10.4f", $9, $10, $11)}'
	cluster_4dfp $file | gawk 'BEGIN{nr=10^6};/^region/{nr=NR};NR>nr{n+=$2};END{printf("\t%d\n",n);}'
	breaksw;
case burn_sphere_4dfp:
	set loci = `echo $file:t | gawk '{m=split($1,a,"_");printf("%+03d_%+03d_%+03d",a[m-2],a[m-1],a[m-0])}'`
	echo $loci | gawk '{printf("%s\t", $1)}'
	grep '^burn_sphere_4dfp' $file.4dfp.img.rec | head -1 | gawk '{printf("%10.4f%10.4f%10.4f", $2, $3, $4)}'
	cluster_4dfp $file | gawk 'BEGIN{nr=10^6};/^region/{nr=NR};NR>nr{n+=$2};END{printf("\t%d\n",n);}'
	breaksw;
case paste_4dfp:
	@ nvox = `cluster_4dfp -l -f$ivol $file | gawk 'BEGIN{nr=10^6};/^region/{nr=NR};NR>nr{n+=$2};END{printf("\t%d\n",n);}'`
	set coords = (`index2atl -af $file ${file}_vol${ivol}_clus.dat | gawk '$1!~/#/{printf("%10.4f%10.4f%10.4f\n", $7, $8, $9)}'`)
	/bin/rm ${file}_vol${ivol}_clus.dat
	set loci = `echo $coords | gawk '{printf("%+03d_%+03d_%+03d" ,$1, $2, $3)}'`
	echo $loci $coords $nvox | gawk '{printf("%14s%10.4f%10.4f%10.4f%10d", $1, $2, $3, $4, $5)}'
	breaksw;
endsw
exit 0

USAGE:
echo "Usage:	"$program" <(4dfp) ROI>"
echo " e.g.:	"$program" asd-ctrl_p.lob_roi_+49_+10_-24"
echo "	option"
echo "	-b	burn_sphere_4dfp"
echo "	-r	ROI_resolve_4dfp"
echo "	-p	peak_4dfp"
echo "	-f<int>	address specified volume of multi-volume file"
echo "N.B.:	absent option "$program automatically tries to determine type of input

exit 1
