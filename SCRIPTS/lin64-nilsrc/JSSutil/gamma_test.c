#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <JSSstatistics.h>

/*************/
/* externals */
/*************/
double	dnormal (void);			/* dnormal.c */

/**********************************************/
/* returns approximate x such that erf(x) ~ P */
/**********************************************/
float inverfa (float P) {
#define TOL	1.e-3
#define NK	100
#define CONST	1.12837916709551257390  /* 2/sqrt(pi) */

	static int	init = 0;
	static double	c[NK];
	double 		t, u, uu;
	int		k, m;

	if (!init) {
		c[0] = 1.;
		for (k = 1; k < NK; k++) {
			for (c[k] = m = 0; m < k; m++) {
				c[k] += c[m]*c[k - 1 - m]/((m + 1.)*(2.*m + 1.));
			}
		}
		if (0) {
			for (k = 0; k < 6; k++) printf (" %10.4f", c[k]); printf ("\n");
			printf (" %10.4f %10.4f %10.4f %10.4f %10.4f %10.4f\n",
				1., 1., 7./6., 127./90., 4369./2520., 34807./16200.);
		}
		init++;
	}

	if (P <= -1.0) return -1./0.;
	if (P >=  1.0) return  1./0.;

	u = P/CONST; uu = u*u;
	for (t = k = 0; k < NK; k++) {
		t += u*c[k]/(2.*k + 1.);
		u *= uu;
		if (fabs (u) < TOL) break;
	}
	if (0) printf ("%10d", k);
	return (float) t;
}

/********************************************************/
/* returns x such that gammp(a,x) = P                   */
/* 2.*invgammp(nu/2.,drand48())) is a chi^2(nu) variate */
/********************************************************/
float invgammp (float a, float P) {
#define PI	3.1415926
	float	x, dx, t, dgammpdx, gammlna;
	int	iter, debug = 0;

	if (a < 1.) {
		printf ("For nu==1 use dnormal()^2\n");
		exit -1;
	}

	if (P <= 0.0) return 0.;
	if (P >= 1.0) return 1./0.;
	if (a == 1.0) return -log (1. - P);
	
	if (a < 4.5 && P < .1) {
		x = pow (P*exp(gammln(a + 1.)), 1./a);
	} else if (a > 15. || (a >= 4. && P > .25)) {
		x = a + inverfa(2.*(P - 0.5))*sqrt(2.*a);
	} else {
		x = a + (P - 0.5)*sqrt(2.*PI*a);
	}
	if (0) return x;	/* return initial estimate */

	gammlna = gammln(a);
	if (debug) printf ("%10s%10s%10s%10s%10s\n", "a", "x", "t", "P", "dx");
	iter = 0;
	do {	iter++;
		t = gammp (a, x);
		dgammpdx = pow(x, a - 1.)*exp(-x -gammlna);
		dx = (P - t)/dgammpdx;
		if (debug) printf ("%10.4f%10.4f%10.6f%10.6f%10.6f\n", a, x, t, P, dx);
		if (dx > a) dx = a; if (dx < -a/5.) dx = -a/5.;
		x += dx; if (x < 0.) x = -x;
	} while (fabs(P - t) > 1.e-6);
	if (0) printf ("%3d ", iter);
	return x;
}

int main (int argc, char *argv[]) {
	float		a, x, t, eps = 0.001, dgammpdx, t1, P;
	float		x1, dxdP, g, f;
	int		i, k, nu = 2;

	a = 50.;
	if (0) for (i = 0; i <= 10; i++) {
		x = i;
		t = gammp (a, x);
		dgammpdx = pow(x, a - 1.)*exp(-x -gammln(a));
		t1 = gammp (a, x + eps);
		printf ("%10.4f%10.4f%10.6f%10.6f%10.6f\n", a, x, t, dgammpdx, (t1 - t)/eps);
	}

	a = 7.;
	if (1) for (i = 0; i < 1000; i++) {
		P = i/1000.;
		x = invgammp (a, P);
		if (1) {
			t = gammp (a, x);
			printf ("%10.6f%10.4f%12.2e\n", P, x, P - t);
		} else {
			printf ("%10.6f%10.4f\n", P, x);
		}
	}

	if (0) for (i = 1; i < 11; i++) {
		a = 10.*i;
		x   = invgammp (a, .895);
		x1  = invgammp (a, .905);
		dxdP = 100.*(x1 - x);
		printf ("%10.4f%10.4f%10.4f\n", a, dxdP, dxdP/sqrt(a));

	}

	if (0) {
		a = 1.5; g = exp(gammln(a));
		for (i = 1; i < 11; i++) {
			x = a*(2. + i/5.);
			t = gammp(a, x);
			f = pow(x, a - 1.)*exp(-x);
			printf ("%10.4f%10.4f\n", g*(1. - t), f);
		}
	}

	nu = 3;
	if (0) for (i = 0; i < 10000; i++) {
		for (f = k = 0; k < nu; k++) {
			t = dnormal();
			f += t*t;
		}
		printf ("%10.6f%10.6f\n", f, 2.*invgammp(nu/2.,drand48()));
	}

	if (0) for (i = -999; i < 1000; i++) {
		P = i/1000.;
		printf ("%10.6f%10.6f\n", P, inverfa (P));
	}
	return 0;
}
