BEGIN {
	TR = 1.;
	maxk = 5; nk = 2*maxk + 1;
	sigma2 = 10.;
	tau = 0.;
}

function cov(t) {
	q = -.5*t*t/sigma2;
	return 1. + q + q*q/2 + q*q*q/6;
}

END {
	if (0) for (i = -100*maxk; i <= 100*maxk; i++) {
		t = TR*i/100;
		tsq = t*t;
		q = -.5*tsq/sigma2
		h = exp(q);
		f = 1. + q + q*q/2 + q*q*q/6;
		printf ("%10.2f%10.6f%10.6f\n", t, h, f);
	}
	if (0) for (k = -maxk; k <= maxk; k++) {
		t = k*TR;
		c[k]    = cov(t);
		chat[k] = cov(t + tau);
		printf ("%10.2f%10.6f%10.6f\n", k*TR, c[k], chat[k]);
	}
	if (1) for (itau = -10; itau <= 10; itau++) {
		tau = itau/10.;
		e2 = 0.;
		for (k = -maxk; k <= maxk; k++) {
			t = k*TR;
			c[k]    = cov(t);
			chat[k] = cov(t + tau);
			q = chat[k] - c[k];
			e2 += q*q;
		}
		printf ("%10.4f%10.6f\n", tau, e2/nk);
	}
}
