#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/CORto4dfp.csh,v 1.2 2018/08/16 05:11:05 avi Exp $
#$Log: CORto4dfp.csh,v $
# Revision 1.2  2018/08/16  05:11:05  avi
# invoke with -f
#
# Revision 1.1  2010/08/24  00:30:21  avi
# Initial revision
#
set idstr = '$Id: CORto4dfp.csh,v 1.2 2018/08/16 05:11:05 avi Exp $'
echo $idstr
set program = $0; set program = $program:t

#set echo

if ($#argv < 2) then
	echo Usage: $program" <COR directory> <outroot>"
	exit 1
endif

if (! -d $1) then
	echo $1 not a directory
	exit -1
endif

if (-e $2.img) /bin/rm $2.img
touch $2.img
if ($status) exit $status
set wrkdir = $cwd

pushd $1
@ k = 1
while ($k <= 256)
	set file = `echo $k | awk '{printf ("COR-%03d", $1)}'`
	if (! -e $file) then
		echo $file not found
		exit -1
	endif
	cat $file >> $wrkdir/$2.img
	@ k++
end
popd

/bin/cp $RELEASE/orig_8bit.hdr $2.hdr
analyzeto4dfp -O4 $2.img
if ($status) exit $status
/bin/rm $2.img $2.hdr

exit 0
