BEGIN {
	s = 1.;
}

function tanh(x) {
	q = exp(-2.*x);
	return (1. - q)/(1. + q);
}

END {
	for (i = -500; i <= 500; i++) {
		x = i/100.;
		y = s*tanh(x/s);
		printf ("%10.6f%10.6f%10.6f\n", x, x, y);
	}
}
