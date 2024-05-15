#!/bin/csh

#set echo
set maxlag = 5.
@ niter = 2000
set TR = 1.
set rhos = (0.6 0.7 0.8 0.9)

#foreach T (1024 4096)
foreach T (4096)
	@ nframe = `echo $T $TR | gawk '{print $1/$2}'`
	echo $TR $nframe
	foreach rho ($rhos)
		echo $rho | gawk '{printf ("%10.4f%10.4f\n%10.4f%10.4f\n", 1., $1, $1, 1.)}' >! $$.dat
		simulate_test_lag $nframe $$.dat -L$$.out -N$niter -t$TR -l0.5
		head -1 $$.out
		cat $$.out | gawk '$5==c && ($3^2 < maxlag^2){print}' c=$rho maxlag=$maxlag | gawk -f ~/bin/histog.awk col=3 maxval=.9 minval=0.1 nbin=30 >! T${T}_lag0.5_rho$rho.hist
	end
end
/bin/rm $$.*
exit
