#$Header: /home/petsun9/avi/bin/RCS/histog.awk,v 1.3 2012/07/13 04:40:40 avi Exp $
#$Log: histog.awk,v $
# Revision 1.3  2012/07/13  04:40:40  avi
# command line control of range
#
# Revision 1.2  2008/03/23  23:49:31  avi
# default col and nbin value
# remove factor of 100 from frequency display
#
# Revision 1.1  2008/03/23  23:44:13  avi
# Initial revision
#
BEGIN	{
	nlin=0;
	u1=0.;u2=0.;
	ldebug=0;
	col=1;
	nbin=10;
	}

(NF >= col && $1 !~/#/) {
	nlin++;x[nlin]=$col;
	if(ldebug != 0) printf("%s %s %s %d %f\n",$1,$2,$col,nlin,x[nlin]);
	}

END	{
	printf ("# col=%s   nbin=%s   nsample=%d\n", col, nbin, nlin);
	for(i = 1;i <= nlin; i++){u1=u1+x[i];}
	u1=u1/nlin;
	for(i = 1;i <= nlin; i++){u2=u2+(x[i]-u1)*(x[i]-u1);}
	u2=u2/(nlin-1);sd=sqrt(u2);
	printf("# mean  %12.4f    sd%12.4f\n",u1,sd);

	if (minval == 0 && maxval == 0) {
		maxval = x[1]; minval = x[1];
		for (i = 1; i <= nlin; i++) {
			if (x[i] > maxval) maxval = x[i];
			if (x[i] < minval) minval = x[i];
		}
	}
	for (j = 0; j < nbin; j++) {hist[j] = 0;}
	for (i = 1; i <= nlin; i++){
		j = int ((x[i] - minval) * nbin / (maxval - minval));
		if (j == nbin) j--;
		hist[j] ++;
	}

	dx = (maxval - minval) / nbin;
	scale = 1 / (nlin * dx);
	printf ("%10.4f%10d%20.4f\n", minval, 0., 0.);
	for (j = 0; j < nbin; j++){
		binval  = minval + j     * dx;
		binval1 = minval + (j+1) * dx;
		printf ("%10.4f%10d%20.4f\n", binval,  hist[j], hist[j]*scale);
		printf ("%10.4f%10d%20.4f\n", binval1, hist[j], hist[j]*scale);
	}
	printf ("%10.4f%10d%20.4f\n", maxval, 0., 0.);

}
