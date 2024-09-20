#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/pseudo_dcm_sort.csh,v 1.12 2018/08/17 05:52:11 avi Exp $
#$Log: pseudo_dcm_sort.csh,v $
# Revision 1.12  2018/08/17  05:52:11  avi
# invoke with -f
#
# Revision 1.11  2018/06/23  02:48:26  avi
# correct bug preventing execution in non-subdirectory mode
#
# Revision 1.10  2015/02/10  06:03:53  avi
# initialize variable $files
#
# Revision 1.9  2014/03/27  03:43:43  avi
# option -i (take integer-named files)
#
# Revision 1.8  2013/12/01  06:10:14  avi
# correct
#
# Revision 1.7  2013/12/01  05:06:19  avi
# multiple strategies for identifying DICOM files
#
# Revision 1.6  2013/11/29  23:29:14  avi
# always process DICOM subdirectory of numeric subdirectory
#
# Revision 1.5  2013/11/29  04:55:58  avi
# trap no DICOMs in study$k condition
#
# Revision 1.4  2013/08/24  06:41:59  avi
# correct dcmdir bug
#
# Revision 1.3  2013/08/08  02:54:22  avi
# process numerical subdirectories with single snamed subdirectory
#
# Revision 1.2  2013/07/01  04:14:05  avi
# create txt report (like dcm_sort)
#
# Revision 1.1  2013/07/01  01:22:43  avi
# Initial revision
#
set program = $0; set program = $program:t

