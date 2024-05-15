#!/bin/csh

set qntfile = lag_16384_.1_.1.dat
if (-e $qntfile) /bin/rm $qntfile
touch $qntfile
@ k = 0
while ($k < 100)
	interp_lag_SE 16384 -i$k -p1=.1 -p2=.1 -o$qntfile
	@ k++
end
exit
