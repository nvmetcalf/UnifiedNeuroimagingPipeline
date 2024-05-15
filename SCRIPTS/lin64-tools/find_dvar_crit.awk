#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/find_dvar_crit.awk,v 1.8 2020/11/26 05:28:11 avi Exp $
#$Log: find_dvar_crit.awk,v $
# Revision 1.8  2020/11/26  05:28:11  avi
# in smooth mode apply parabolic interpolation to s[k] rather than y[k]
#
# Revision 1.7  2020/11/14  22:08:25  avi
# option -S smooth hisotgram before finding mode
#
# Revision 1.6  2019/11/10  05:37:33  avi
# make min number of bin 7
#
# Revision 1.5  2019/03/06  05:03:17  avi
# replace hard-coded histogram upper limit with 2.5*mean
#
# Revision 1.4  2019/02/26  07:10:20  avi
# create find_dvar_crit.log instead of writing answer to stdout
#
# Revision 1.3  2019/02/26  06:42:39  avi
# enable debug
# make invalid histogram message more informative
#
# Revision 1.2  2019/02/26  03:24:27  avi
# ignore vals > 500
#
# Revision 1.1  2016/05/28  01:11:43  avi
# Initial revision
#
# Revision 1.1  2016/05/28  01:10:36  avi
# Initial revision
#

BEGIN {
	debug = 1;
	tol = 2.5;	# in units of s.d.
	S_flag = 0;	# smooth histogram when set
	nval = 0;
	valsum = 0;
}

$1 !~/#/ && $1 < 500. && NF == 1 {
	vals[nval] = $1;
	nval++;
}

$1 !~/#/ && $1 < 500. && NF == 2 && $2 == "+" {
	vals[nval] = $1;
	nval++;
}

END {
	nbin = int (nval/25); if (nbin < 7) nbin = 7;
	for (i = 0; i < nval; i++) valsum += vals[i];
	dvarmax = 2.5*valsum/nval;
	del = dvarmax/nbin;
	printf ("nval=%d nbin=%d del=%.4f\n", nval, nbin, del);

	for (i = 0; i < nval; i++) {
		k = int (vals[i]/del);
		y[k]++;	# y has histogram
	}
	m = 0;		# index of max bin
	for (k = 0; k < nbin; k++) if (y[k] > y[m]) m = k;
	if (m == 0 || m == nbin - 1) {
		print "find_dvar_crit.awk: histogram peak on boundary";
		for (k = 0; k < nbin; k++) printf ("%5d%5d\n", k, y[k]);
		exit -1;
	}
	mode = del*(m + 0.5 - 0.5*((y[m + 1] - y[m - 1])/(y[m + 1] + y[m - 1] - 2.*y[m])));
#############################################
# copy y to s = smoothed version of histogram
#############################################
	for (k = 0; k < nbin; k++) s[k] = y[k];
###############################################
# test max bin is surrounded by next lower bins
###############################################
if (S_flag) do {
	for (k = 0; k < nbin; k++) t[k] = s[k];
	for (j = 0; j < 3; j++) {
		m = 0; for (i = 0; i < nbin; i++) if (t[i] > t[m]) m = i;
		order[j] = m;
		t[m] = 0;
	}
	printf ("peak indices %5d%5d%5d\n", order[0], order[1], order[2]);
	test = (order[0] - order[2])^2 + (order[0] - order[1])^2;
	printf ("test=%d\n", test);
	if (test > 2) {
################
# smooth s by 3s
################
		t[0] = s[0]; t[nbin - 1] = s[nbin - 1];
		for (k = 1; k < nbin - 1; k++) t[k] = 0.25*(s[k - 1] + 2*s[k] + s[k + 1]);
		for (k = 0; k < nbin; k++) s[k] = t[k];
	} else {
		m = order[0];
		mode = del*(m + 0.5 - 0.5*((s[m + 1] - s[m - 1])/(s[m + 1] + s[m - 1] - 2.*s[m])));
	}
} while (test > 2);
	mval = 0; ss = 0;
	for (i = 0; i < nval; i++) if (vals[i] < mode) {
		ss += (mode - vals[i])^2;
		mval++;
	}
	sd = sqrt (ss/mval);
	crit = mode + tol*sd;
	if (S_flag) {
		for (k = 0; k < nbin; k++) printf ("%10.2f%10d%10.2f\n", k*del, y[k], s[k]);
	} else {
		for (k = 0; k < nbin; k++) printf ("%10.2f%10d\n", k*del, y[k]);
	}
	printf ("mode=%f sd=%f mode+tol*sd=%f\n", mode, sd, crit);
	printf ("CRIT= %f\n", crit);
}
