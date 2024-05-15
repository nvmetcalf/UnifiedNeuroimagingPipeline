{	n = NF/2;
	for (i = 1; i <= n; i++) {
		d = $i - $(i + n);
		printf ("%10.6f", d);
	}
	printf ("\n");
}
