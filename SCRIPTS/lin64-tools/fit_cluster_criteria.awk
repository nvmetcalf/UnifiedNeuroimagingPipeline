BEGIN {
	nsig + 0;
	debug = 0;
}

/significance/ {
	m=split ($1,a,"=");
	nsig++;
	sig[nsig] = a[2];
}

/ktmin/ {
	m=split ($1,a,"=");
	ktmin = a[2];
}

/ktmax/ {
	m=split ($1,a,"=");
	ktmax = a[2];
}

/dthresh/ {
	m=split ($1,a,"=");
	dthresh = a[2];
}

NF == 2 && nsig > 0 {
	kt = int ($1/dthresh + 0.000001)
	logscrit[nsig,kt] = log($2);
	if (debug) print nsig, kt, logscrit[nsig,kt];
}

END {
	print "model:	log[cluster size in voxels] = C + beta*(Zscore threshold)"
	for (isig = 1; isig <= nsig; isig++) {
		for (i = 1; i <= 2; i++) {
			b[i] = 0;
			for (j = 1; j <= 2; j++) A[i,j] = 0;
		}
		for (kt = ktmin; kt <= ktmax; kt++) {
			v = logscrit[isig,kt];
			if (!v) continue;
			z = kt*dthresh;
			A[1,1] += 1;
			A[1,2] += z;
			A[2,1] += z;
			A[2,2] += z^2;
			b[1] += v;
			b[2] += v*z;
		}
		if (0) {
			print A[1,1], A[1,2], b[1];
			print A[2,1], A[2,2], b[2];
		}

		det = A[1,1]*A[2,2] - A[2,1]*A[1,2];
		Ai[1,1] =  A[2,2]/det;
		Ai[1,2] = -A[1,2]/det;
		Ai[2,1] = -A[2,1]/det;
		Ai[2,2] =  A[1,1]/det;

		C 	= Ai[1,1]*b[1] + Ai[1,2]*b[2];
		beta	= Ai[2,1]*b[1] + Ai[2,2]*b[2];
		printf ("sig=%5.4f C=%6.4f beta=%6.4f\n", sig[isig], C, beta);
	}
}
