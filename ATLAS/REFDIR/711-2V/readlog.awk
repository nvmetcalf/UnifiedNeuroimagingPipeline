$1 == "imgreg_4dfp" {print linebefore; print $4;}
NF > 0 {
	linebefore = $0;
}
