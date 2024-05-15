NF == 1 {
	l = $1;
	eta = sqrt(2.*(l - 1. - log(l)));
	C0 = 1./(l - 1.) - 1./eta;
	print C0;
}
