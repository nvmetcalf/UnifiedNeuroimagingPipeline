#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/FD.awk,v 1.1 2016/10/25 00:42:12 avi Exp $
#$Log: FD.awk,v $
# Revision 1.1  2016/10/25  00:42:12  avi
# Initial revision
#

BEGIN {
	pi=atan2(1,1)*4;
}

function abs(v) {return v < 0 ? -v : v}

NF > 0 {
	if($1 == 1) 
		print "500.00\t500.00";
	else if ($1 ~ /^[0-9]+$/) {
		L1 = abs($2)+abs($3)+abs($4) + 50*pi*(abs($5)+abs($6)+abs($7))/180;
		L2 = sqrt($2^2+$3^2+$4^2)    + 50*pi*sqrt($5^2+$6^2+$7^2)/180;
		printf ("%0.4f\t%0.4f\n", L1, L2);
	}
}

END {
}
