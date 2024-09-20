#!/bin/bash

toPAL=4dfp_to_PAL
if [[ ! -f `which $toPAL` ]]
then
	if [[ -f `which $0` ]]
	then
		#strip script name off the path string, add 4dfp_to_PAL
		toPAL=`which $0 | sed 's|/[^/]*|/|'`4dfp_to_PAL
		if [[ ! -f $toPAL ]]
		then
			echo 'please set $toPAL in the script manually, cannot locate'
			exit 0
		fi
	else
		echo 'please set $toPAL in the script manually, cannot locate'
		exit 0
	fi
fi

if (( $# < 4 ))
then
	echo "Usage: $0 <dicomdir> <dicomglob> <outname> <compress>"
	echo '	<dicomdir> is passed to dcm_to_4dfp, and all files matching'
	echo '	<dicomdir>/<dicomglob> are used with dcmdump to generate'
	echo '	frame durations and scalings'
	echo '	<compress> is how many Z slices to average into one for output'
	exit 0
fi

if [[ -f acqtime.txt ]]
then
	rm acqtime.txt
fi

if [[ -f timedata.txt ]]
then
	rm timedata.txt
fi

echo dcm_to_4dfp -r -b $3 $1
dcm_to_4dfp -r -b $3 $1

uniq=''

echo building frame information...
for file in `echo $1/$2`
do
	#seriously nasty, but only because this data is too stupid to include a timepoint index
	#acquisition time
	mytime=`dcmdump +P 0008,0032 $file 2> /dev/null | cut -f2 -d[ | cut -f1 -d]`
	
	echo $mytime >> acqtime.txt
	temp=`sort -u acqtime.txt | wc`
	if [[ $uniq != $temp ]]
	then
		uniq=$temp
		#acquisition date
		mydate=`dcmdump +P 0008,0022 $file 2> /dev/null | cut -f2 -d[ | cut -f1 -d]`
		#acquisition date, time - use for unique sorting of frames
		sortfield=$mydate$mytime
		#duration, needed for conversion
		duration=`dcmdump +P 0018,1242 $file 2> /dev/null | cut -f2 -d[ | cut -f1 -d]`
		echo $sortfield $duration >> timedata.txt
	fi
done

sort -n timedata.txt | cut -f2- -d' ' > sorteddurations.txt

echo $toPAL $3 sorteddurations.txt $3 $4
$toPAL $3 sorteddurations.txt $3 $4

if [[ ! $5 ]]
then
	rm acqtime.txt timedata.txt sorteddurations.txt
fi
