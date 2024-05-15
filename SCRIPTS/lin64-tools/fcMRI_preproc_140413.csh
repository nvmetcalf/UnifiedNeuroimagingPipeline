#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/fcMRI_preproc_140413.csh,v 1.5 2018/08/17 05:47:40 avi Exp $
#$Log: fcMRI_preproc_140413.csh,v $
# Revision 1.5  2018/08/17  05:47:40  avi
# invoke with -f
#
# Revision 1.4  2015/05/30  02:46:09  avi
# use -F instead of -f option with bandpass_4dfp
#
# Revision 1.3  2015/02/16  04:09:58  avi
# report whole brain mean sd1 after regression and after spatio-temporal filtering
#
# Revision 1.2  2014/08/22  01:10:43  avi
# compute nuisance regressors after voxelwize de-meaning
#
# Revision 1.1  2014/08/20  01:32:12  avi
# Initial revision
#

##############################
# fcMRI-specific preprocessing
##############################
set program = $0
set program = $program:t
set rcsid = '$Id: fcMRI_preproc_140413.csh,v 1.5 2018/08/17 05:47:40 avi Exp $'
echo $rcsid

if (${#argv} < 1) then
	echo "Usage:	$program <parameters file> [instructions]"
	echo "e.g.,	$program VB16168.params"
	exit 1
endif 
date
uname -a

set prmfile = $1
if (! -e $prmfile) then
	echo $prmfile not found
	exit -1
endif
source $prmfile
if (${#argv} > 1) then
	set instructions = $2
	if (! -e $instructions) then
		echo $program": "$instructions not found
		exit -1
	endif
	cat $instructions
	source $instructions
endif

if (! ${?FCdir}) set FCdir = FCmaps
echo "##### list parameters from $prmfile #####"
echo "patid 	= $patid"
echo "srcdir	= $srcdir"	# containes bold directories
echo "workdir	= $workdir"	# contains $FCdir		
echo "TR_vol	= $TR_vol"
echo "skip	= $skip"
echo "FCdir 	= $FCdir"
echo "##### end parameters list #####"

@ onestep = 0 		# if set then $program will exit at the end of each step
set WB_region	= $REFDIR/glm_atlas_mask_333
set VENT_WM_reg = ($REFDIR/711-2B_lat_vent_333 $REFDIR/small_WM)
if (! -e $WB_region.4dfp.img	|| ! -e $WB_region.4dfp.ifh		\
||  ! -e $VENT_WM_reg[1].4dfp.img	|| ! -e $VENT_WM_reg[1].4dfp.ifh	\
||  ! -e $VENT_WM_reg[2].4dfp.img	|| ! -e $VENT_WM_reg[2].4dfp.ifh) then
	echo $program error: standard nuisance regressor ROI 4dfp images not found
	exit -1
endif

if (! ${?anat_aveb}) set anat_aveb = 10	# = run_dvar_4dfp preblur in mm
if (! ${?anat_avet}) set anat_avet = 7	# = run_dvar_4dfp criterion
if (! ${?FWHM}) set FWHM = 6		# = spatial blur (in each direction) in mm
if (! ${?MB}) @ MB = 0			# skip slice timing correction and debanding
set MBstr = _faln_dbnd; if ($MB) set MBstr = ""

if (! -e $FCdir) mkdir $FCdir
if (! ${?conc}) then
	set concroot	= ${patid}${MBstr}_xr3d_atl
	set conc	= $concroot.conc
else
	set concroot = $conc:r
	if (-e $conc) then
		/bin/cp $conc* $FCdir
		if ($status) exit $status
		goto COMPUTE_DEFINED
	endif
endif
####################################
# make conc file and mv it to $FCdir
####################################
CONC:
touch $$.lst
foreach run ($fcbolds)
	set file = $srcdir/bold$run/$patid"_b"$run${MBstr}"_xr3d_atl"			
	echo $file >> $$.lst
end
conc_4dfp $concroot -l$$.lst -w
if ($status) exit $status
/bin/rm $$.lst
/bin/mv $conc* $FCdir

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
echo	run_dvar_4dfp ${concroot}.conc -m${concroot}_dfndm -n$skip -x$anat_avet -b$anat_aveb
	run_dvar_4dfp ${concroot}.conc -m${concroot}_dfndm -n$skip -x$anat_avet -b$anat_aveb
set format = `cat ${concroot}.format`

#####################
# compute initial sd1
#####################
var_4dfp -s -f$format	${concroot}.conc	# option -s creates ${concroot}_sd1
var_4dfp -m -f$format	${concroot}.conc	# option -m creates ${concroot}_uout.conc
ifh2hdr -r20		${concroot}_sd1
set sd1_WB0 = `qnt_4dfp ${concroot}_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`
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
qnt_4dfp -s -d -f$format ${concroot}_uout.conc $WB_region \
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
qnt_4dfp -s -d -f$format ${concroot}_uout.conc $VENT_WM_reg[1] \
	| awk '$1!~/#/{printf("%10.4f%10.4f\n", $2, $3)}' >! $output"1"
qnt_4dfp -s -d -f$format ${concroot}_uout.conc $VENT_WM_reg[2] \
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

##########################################################################
# run glm_4dfp to remove nuisance regressors out of volumetric time series
##########################################################################
GLM:
glm_4dfp $format ${patid}_nuisance_regressors.dat		${concroot}_uout.conc -rresid -o
if ($status) exit $status
ifh2hdr -r-20to20						${concroot}_uout_coeff
var_4dfp -s -f$format						${concroot}_uout_resid.conc
if ($status) exit $status
ifh2hdr -r20							${concroot}_uout_resid_sd1
set sd1_WB1 = `qnt_4dfp ${concroot}_uout_resid_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`

##########################
# temporal bandpass filter
##########################
BANDPASS:
bandpass_4dfp ${concroot}_uout_resid.conc $TR_vol -bh.1 -oh2 -EB -F${concroot}.format
if ($status) exit $status
if ($onestep) exit

##############
# spatial blur
##############
BLUR:
set blur = `echo 4.413/$FWHM | bc -l | awk '{printf ("%.6f", $1)}'`
gauss_4dfp ${concroot}_uout_resid_bpss.conc $blur
if ($status) exit $status
if ($onestep) exit

var_4dfp -s -f$format						${concroot}_uout_resid_bpss_g7.conc
if ($status) exit $status
ifh2hdr -r20							${concroot}_uout_resid_bpss_g7_sd1
set sd1_WB2 = `qnt_4dfp ${concroot}_uout_resid_bpss_g7_sd1	${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`

echo $sd1_WB0 | awk '{printf("whole brain mean sd1 before fcMRI preprocessing =   %8.4f\n",$1)}'
echo $sd1_WB1 | awk '{printf("whole brain mean sd1 after nuisance regression =    %8.4f\n",$1)}'
echo $sd1_WB2 | awk '{printf("whole brain mean sd1 after regression & filtering = %8.4f\n",$1)}'

popd		# out of $FCdir
exit
