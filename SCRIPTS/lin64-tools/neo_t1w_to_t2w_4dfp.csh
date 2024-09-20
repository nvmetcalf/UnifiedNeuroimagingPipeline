#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/neo_t1w_to_t2w_4dfp.csh,v 1.2 2018/08/17 05:51:04 avi Exp $
#$Log: neo_t1w_to_t2w_4dfp.csh,v $
# Revision 1.2  2018/08/17  05:51:04  avi
# invoke with -f
#
# Revision 1.1  2011/02/11  18:27:45  avi
# Initial revision
#

set idstr = '$Id: neo_t1w_to_t2w_4dfp.csh,v 1.2 2018/08/17 05:51:04 avi Exp $'
echo $idstr
set program = $0; set program = $program:t

if ($#argv < 1) goto Usage
set patid	= $1
set t4file = $patid"_mpr1_to_"$patid"_t2w_t4"

############################################
# compute T1W->T2W and T1W->atlas transforms
############################################
set t4file = $patid"_mpr1_to_"$patid"_t2w_t4"
set log =    $patid"_mpr1_to_"$patid"_t2w".log
echo $program $argv[1-] >! $log
echo $idstr             >> $log
date                    >> $log

set oristr = (T C S)
@ ori = `awk '/orientation/{print $NF - 1}' $patid"_t2w".4dfp.ifh`
t4_inv $RELEASE/$oristr[$ori]_t4 $$_t4
@ ori = `awk '/orientation/{print $NF - 1}' $patid"_mpr1".4dfp.ifh`
t4_mul $RELEASE/$oristr[$ori]_t4 $$_t4 $t4file
/bin/rm $$_t4

set modes = (4099 4099 1027 1035 2059 10251)
@ i = 1
while ($i <= $#modes)
        echo    imgreg_4dfp $patid"_t2w" none $patid"_mpr1" none $t4file $modes[$i]
        echo    imgreg_4dfp $patid"_t2w" none $patid"_mpr1" none $t4file $modes[$i] >> $log
                imgreg_4dfp $patid"_t2w" none $patid"_mpr1" none $t4file $modes[$i] >> $log
        @ i++
        if ($status) exit $status
end
t4_mul $t4file $patid"_t2w_to_711-2N_t4"	$patid"_mpr1_to_711-2N_t4"
t4_mul $t4file $patid"_t2w_to_term_N10_t2w_t4"	$patid"_mpr1_to_term_N10_t2w_t4"

################################
# resmaple mpr1 on t2w and atlas
################################
t4img_4dfp $t4file				$patid"_mpr1"	$patid"_mpr1_on_"$patid"_t2w" -O$patid"_t2w"
t4img_4dfp $patid"_mpr1_to_term_N10_t2w_t4"	$patid"_mpr1"	$patid"_mpr1_on_term_N10_t2w" -O$REFDIR/term_N10_t2w

exit 0

Usage:
echo "Usage:	"$program" <patid>"
echo " e.g.:	"$program caf102a40

exit 1
