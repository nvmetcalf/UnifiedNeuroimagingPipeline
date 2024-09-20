$0~/^i =/ {
	i = $NF;
	if (i > imax) imax = i;
}

$0~/^j =/ {
	j = $NF;
	if (j > jmax) jmax = j;
}

/eta,q/ {
	eta[i,j] = $2;
}

END {
	for (i = 1; i <= imax; i++) eta[i,i] = 1.;
	printf ("eta matrix\n");
	for (i = 1; i <= imax; i++) {
		for (j = 1; j <= jmax; j++) printf ("%10.5f", eta[i,j]);
		printf ("\n");
	}
	printf ("eta matrix asymmetry\n");
	for (i = 1; i <= imax; i++) {
		for (j = 1; j <= jmax; j++) printf ("%10.5f", eta[i,j]-eta[j,i]);
		printf ("\n");
	}
}
