#!/bin/csh

set program = `basename $0`

set g  = 1.3
set gx = `echo $g | gawk '{print "g"10*$1}'`
set b  = 5
set bx = `echo $b | gawk '{print "b"10*$1}'`

if ($#argv != 2) then
	echo "Usage: $program <mpr(4dfp)> <pet(4dfp)>"
	echo "N.B.: blurs mpr with $gx and pet with $bx"
	echo "N.B.: requires <mpr_mskt(4dfp)> or mpr2atlas t4"
	exit 1
endif

set mprroot = `~larsc/bin/getroot.csh $1`
set petroot = `~larsc/bin/getroot.csh $2`

set mprbase = `basename $mprroot`
set petbase = `basename $petroot`
set t41     = ${petbase}_to_${mprbase}_t4
set t42     = ${mprbase}_to_${petbase}_t4

set S       = `~larsc/bin/findrelease.csh`
set oristr  = (T C S)

foreach img ($mprroot $petroot)
	if (! -e ${img}.4dfp.img || ! -e ${img}.4dfp.ifh) then
		echo "${program}: $img not found"
		exit 1
	endif
end

if (! -e $t42) then
	if (! -e $t41) then
		set ori = `gawk '/orientation/ {print $NF-1}' ${mprroot}.4dfp.ifh ${petroot}.4dfp.ifh`
		$S/t4_inv $S/$oristr[$ori[1]]_t4 temp$$_t4
		$S/t4_mul $S/$oristr[$ori[2]]_t4 temp$$_t4 $t41
		rm temp$$_t4
	endif
	$S/t4_inv $t41 $t42
else
	if (! -e $t41) $S/t4_inv $t42 $t41
endif

~larsc/bin/mpr_reg_prep.csh $mprroot
~larsc/bin/pet_reg_prep.csh $petroot

#~larsc/bin/img_reg.csh ${mprroot}_${gx} ${mprroot}_mskt ${petroot}_${bx} ${petroot}_msk  $t41
~larsc/bin/img_reg.csh ${mprroot}_${gx} ${mprroot}_mskt ${petroot}_${bx} none  $t41
#imgreg_4dfp ${mprroot}_${gx} none ${petroot}_${bx} none  $t41 10243 >> $t41.log
#~larsc/bin/img_reg.csh ${petroot}_${bx} ${petroot}_msk  ${mprroot}_${gx} ${mprroot}_mskt $t42
~larsc/bin/img_reg.csh ${petroot}_${bx} none  ${mprroot}_${gx} ${mprroot}_mskt $t42
#imgreg_4dfp ${petroot}_${bx} none  ${mprroot}_${gx} none $t42 10243 >> $t42.log

t4_resolve $mprroot $petroot -OMR >! ${mprroot}_${petroot}_mov.log
exit 0
