#!/bin/bash
# Program for atlas based PiB processing. This is a bash wrapper for a matlab code
# Yi Su, 2013-02-07

idstr='$Id: atlpib.sh,v 1.0 2013/02/07 suy Exp $'
echo $idstr

if (( $# < 1 )) 
then
	echo "Usage: `basename $0` petroot"
	exit 255
fi

petroot=$1 # 4dfp file

# Prepare .m file 

mfile=${petroot}"_atlpib.m"
if [ -e $mfile ] 
then
	rm $mfile
fi
touch $mfile
echo "addpath('/data/nil-bluearc/raichle/suy/matlabcodes/');" >>$mfile #addpath
echo "atlpib('"$petroot"');" >>$mfile


#-----------------------------------------------------------------------------------------------------------------------#
#--Execute matlab file -------------------------------------------------------------------------------------------------#
$MLBIN/matlab -nojvm -nodisplay < $mfile > /dev/null
rm $mfile

