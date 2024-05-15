#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/list_regressors.csh,v 1.2 2021/06/24 16:33:03 tanenbauma Exp $
#$Log: list_regressors.csh,v $
# Revision 1.2  2021/06/24  16:33:03  tanenbauma
# Add -f flag
#
# Revision 1.1  2021/06/24  05:46:40  avi
# Initial revision
#

if ($#argv < 1) exit
if (! -e $1) exit
@ ncol = `cat $1 | awk 'NR==1{print NF}'`
echo $1 $ncol | awk '{printf("%-40s %3d regressors\n", $1, $2)}'

exit
