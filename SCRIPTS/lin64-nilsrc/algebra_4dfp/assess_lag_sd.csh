#!/bin/csh

@ T = 4096
set maxlag = 5.
@ niter = 2000
set rhos = (0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.95 0.97 0.98 0.99)
set TRs = (0.25 0.5 1.0 2.0)

goto HERE2

foreach TR ($TRs)
	@ k = 1
	while ($k <= $#rhos)
		cat test.log | gawk '$1==T && $2==TR {printf ("%10.4f%10.4f\n", $3, $4)}' T=$T TR=$TR >! lag_sd_T${T}_TR${TR}.dat
		@ k++
	end
end
exit

HERE:
simulate_test_lag 4096 /data/nil-bluearc/raichle/avi/NP600/vb12817/FCmaps/vb12817_seed_regressors_CCR.dat -N$niter -Lvb12817_Zhang36_simulate_test_lag.dat
cat vb12817_Zhang36_simulate_test_lag.dat | gawk '$1!~/#/ && ($3^2 < maxlag^2) && $5 != 1. && ($5^2 > 0.01) {print}' maxlag=$maxlag >! vb12817_Zhang36_simulate_test_lag_selected.dat
sort -n -k 5,5 vb12817_Zhang36_simulate_test_lag_selected.dat > ! vb12817_Zhang36_simulate_test_lag_selected_sort.dat
sort -u -m -k 5,5 vb12817_Zhang36_simulate_test_lag_selected_sort.dat >! vb12817_Zhang36_simulate_test_lag_selected_unique.dat
cat vb12817_Zhang36_simulate_test_lag_selected_unique.dat | gawk '{print $5}' >! vb12817_Zhang36_simulate_test_lag_selected_unique.lst
#exit
HERE1:
set out = lag_sd_vb12817_Zhang36_simulate_test_lag.dat
if (-e $out) /bin/rm $out
touch $out
@ n = `wc vb12817_Zhang36_simulate_test_lag_selected_unique.lst | gawk '{print $1}'`
@ k = 1
while ($k <= $n)
	set c = `head -$k vb12817_Zhang36_simulate_test_lag_selected_unique.lst | tail -1`
	cat vb12817_Zhang36_simulate_test_lag_selected.dat | gawk '$5==c {print}' c=$c | gawk -f ~/bin/histog.awk col=3 maxval=.8 minval=-.8 nbin=30 >! $$.dat
	set r = `cat $$.dat | gawk '/mean/{print $NF}'`
	echo $c $r | gawk '{printf("%10.4f%10.4f\n", $1, $2)}' >> $out
	@ k++
end
cat $out
rm $$.dat
exit

HERE2:
simulate_test_lag 4096 /data/nil-bluearc/raichle/avi/NP600/vb12817/FCmaps/vb12817_seed_regressors_CCR.dat -N100 -Lreal_cor_simulate_test_lag.dat
cat real_cor_simulate_test_lag.dat | gawk '$1!~/#/ && ($3^2 < maxlag^2) && $5 != 1. && ($5^2 > 0.01) {printf ("%10.4f%10.4f\n", $5, $3)}' maxlag=$maxlag >! real_cor_simulate_test_lag_selected.dat

