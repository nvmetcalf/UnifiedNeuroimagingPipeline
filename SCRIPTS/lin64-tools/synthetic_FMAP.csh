#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/synthetic_FMAP.csh,v 1.3 2021/12/13 22:51:25 tanenbauma Exp $
#$Log: synthetic_FMAP.csh,v $
# Revision 1.3  2021/12/13  22:51:25  tanenbauma
# replaced realpath with readlink
#
# Revision 1.2  2021/12/07  17:59:18  avi
# better logging
#
#Revision 1.1  2020/08/27 20:41:16  avi
#Initial revision
#
set idstr = '$Id: synthetic_FMAP.csh,v 1.3 2021/12/13 22:51:25 tanenbauma Exp $'
echo $idstr
set program = $0:t
set niter = 0
set warpdir = $cwd
setenv FSLOUTPUTTYPE NIFTI

if ( $?FSLDIR == 0 ) then
	echo "Error: FSLDIR environment variable needs to be set"
	exit -1
endif

if ( $?RELEASE == 0 ) then
	echo "Error: RELEASE environment variable needs to be set"
	exit -1
endif

@ n = ${#argv}
if ( $n < 9 ) goto USAGE
set epi       = $argv[1]
set epimsk    = $argv[2]
set struct    = $argv[3]
set structmsk = $argv[4]
set warp      = $argv[5]	# warp is assumed to be from struct to the mean and bases   
set mean      = $argv[6]
set dwell     = $argv[7]	# effective echo spaceing in units of sec	
set ped       = $argv[8]
set outroot   = $argv[9]
set bases     = ''; set nbases = 0; set niter = 0;

@ i = 10
while ( $i <= $n )
	switch ( $argv[$i] )
	case "-bases":
		@ i++
		set bases = $argv[$i]; @ i++
		set nbases = $argv[$i]; @ i++
		set niter = $argv[$i]; @ i++
		breaksw;
	case "-dir"
		@ i++ 
		set warpdir = $argv[$i]; @ i++
		breaksw;
	default:
		echo "unknown argument"
		goto USAGE
	endsw
end

if ( ! -d $warpdir ) mkdir $warpdir
set rmstr = ''

## Set up EPI
set epi = `echo $epi | sed 's|\.4dfp\....$||'`
if ( `readlink -f ${epi:h}` != `readlink -f ${warpdir}` ) then 
	cp -f ${epi}.4dfp.img ${epi}.4dfp.ifh ${epi}.4dfp.img.rec*  ${warpdir} || exit $status
	set rmstr = "$rmstr ${warpdir}/${epi:t}.*  ${warpdir}/${epi:t}.nii"
endif
set epi = ${epi:t}
nifti_4dfp -n ${warpdir}/${epi} ${warpdir}/${epi}

## Set up EPI mask
set epimsk = `echo $epimsk | sed 's|\.4dfp\....$||'`
if ( `readlink -f ${epimsk:h}` != `readlink -f ${warpdir}` ) then 
	cp -f ${epimsk}.4dfp.img ${epimsk}.4dfp.ifh ${epimsk}.4dfp.img.rec* ${warpdir} || exit $status
	set rmstr = "$rmstr ${warpdir}/${epimsk:t}.* ${warpdir}/${epimsk:t}.nii"
endif
set epimsk = ${epimsk:t}
nifti_4dfp -n ${warpdir}/${epimsk} ${warpdir}/${epimsk}

## Set up structual image
set struct = `echo $struct | sed 's|\.4dfp\....$||'`
if ( `readlink -f ${struct:h}` != `readlink -f ${warpdir}` ) then 
	cp -f ${struct}.4dfp.img ${struct}.4dfp.img.rec* ${struct}.4dfp.ifh ${warpdir} || exit $status
	set rmstr = "$rmstr ${warpdir}/${struct:t}.4dfp.* ${warpdir}/${struct:t}.nii"
endif
set struct = ${struct:t}
nifti_4dfp -n ${warpdir}/${struct}  ${warpdir}/${struct}

## Set up structual image mask
set structmsk = `echo $structmsk | sed 's|\.4dfp\....$||'`
if ( `readlink -f ${structmsk:h}` != `readlink -f ${warpdir}` ) then 
	cp -f ${structmsk}.4dfp.img ${structmsk}.4dfp.img.rec* ${structmsk}.4dfp.ifh ${warpdir} || exit $status
	set rmstr = "$rmstr ${warpdir}/${structmsk:t}.4dfp.*"
endif
set structmsk = ${structmsk:t}

## Set up Mean
set mean = `echo $mean | sed 's|\.4dfp\....$||'`
set d = `dirname $mean`
if ( `readlink -f $d` != `readlink -f ${warpdir}` ) then 
	cp -fv ${mean}.4dfp.img ${mean}.4dfp.ifh ${warpdir} || exit $status
	set rmstr = "$rmstr ${warpdir}/${mean:t}.4dfp.* ${warpdir}/${mean:t}.nii"
endif
set mean = ${mean:t}
nifti_4dfp -n ${warpdir}/${mean} ${warpdir}/${mean}

if ( $bases != '' ) then
	set bases = `echo $bases | sed 's|\.4dfp\....$||'`
	echo "$bases 1 $nbases" > $$.bases.lst    	
	paste_4dfp -a $$.bases.lst ${warpdir}/${bases:t}_f1_to_f$nbases || exit $status
	set bases = ${bases:t}_f1_to_f$nbases
	nifti_4dfp -n ${warpdir}/${bases} ${warpdir}/${bases} || exit $status
	set rmstr = "$rmstr ${warpdir}/${bases}.*"
	rm $$.bases.lst
endif
pushd $warpdir
	set mode = ( 4099 1027 2051 2051 10243)
	set msk  = ( none none ${epimsk} ${epimsk} ${epimsk} )
	set t4file = ${epi}_to_${struct}_t4
	if ( -e ${epi}_to_${struct}_t4 )  rm ${epi}_to_${struct}_t4 
	if ( -e ${epi}_to_${struct}.log ) rm ${epi}_to_${struct}.log
	@ k = 1
	while ( $k <= $#mode )
		imgreg_4dfp ${struct} ${structmsk} ${epi} $msk[$k]  $t4file ${mode[$k]} >> ${epi}_to_${struct}.log  || exit $status
		@ k++
	end
	aff_conv 4f $epi $struct $t4file $epi $struct ${epi}_to_${struct}.mat
	convertwarp --ref=$mean --premat=${epi}_to_${struct}.mat --warp1=$warp --out=${epi}_to_${mean}_warp || exit $status
	invwarp --ref=${epi} --warp=${epi}_to_${mean}_warp --out=${mean}_to_${epi}_warp || exit $status
	
	applywarp --ref=$epi --in=${mean} --warp=${mean}_to_${epi}_warp --out=${mean}_on_${epi} || exit $status
	nifti_4dfp -4 ${mean}_on_${epi} ${mean}_on_${epi} || exit $status
	
	if ( $bases != '') then 
		applywarp --ref=$epi --in=${bases} --warp=${mean}_to_${epi}_warp --out=${bases}_on_${epi} || exit $status
		nifti_4dfp -4 ${bases}_on_${epi} ${bases}_on_${epi}  || exit $status
		rm ${bases}_on_${epi}.nii
	endif
	####################
	# get method and run
	####################
	set log = ${epi}_basis_opt.log; date >! $log
	if ( $niter == 0 ) then
		foreach e ( .img .ifh .hdr )
			mv ${mean}_on_${epi}.4dfp.$e ${outroot}_on_${epi}.4dfp.$e
		end
		mv  ${mean}_on_${epi}.nii ${outroot}_on_${epi}.nii 
		##################################
		# undistort EPI with new field map
		##################################
	echo	$FSLDIR/bin/fugue --loadfmap=${outroot}_on_${epi} --dwell=$dwell --in=$epi -u ${epi}_uwrp \
			--unwarpdir=$ped --saveshift=${epi}_uwrp_shift_map
		$FSLDIR/bin/fugue --loadfmap=${outroot}_on_${epi} --dwell=$dwell --in=$epi -u ${epi}_uwrp \
			--unwarpdir=$ped --saveshift=${epi}_uwrp_shift_map >> $log || exit $status
		nifti_4dfp -4 ${epi}_uwrp ${epi}_uwrp || exit $status
		####################
		# compute new t4file
		####################
		cp $t4file ${epi}_uwrp_to_${struct}_t4 
		imgreg_4dfp $struct $structmsk ${epi}_uwrp $epimsk ${epi}_uwrp_to_${struct}_t4 10243 || exit $status
		###########################################
		# transform unwarped EPI to structual space
		###########################################
		t4img_4dfp ${epi}_uwrp_to_${struct}_t4 ${epi}_uwrp ${epi}_uwrp_on_${struct} -O${struct} || exit $status
		exit $status
	else
		if ( ! $?nbases) set nbasis = 6 
		if ( ! $?basis_opt) set basis_opt = basis_opt_AT
		if ( ! $?range_shrink ) set range_shrink = 1
		if ( ! $?range ) set range = 0.01
###################################
# make parameter file for basis_opt
###################################
		echo "set epi          = $epi"				>! ${epi}_basis_opt.params
		echo "set basis        = ${bases}_on_${epi}"		>> ${epi}_basis_opt.params
		echo "set mean         = ${mean}_on_${epi}"		>> ${epi}_basis_opt.params
		echo "set dir          = $ped"				>> ${epi}_basis_opt.params
		echo "set phase        = ${outroot}_on_${epi}"		>> ${epi}_basis_opt.params
		echo "set struct       = $struct"			>> ${epi}_basis_opt.params
		echo "set struct_mskt  = $structmsk"			>> ${epi}_basis_opt.params
		echo "set t4           = ${epi}_to_${struct}_t4"	>> ${epi}_basis_opt.params
		echo "set unwarp_Aaron = unwarp_eta_AT.csh"		>> ${epi}_basis_opt.params
		
##################################
# make a weight file for basis_opt
##################################
		echo "Echo Spacing: $dwell"				>! ${epi}_basis_opt.weights
		echo "Weights: $nbases"					>> ${epi}_basis_opt.weights
###############################################
# run basis_opt with created params and weights
###############################################
	echo 	$basis_opt ${epi}_basis_opt.params ${epi}_basis_opt.weights -n$niter -e$range -s$range_shrink
	echo 	$basis_opt ${epi}_basis_opt.params ${epi}_basis_opt.weights -n$niter -e$range -s$range_shrink >> $log
		$basis_opt ${epi}_basis_opt.params ${epi}_basis_opt.weights -n$niter -e$range -s$range_shrink >> $log
		mv ${outroot}_on_${epi}.4dfp.img ${outroot}_on_${epi}_uwrp.4dfp.img 
		mv ${outroot}_on_${epi}.4dfp.ifh ${outroot}_on_${epi}_uwrp.4dfp.ifh
		nifti_4dfp -n ${epi}_uwrp ${epi}_uwrp
		ifh2hdr ${outroot}_on_${epi}_uwrp
		ifh2hdr ${epi}_uwrp
	endif
	date >> $log
popd	# out of $warpdir
rm -f $rmstr ${warpdir}/${mean}_on_${epi}.*
if  ( $?bases ) then 
	rm -f ${warpdir}/${bases}_on_${epi}.* ${warpdir}/*tmp*
endif
echo successful completion $program
exit 0

USAGE:
/bin/echo -e "${program}:"
/bin/echo -e "SYNOPSIS:"
/bin/echo -e "${program} <epi> <epi_mask> <structural> <structural_mask> <warp> <mean> <dwell> <ped> <outroot> [-dir wrkdir] [-bases path nbases niter]" 
/bin/echo -e "DESCRIPTION:"
/bin/echo -e "	Generates a synthetic field map generated by optimizing a linear combination of a set of componants derived from a larger set of preprocessed field maps."
/bin/echo -e "	epi		Path to epi that need distortion correction. Image must be in 4dfp format."
/bin/echo -e "	epi_mask	The epi brain mask"
/bin/echo -e "	structural	Path to the structural image. must be in 4dfp format."
/bin/echo -e "	structural_mask	Path to a brain mask in structural space. must be in 4dfp format."
/bin/echo -e "	warp		The non-linear from structural to mean and bases space."
/bin/echo -e "	mean		mean field map."
/bin/echo -e "	dwell		The effective echo spacing of the epi. must in in units of seconds"
/bin/echo -e "	ped		Phase encoding direction of the epi. ( x x- y y-)"
/bin/echo -e "	outroot		outroot name of the sythetic fieldmap"
/bin/echo -e "optional arguments"
/bin/echo -e "	-dir <directory>		The output directory (default current working directory)"
/bin/echo -e "	-bases <path> <nbases> <niter>	Use if you want to use bases components in estimating"
/bin/echo -e "					synthetic field map. Flag requires the full path to the"
/bin/echo -e "					bases set in 4dfp format the number of bases you want to use and the number of iterations."
exit 1