set ext		= dcm
set root	= ""
@ integer	= 0
@ subdir_flag	= 0
@ debug		= 0
@ k		= 0
@ i		= 1
@ uset		= 1
while ($i <= ${#argv})
	set swi = `echo $argv[$i] | awk '$1~/^-/{print substr($1,1,2)}'`
	if (${#swi} > 0) then
		set arg = `echo $argv[$i] | awk '{print substr($0,3)}'`
		switch ($swi)
                        case -d:
                                @ debug++; set echo;		breaksw;
                        case -i:
                                @ integer++;			breaksw;
                        case -s:
                                @ subdir_flag++;		breaksw;
                        case -e:
                                set ext = $arg;			breaksw;
                        case -r:
                                set root = $arg;		breaksw;
			case -t:
				@ uset = 0;			breaksw;
			default:
				echo $swi option not recognized
				goto USAGE
				breaksw;
		endsw
	else
		switch ($k)
			case 0:
				set dcmdir = $argv[$i];	@ k++;	breaksw;
			default:				breaksw;
		endsw
	endif
	@ i++
end
if ($k < 1) goto USAGE

if (! -d $dcmdir) then
	echo $program": "$dcmdir not a directory
	exit -1
endif
if (`echo $dcmdir | awk '{if(substr($0,1,1)!="/")print 1}'`) set dcmdir = $cwd/$dcmdir
set wrkdir = $cwd

set studies = ()
foreach d ($dcmdir/*)
	if (-d $d) then
		@ k = `echo $d:t | awk '{print $1 + 0}'`
		if (! $k) then
			echo non-numeric subdirectory $d skipped
			break
		endif
		set studies = ($studies $k)
		@ noDICOMS = 0
		if (-e study$k) /bin/rm -rf study$k
		mkdir study$k
		pushd study$k	# into study$k
		set files = ()
		if ($subdir_flag) then
			if (-d $dcmdir/$k/DICOM) then
				set subdir = DICOM
			else
				set subdir = (`ls $dcmdir/$k`)
				echo "subdir=$subdir"
				if ($#subdir != 1) then
					echo $program": numeric subdirectory has more than one subdirectory"
					exit -1
				endif
			endif
			if ($integer) then
				ls $dcmdir/$k/"$subdir" | gawk '($1+0)==$1{print}' >! $wrkdir/$$.lst
				set files = (`cat $wrkdir/$$.lst | gawk '{printf(" %s/%s", D, $1)}' D=$dcmdir/$k/"$subdir"`)
				if ($debug) echo "files="$files
				/bin/rm $$.lst
			endif
			if (${#files} == 0) then
				set files = (`ls $dcmdir/$k/"$subdir"/MR*`)
			endif
			if (${#files} == 0 && $root != "") then
				set files = (`ls $dcmdir/$k/"$subdir"/$root*`)
			endif
			if (${#files} == 0 && $ext  != "") then
				set files = (`ls $dcmdir/$k/"$subdir"/*$ext`)
			endif
			echo ${#files} $dcmdir/$k/"$subdir" | gawk '{printf("%4d DICOM files found in %s\n", $1, $2)}'
			if (${#files} > 0) then
				foreach x ($files)
					ln -s "$x" .
				end
		
			else
				@ noDICOMS++;
			endif
		else
			if ($integer) then
				ls $dcmdir/$k | gawk '($1+0)==$1{print}' >! $wrkdir/$$.lst
				set files = (`cat $wrkdir/$$.lst | gawk '{printf(" %s/%s", D, $1)}' D=$dcmdir/$k`)
				if ($debug) echo "files="$files
				/bin/rm $$.lst
			endif
			if (${#files} == 0) then
				set files = (`ls $dcmdir/$k/MR*`)
			endif
			if (${#files} == 0 && $root != "") then
				set files = (`ls $dcmdir/$k/$root*`)
			endif
			if (${#files} == 0 && $ext  != "") then
				set files = (`ls $dcmdir/$k/*$ext`)
			endif
			echo ${#files} $dcmdir/$k | gawk '{printf("%4d DICOM files found in %s\n", $1, $2)}'
			if (${#files} > 0) then
				foreach x ($files)
					ln -s $x .
				end
			else
				@ noDICOMS++;
			endif
		endif
		popd		# out of study$k
		if ($noDICOMS) /bin/rm -rf study$k
	endif
end

#################################
# create permanent study key file
#################################
set command = dcm_dump_file
if ($uset) set command = $command" -t"
touch $$.tmp
@ i = 1
while ($i <= ${#studies})
	@ k = $studies[$i]
	if (! -d study$k) goto NEXTi
	set f = `ls study$k/* | head -1`
	set sequens = `$command $f | grep "ACQ Sequence Name" | gawk '{gsub(/\*/,"");l=index($0,"ame");print substr($0,l+5);}'`
	if ($sequens == "") set sequens = "none"
	set descrip = `$command $f | grep "ID Series Description" | gawk '{gsub(/\[/,"");gsub(/\?/,"");gsub(/\]/,"");gsub(/ /,"");gsub(/*/,"star");l=index($0,"ion");print substr($0,l+5);}'`
	if ($descrip == "") set descrip = "none"
	@ filecnt = `ls study$k/* | wc | awk '{print $1}'`
	echo $k $sequens $descrip $filecnt >> $$.tmp
NEXTi:
	@ i++
end
sort -n	$$.tmp | gawk '{printf("%-5d%-15s%-50s%5d\n",$1,$2,$3,$4)}' >!	${dcmdir:t}.studies.txt
cat									${dcmdir:t}.studies.txt
/bin/rm $$.tmp
exit 0

USAGE:
echo "usage:	"$program" <dicom directory>"
echo "e.g.:	"$program" RAW"
echo "N.B.:	dicom subdirectories must be numeric"
echo "	option"
echo "	-d	debug mode (set echo)"
echo "	-s	DICOM files are within a subdirectory of numeric subdirectories (default directly in numeric subdirectory)"
echo "	-e	identify DICOM files by specified extension (default extension = $ext)"
echo "	-r	identify DICOM files by specified root (default root = 'MR*')"
echo "	-i	take DICOM files with integer filenames"
echo "	-t	toggle off use of -t in call to dcm_dump_file (default ON)"
echo "N.B.:	default subdirectory of numeric subdirectory is 'DICOM'"
exit 1
