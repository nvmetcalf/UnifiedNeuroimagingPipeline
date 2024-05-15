BEGIN {
	i = 0;
	err = 0;
}

$1!~/#/ {
	if (i) {
		if (NF != n) {
			print "format error";
			err++;
			exit;
		}
	} else {
		n = NF;
	}
	for (j = 0; j < n; j++) v[i,j] = $(j + 1);
	i++;
}

END {
	if (err) exit -1
	for (i = 0; i < n; i++) {
		for (j = i + 1; j < n; j++) {
			printf ("%5d%5d%10.4f\n", i, j, v[i,j]);
		}
	}
}
