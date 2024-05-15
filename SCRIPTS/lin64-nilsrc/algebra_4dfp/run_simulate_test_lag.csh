#!/bin/csh

#set echo
@ T = 4096
set maxlag = 5.
@ niter = 2000
set rhos = (0.97 0.98 0.99)
set rhos = (0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.95)
set TRs = (.25 .5 1 2)
set TRs = (1)
set k_string = "k_still=0.10 k_motion=0.5"
set k_label = "k0.10_0.5"

goto SCATTER

##########################
# lag sd dependence on rho
##########################
foreach mode ("" -E -EI1 -EI2)
	set log = test"_z1_l0_"$k_label${mode}_g4.log1
	if (-e $log) /bin/rm $log; touch $log
	@ i = 0
	foreach TR ($TRs)
		@ nframe = `echo $T $TR | gawk '{print $1/$2}'`
		echo $TR $nframe
		foreach rho ($rhos)
			echo $rho | gawk '{printf ("%10.4f%10.4f\n%10.4f%10.4f\n", 1., $1, $1, 1.)}' >! $$.dat
			simulate_test_lag $nframe $$.dat -L$$.out -N$niter -t$TR -i$i $mode -l0. -g4. -z1. $k_string; @ i++;
			if ($status) exit $status
#			simulate_test_lag $nframe $$.dat -L$$.out -N$niter -t$TR -i$i $mode -g40.
			if ($status) exit $status
			head -1 $$.out
			cat $$.out | gawk '$5==c && ($3^2 < maxlag^2){print}' c=$rho maxlag=$maxlag | gawk -f ~/bin/histog.awk col=3 maxval=.8 minval=-.8 nbin=30 >! $$.hist
			set sd = `cat $$.hist | gawk '/mean/{print $NF}'`
			echo $T $TR $rho $sd | gawk '{printf ("%10d%10.4f%10.4f%10.4f\n", $1, $2, $3, $4)}' >> $log
			/bin/rm $$.*
		end
	end
	cat $log | gawk '{printf ("%10.4f%10.4f\n", $3, $4)}' >! $log.dat
end
exit

SCATTER:
set A = ~/bin/variance.awk

#set datfile = lags_r0.6_l.5_z1_${k_label}_EI2_g4.dat
#simulate_test_lag 4096 C_60.dat -L$$.out -N2000 -l0.5 -z1. -g4. $k_string -EI2

set datfile = lags_r0.6_l.5_z0_${k_label}.dat
simulate_test_lag 4096 C_60.dat -L$$.out -N2000 -l0.5 -z0. $k_string
cat $$.out | gawk '$5==0.6 && ($3^2 < 25.){print $3, $4}' >! $datfile
cat $datfile | gawk -f $A col=1 | tail -1
cat $datfile | gawk -f $A col=2 | tail -1

/bin/rm $$.out
exit

FORMAT:
simulate_test_lag 4096 C_60.dat -N1 $k_string -FE >! format_$k_label.txt
exit
