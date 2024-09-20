#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/IBIS_fcMRI_preproc.csh,v 1.1 2018/08/17 06:04:19 avi Exp $
#$Log: IBIS_fcMRI_preproc.csh,v $
# Revision 1.1  2018/08/17  06:04:19  avi
# Initial revision
#

##############################
# fcMRI-specific preprocessing
##############################
set program = $0
set program = $program:t
set rcsid = '$Id: IBIS_fcMRI_preproc.csh,v 1.1 2018/08/17 06:04:19 avi Exp $'
echo $rcsid

if (${#argv} < 1) then
	echo "Usage:	$program <patid>"
	exit 1
endif 
date
uname -a

set patid = $1
set workdir = $cwd
set TR_vol = 2.5
@ skip = 4
set FCdir = FCmaps
echo "patid 	= $patid"
echo "workdir	= $workdir"	# contains $FCdir		
echo "TR_vol	= $TR_vol"
echo "skip	= $skip"
echo "FCdir 	= $FCdir"

#set echo

@ onestep = 0 		# if set then $program will exit at the end of each step
set blur	= .735452	# = .4413/6, i.e., 6 mm blur that is conservative relative to fidl's Monte Carlo
set WB_region	= $REFDIR/glm_atlas_mask_333
set VENT_WM_reg = ($REFDIR/711-2B_lat_vent_333 $REFDIR/small_WM)
if (! -e $WB_region.4dfp.img	|| ! -e $WB_region.4dfp.ifh		\
||  ! -e $VENT_WM_reg[1].4dfp.img	|| ! -e $VENT_WM_reg[1].4dfp.ifh	\
||  ! -e $VENT_WM_reg[2].4dfp.img	|| ! -e $VENT_WM_reg[2].4dfp.ifh) then
	echo $program error: standard nuisance regressor ROI 4dfp images not found
	exit -1
endif

if (! -e $FCdir) mkdir $FCdir
set concroot	= ${patid}_rmsp_faln_dbnd_xr3d_atl
set conc	= $concroot.conc

################
# debugging code
################
if ($onestep) then
	set echo
	pushd $FCdir; goto GLM
endif

##########################
# run compute_defined_4dfp
##########################
COMPUTE_DEFINED:
pushd $FCdir		# into $FCdir
compute_defined_4dfp $conc
if ($status) exit $status
maskimg_4dfp ${concroot}_dfnd $WB_region ${concroot}_dfndm
if ($status) exit $status

###################
# run run_dvar_4dfp
###################
run_dvar_4dfp $conc -m${concroot}_dfndm -n4 -x20
set format = `cat ${concroot}.format`

#####################
# compute initial sd1
#####################
var_4dfp -s -f$format	${concroot}.conc
ifh2hdr -r20		${concroot}_sd1
set sd1_WB0 = `qnt_4dfp ${concroot}_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`
if ($onestep) exit

##############
# spatial blur
##############
BLUR:
gauss_4dfp $conc $blur
if ($status) exit $status
if ($onestep) exit

##########################
# temporal bandpass filter
##########################
BANDPASS:
bandpass_4dfp ${concroot}_g7.conc $TR_vol -bh.1 -oh2 -E 
if ($status) exit $status
if ($onestep) exit

############################################################
# make movement regressors for each BOLD run
# convert rdat (within-run) and ddat (differentiated) output
# of mat2dat for use as regressors in glm_4dfp
############################################################
MOVEMENT:
set regr_output = $workdir/$FCdir/$patid"_mov_regressor".dat
if (-e $regr_output) /bin/rm $regr_output; touch $regr_output

gawk '/file:/{l=index($0,"file:"); print substr($0,l+5);}' $conc > $$.2
gawk '{gsub(/_atl.4dfp.img/,""); print}' $$.2 >! $$.3
set mats = (`cat $$.3`)
set regr_output = $patid"_mov_regressor".dat
if (-e $regr_output) /bin/rm $regr_output; touch $regr_output
if (! -e $RELEASE/trendout.awk) then
	echo $program error: $RELEASE/trendout.awk not found
	exit -1
endif
foreach F ($mats)
	mat2dat $F.mat -R -D
	if ($status) exit $status
	set out = $F"_movement_regressor.dat"
	awk '$1!~/#/{for (i = 2; i <= 7; i++) printf ("%10s", $i); printf ( "\n" );}' $F.rdat >! $$.0
	awk '$1!~/#/{for (i = 2; i <= 7; i++) printf ("%10s", $i); printf ( "\n" );}' $F.ddat >! $$.1
	paste $$.0 $$.1 >! $out		
	cat $out | gawk -f $RELEASE/trendout.awk >> $regr_output
end
/bin/rm $$.*
@ nframe = `wc $patid"_mov_regressor".dat | awk '{print $1}'`

#############################################################
# make the whole brain regressor including the 1st derivative
#############################################################
WB:
if (! ${?format}) set format = `conc2format $conc $skip`
qnt_4dfp -s -d -f$format ${concroot}_g7_bpss.conc $WB_region \
	| awk '$1!~/#/{printf("%10.4f%10.4f\n", $2, $3)}' >! ${patid}_WB_regressor_dt.dat
@ n = `wc ${patid}_WB_regressor_dt.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo $patid"_mov_regressor".dat ${patid}_WB_regressor_dt.dat length mismatch
	exit -1
endif

############################################################################
# make ventricle and bilateral white matter regressors and their derivatives
############################################################################
VENT_WM:
set output = ${patid}_vent_wm_dt.dat; if (-e $output) /bin/rm $output; touch $output
qnt_4dfp -s -d -f$format ${concroot}_g7_bpss.conc $VENT_WM_reg[1] \
	| awk '$1!~/#/{printf("%10.4f%10.4f\n", $2, $3)}' >! $output"1"
qnt_4dfp -s -d -f$format ${concroot}_g7_bpss.conc $VENT_WM_reg[2] \
	| awk '$1!~/#/{printf("%10.4f%10.4f\n", $2, $3)}' >! $output"2"
paste $output"1" $output"2" >! $output
/bin/rm $output*[12]
@ n = `wc ${patid}_vent_wm_dt.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo $patid"_mov_regressor".dat ${patid}_vent_wm_dt.dat.dat length mismatch
	exit -1
endif

#############################################
# optional externally supplied task regressor
#############################################
TASK:
if (! ${?task_regressor}) set task_regressor = ""
if ($task_regressor != "") then
	if (! -r $task_regressor) then
		echo $task_regressor not accessible
		exit -1
	endif
	@ n = `wc $task_regressor | awk '{print $1}'`
	if ($n != $nframe) then
		echo $patid"_mov_regressor".dat $task_regressor length mismatch
		exit -1
	endif
endif

####################################
# paste nuisance regressors together
####################################
PASTE:
set WB = ${patid}_WB_regressor_dt.dat
if (${?noGSR}) then
	if ($noGSR) set WB = ""
endif
paste ${patid}_mov_regressor.dat $WB ${patid}_vent_wm_dt.dat $task_regressor >! ${patid}_nuisance_regressors.dat
set illcond = `covariance $format ${patid}_nuisance_regressors.dat -e | tail -1 | gawk '$2 > 1.e4{k++;};END{print k + 0;}'`
if (-e ${patid}_nuisance_regressors.dat1) /bin/rm ${patid}_nuisance_regressors.dat1
if ($illcond) then
	covariance $format ${patid}_nuisance_regressors.dat -D100
	ln -s ${patid}_nuisance_regressors_SVD*.dat	${patid}_nuisance_regressors.dat1
else
	ln -s ${patid}_nuisance_regressors.dat 		${patid}_nuisance_regressors.dat1
endif

##########################################################################
# run glm_4dfp to remove nuisance regressors out of volumetric time series
##########################################################################
GLM:
glm_4dfp $format ${patid}_nuisance_regressors.dat1	${concroot}_g7_bpss.conc -rresid -o
if ($status) exit $status
ifh2hdr -r-20to20					${concroot}_g7_bpss_coeff

##################################
# rerun run_dvar_4dfp and var_4dfp
##################################
run_dvar_4dfp ${concroot}_g7_bpss_resid.conc -m${concroot}_dfndm -n4 -x4
set format = `cat ${concroot}_g7_bpss_resid.format`
var_4dfp -s -f$format					${concroot}_g7_bpss_resid.conc
if ($status) exit $status
ifh2hdr -r20						${concroot}_g7_bpss_resid_sd1
set sd1_WB1 = `qnt_4dfp ${concroot}_g7_bpss_resid_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`

echo $sd1_WB0 | awk '{printf("whole brain mean sd1 before fcMRI preprocessing = %8.4f\n",$1)}'
echo $sd1_WB1 | awk '{printf("whole brain mean sd1  after fcMRI preprocessing = %8.4f\n",$1)}'

popd		# out of $FCdir
exit 0

