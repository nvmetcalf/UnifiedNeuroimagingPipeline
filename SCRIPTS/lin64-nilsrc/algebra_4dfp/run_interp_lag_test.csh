#!/bin/csh

foreach del (2.50)
	set out = interpolated_lag_$del.dat
	if (-e $out) /bin/rm $out
	touch $out
	@ k = 1
	while ($k <= 20)
		interp_lag_test 16384 -i$k -d$del | gawk '/^interpolated/{print $NF;}' >> $out
		@ k++
	end
end
exit
