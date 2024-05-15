END {
	scale = .46/3.08;
	for (i = 1; i <= 100; i++) {
		r = i/100.;
		pi = 2*atan2(1., 0.);
#		print pi;
		theta = .5*pi*(1 - r);
		printf ("%10.4f%10.4f\n", r, scale*sin(theta)/cos(theta));
	}
}
