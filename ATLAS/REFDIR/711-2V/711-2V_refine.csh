#!/bin/csh

set program 	= $0; set program = $program:t
set newatl	= 711-2V
set patlst	= $newatl.lst
set mask 	= /data/petsun43/data1/atlas/711-2B_mask_g5_111z
set echo

if (! -e BAK) mkdir BAK
@ iter = 0
ITER:
mkdir BAK/iter$iter

###################
# refine transforms
###################
set log = $program.log
touch				$log
echo $program $argv[1-] >>	$log
date >>				$log

###############################
# register each case to average
###############################

foreach t4file (*_to_$newatl"_t4")
	/bin/cp -p $t4file BAK/iter$iter
	set mpr = `echo $t4file | awk '{l=index($1,"_to_");print substr($1,1,l-1)}'`	
	if (! -e $mpr"_g11".4dfp.img || ! -e $mpr"_g11".4dfp.ifh) gauss_4dfp $mpr 1.1
	@ mode = 2048 + 256 + 7
echo	imgreg_4dfp $newatl"_111" $mask $mpr"_g11" none $t4file $mode >> $log
	imgreg_4dfp $newatl"_111" $mask $mpr"_g11" none $t4file $mode >> $log
end

echo	/bin/mv $newatl"_111.4dfp*" BAK/iter$iter
	/bin/mv $newatl"_111.4dfp"* BAK/iter$iter
echo	t4imgs_4dfp $patlst $newatl"_111" -O111
	t4imgs_4dfp $patlst $newatl"_111" -O111
	ifh2hdr $newatl"_111" -r1300

echo	/bin/mv $newatl"_to_711-2B_t4" BAK/iter$iter
	/bin/mv $newatl"_to_711-2B_t4" BAK/iter$iter

############################
# register average to 711-2B
############################
@ mode = 2048 + 256 + 7
imgreg_4dfp /data/petsun23/avi/atlas_remake/711-2B_111 $mask $newatl"_111" none $newatl"_to_711-2B_t4.scale" $mode | tail -17 >> $log
@ mode = 2048 + 7
echo 	imgreg_4dfp /data/petsun23/avi/atlas_remake/711-2B_111 $mask $newatl"_111" none $newatl"_to_711-2B_t4"	$mode >> $log
	imgreg_4dfp /data/petsun23/avi/atlas_remake/711-2B_111 $mask $newatl"_111" none $newatl"_to_711-2B_t4"	$mode >> $log
	imgreg_4dfp /data/petsun23/avi/atlas_remake/711-2B_111 $mask $newatl"_111" none $newatl"_to_711-2B_t4"	$mode >> $log
tail -1 $newatl"_to_711-2B_t4.scale" >> $newatl"_to_711-2B_t4"
echo	cat $newatl"_to_711-2B_t4" >> $log
	cat $newatl"_to_711-2B_t4" >> $log

####################
# compose transforms
####################
foreach t4file (*_to_$newatl"_t4")
	t4_mul $t4file $newatl"_to_711-2B_t4" temp_t4
	/bin/mv temp_t4 $t4file
end

##############
# remake atlas
##############
echo	t4imgs_4dfp $patlst $newatl"_111" -O111
	t4imgs_4dfp $patlst $newatl"_111" -O111
	ifh2hdr $newatl"_111" -r1300

@ iter++
if ($iter <= 6) goto ITER
exit
