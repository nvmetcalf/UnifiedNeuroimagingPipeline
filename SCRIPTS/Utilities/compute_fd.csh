#!/bin/csh 

set DDAT_file = $1
set HeadRadius = $2
set Skip = $3
set ForwardFlag = $4
set FD_thresh = $5

if(! -e $DDAT_file) then
	echo "$DDAT_file does not exist"
	exit 1
endif

@ ddat_length = `wc $DDAT_file | awk '{print $1}'`
@ ddat_start = $ddat_length - 8
@ ddat_end = $ddat_length - 5

#compute fd
head -$ddat_end $DDAT_file | tail -$ddat_start | awk -v pi=3.14159 -v radius=$HeadRadius 'function abs(x){return(x < 0.0 ? -x : x);}{print(abs($2) + abs($3) + abs($4) + abs((pi/180) * $5 * radius) + abs((pi/180) * $6 * radius) + abs((pi/180) * $7 * radius));}' >! $DDAT_file".fd"

#compute the at moment fd format
cat $DDAT_file".fd" | awk -v thresh=$FD_thresh '{if($1 > thresh){print("0");}else{print("1");}}' >! temp

#apply skip and forward
cat temp | awk -v skip=$Skip -v forward=$ForwardFlag 'BEGIN{post_flag_skip = 0;}{if(skip > 0){print("0"); skip--;} else if($1 == 0){post_flag_skip = forward; print("0");} else if(post_flag_skip > 0){print("0"); post_flag_skip--;} else{print($1)}}' >! $DDAT_file".fd.sfbin"

#make expanded avi format
cat $DDAT_file".fd.sfbin" | awk '{if($1) {printf("+");} else {printf("x");}}' >! $DDAT_file".format_expanded"

#make avi format
condense `cat $DDAT_file".fd.sfbin" | awk '{if($1) {printf("+");} else {printf("x");}}'` >! $DDAT_file".format"
if($status) exit 1
#make tmask
cat $DDAT_file".fd.sfbin" | awk '{if($1) {printf("1\t");} else {printf("0\t");}}' >! $DDAT_file".tmask"

rm temp

