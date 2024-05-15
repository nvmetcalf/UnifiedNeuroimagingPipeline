/:/ {
	split($4,a,":"); sec = a[3] + 60*(a[2] + 60*a[1]);
	dsec = sec - sec0;
	sec0 = sec;
	if (dsec < 0) dsec += 24*3600;
	if (iter > 1) printf ("%10d%10d\n", ncol, dsec);
}

/ncol/ {
	iter = $3;
	ncol = $NF;
}
