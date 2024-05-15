BEGIN {
	ndir = 0;
}

NF == 1 {
	m = split ($1,a,"/");
	if (m == 3 && a[3] == "") m = 2;
	new = 1;
	for (i = 0; i < ndir; i++) if (a[1] == dirs[i]) {
		new = 0;
		break;
	}
	if (new == 1 && m == 2) {
		printf ("mkdir %s\n", a[1]);
		dirs[ndir] = a[1];
		ndir++;
	}
	if (a[1] == "diff4dfp" || a[1] == "JSSutil") {
		src = "/home/usr/shimonyj"
	} else {
		src = "/data/petsun4/data1/src_solaris"
	}
	if (m == 2) {
		printf ("pushd %s\n", a[1]);
		printf ("ln -s %s/%s/%s .\n", src, a[1], a[2]);
		printf ("popd\n");
	}
	if (m == 1) {
		printf ("ln -s %s/%s .\n", src, a[1]);
	}
}
