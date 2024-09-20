/RESOLVE/ {
	printf ("pushd unresolved_t4\nt4_resolve ");
	t = $2;
	s = "";
	for (i = 2; i <= NF; i++) {s = s $i; printf ("${%sT} ", $i);}
	printf ("-o${PATID}%s_target\t>> ${PATID}_${program}_t4_resolve.log\npopd\n", s);
	for (i = 2; i <= NF; i++) printf ("mv -f unresolved_t4/${%sT}_to_${PATID}%s_target_t4 resolved_t4/${%sT}_to_${PATID}%s_target_t4\n", $i, s, $i, s);
	printf ("mv -f unresolved_t4/${PATID}%s_target.sub resolved_t4/${PATID}%s_target.sub\n", s, s);
}
/TARGET/ {for (i = 2;  i <= NF; i++) printf ("cp resolved_t4/${%sT}_to_${PATID}%s_target_t4 ${%sT}_to_${%sT}_t4\n", $i, s, $i, t);}
/PATH/   {
	for (i = NF-1; i > 2; i--) printf ("t4_mul ${%sT}_to_${%sT}_t4 ${%sT}_to_${%sT}_t4\n", $NF, $i, $i, $(i-1));
	for (i = NF-2; i > 2; i--) printf ("rm     ${%sT}_to_${%sT}_t4\n",                     $NF, $i);
}

