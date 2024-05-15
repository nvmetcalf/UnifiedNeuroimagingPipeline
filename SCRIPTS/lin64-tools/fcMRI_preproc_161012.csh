#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/fcMRI_preproc_161012.csh,v 1.11 2020/11/15 01:30:03 avi Exp $
#$Log: fcMRI_preproc_161012.csh,v $
# Revision 1.11  2020/11/15  01:30:03  avi
# new params variable autocrit_S: cause find_dvar_crit.awk to smooth historgram before finding mode
#
# Revision 1.10  2020/07/24  21:38:48  avi
# dbnd_flag control
#
# Revision 1.9  2020/04/25  04:07:07  avi
# control autocrit tolerance in find_dvar_crit.awk via option -T<autocrit_tol> in call to run_dvar_4dfp
#
# Revision 1.8  2018/10/15  22:10:15  avi
# typo in GSR message
#
# Revision 1.7  2018/10/06  06:44:02  avi
# params switch $noWM
# echo actually used regressors to stdout
#
# Revision 1.6  2018/08/17  06:11:48  avi
# invoke csh with -f
#
# Revision 1.5  2016/11/10  17:38:08  avi
# user control of CSF_excl_lim
#
# Revision 1.4  2016/10/27  06:14:54  avi
# substantial revision of frame-censoring code
#
# Revision 1.3  2016/10/26  23:16:36  avi
# exit if movement/ subdirectory is not present
#
# Revision 1.2  2016/10/25  01:09:06  avi
# more general FD logic
#
# Revision 1.1  2016/10/12  20:14:17  avi
# Initial revision
#
# Revision 1.20  2016/06/12  00:28:47  avi
# define $anat_avet by value in atlas if it is not defined
#
# Revision 1.19  2016/05/12  00:26:26  avi
# correct login in computing bpss flag
#
# Revision 1.18  2016/03/29  00:57:21  avi
# remove dilated FSWB mask from extra-axial CSF ROI
#
# Revision 1.17  2016/03/10  00:20:37  avi
# $concroot and $blurstr logic
#
# Revision 1.16  2016/03/01  03:07:33  avi
# use option -F (specify format as file) with several executables
#
# Revision 1.15  2016/02/10  04:36:37  avi
# run nuisance regressors through covariance -D250 before final assembly
#
# Revision 1.14  2016/02/09  23:47:49  avi
# modify logic to tolerate small ventricles
#
# Revision 1.13  2015/02/13  01:30:11  avi
# if $conc is defined, then use it to compute $format *in $FCdir*; i.e., do *not* use _func_vols_ave in atlas
#
# Revision 1.12  2014/08/23  06:05:30  avi
# extract global signal from ${concroot}_uout.conc rather than ${concroot}.conc
#
# Revision 1.11  2014/07/02  23:14:13  avi
# generate  ${concroot}_uout as a first step
# remove "-Z" from calls to qntv_4dfp to use new tolerance for undefined volumetric timeseries datapoints (and add -D)
#
# Revision 1.10  2014/06/02  03:06:58  avi
# tolerate $day1_patid == ""
#
# Revision 1.9  2014/06/02  02:12:51  avi
# correct incorrect SVD threshold argument passed to qntv_4dfp (should have been $CSF_svdt)
#
# Revision 1.8  2014/02/22  23:32:40  avi
# always define patid1 (on the basis of $day1_patid)
#
# Revision 1.7  2014/02/22  07:43:51  avi
# consistent use of $min_frames
#
# Revision 1.6  2014/02/22  06:06:07  avi
# set patid1 = $day1_patid
#
# Revision 1.5  2014/02/21  06:56:29  avi
# handle combined concs representing multiple sessions - define patid1
#
# Revision 1.4  2014/02/19  04:46:39  avi
# tolerate no ventricle regressors
#
# Revision 1.3  2014/02/14  02:53:20  avi
# typo
#
# Revision 1.2  2014/02/14  02:18:14  avi
# $min_frames settable
#
# Revision 1.1  2013/11/08  05:12:58  avi
# Initial revision
#

##############################
# fcMRI-specific preprocessing
##############################
set program = $0
set program = $program:t
set rcsid = '$Id: fcMRI_preproc_161012.csh,v 1.11 2020/11/15 01:30:03 avi Exp $'
echo $rcsid

if (${#argv} < 1) then
	echo "Usage:	$program <parameters file> [instructions]"
	echo "e.g.,	$program VB16168.params"
	exit 1
endif 
date
uname -a
echo $program $argv[1-]

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
echo "patid 	= "$patid
echo "target	= "$target
echo "FCdir 	= "$FCdir
echo "FSdir 	= "$FSdir
echo "##### end parameters list #####"
if (! ${?day1_patid}) set day1_patid = ""
if ($day1_patid != "") then
	set patid1 = $day1_patid
else
	set patid1 = $patid
endif

#######################################
#Setting up slice timing and debanding
#######################################
if (! ${?MB}) @ MB = 0			# skip slice timing correction and debanding
if (! ${?MBfac}) @ MBfac = 1
if ( ! $MB ) then 
	if (! ${?interleave}) set interleave = ""
	if (${?Siemens_interleave}) then
		if ($Siemens_interleave) set interleave = "-N"
	endif
	if ( ${?seqstr} ) then
		set SLT = ( `echo $seqstr | sed 's|,| |g'` ) 
		@ k = 3
		set difftime = `echo $SLT[2] - $SLT[1] | bc -l`
		set dbnd_flag = 1
		if ( $difftime != "-2" && $difftime != "2") set dbnd_flag = 0
		set SWITCH = 0; 
		while ( $dbnd_flag  && $k <= $#SLT )
			@ l = $k - 1
			if ( `echo $SLT[$k] - $SLT[$l] != $difftime | bc -l` && $SWITCH == 1) then
				 set dbnd_flag = 0
			else if ( `echo $SLT[$k] - $SLT[$l] != $difftime | bc -l` ) then 
				set  SWITCH = 1
			endif
			@ k++
		end
	else if ( "$interleave" == "" || "$interleave" == "-N" ) then
		set dbnd_flag = 1
	else if ( "$interleave" == "-S" ) then
		set dbnd_flag = 0
	endif
	if ($dbnd_flag) then
		set MBstr = _faln_dbnd
	else
		set MBstr = _faln
	endif
else 
	set MBstr = ""
endif

if (! ${?blur}) set blur = 0
if (! ${?bpss_params}) set bpss_params = ()
@ bpss = ${#bpss_params}	# bandpass_4dfp run flag

###################################################
# run Generate_FS_Masks (results left in ../atlas/)
###################################################
if ( ! -e atlas/${patid1}_CS_erode_on_${target:t}_333_clus.4dfp.img ) then 
	Generate_FS_Masks_AZS.csh $prmfile $instructions
	if ($status) exit $status
endif 
if (! -e $FCdir) mkdir $FCdir
if (! ${?conc}) then
###################################
# make conc file and move to $FCdir
###################################
	set concroot	= ${patid}${MBstr}_xr3d_uwrp_atl
	set conc	= $concroot.conc
	touch $$.lst
	foreach run ($fcbolds)
		set file = $srcdir/bold$run/$patid"_b"$run${MBstr}"_xr3d_uwrp_atl"			
		echo $file >> $$.lst
	end
	conc_4dfp $concroot -l$$.lst -w
	if ($status) exit $status
	if (-e $$.lst) /bin/rm $$.lst
	/bin/mv $conc* $FCdir
else
	if (! -e $conc) then
		echo $program": "$conc defined in params but does not exist
		exit -1
	endif
	set concroot = $conc:r
	/bin/cp $conc* $FCdir
endif

pushd $FCdir		# into $FCdir
/bin/rm ${patid1}_FSWB_on_${target:t}_333.4dfp.*
foreach e (img img.rec ifh hdr)
	ln -s ../atlas/${patid1}_FSWB_on_${target:t}_333.4dfp.$e .	# symbolically link FS whole brain mask
	if ($status) exit $status
end

if (${?fmtfile}) goto COMPUTE_DEFINED
set fmtfile = ${concroot}.format
#########################
# compute frame censoring
#########################
pushd ../movement	# from $FCdir
if ($status) exit $status
if (-e ${patid}${MBstr}"_xr3d".FD) /bin/rm	${patid}${MBstr}"_xr3d".FD
touch						${patid}${MBstr}"_xr3d".FD
@ k = 1
while ($k <= ${#irun})
	gawk -f $RELEASE/FD.awk $patid"_b"$irun[$k]${MBstr}"_xr3d".ddat >> ${patid}${MBstr}"_xr3d".FD
	@ k++
end
if ($?FDthresh) then 
	if (! ${?FDtype}) @ FDtype = 1
	conc2format ../$FCdir/$conc $skip >! $$.format2
	format2lst $$.format2 >! $$.format0
	gawk '{c="+";if ($'$FDtype' > crit)c="x"; printf ("%s\n",c)}' crit=$FDthresh ${patid}${MBstr}"_xr3d".FD >! $$.format1
	paste $$.format0 $$.format1 | awk '{if($1=="x")$2="x";printf("%s",$2)}' >! ${patid}${MBstr}"_xr3d".FD.format
	/bin/rm $$.format[012]
	/bin/mv ${patid}${MBstr}"_xr3d".FD.format ../$FCdir/
endif 
popd			# back to $FCdir

if (! ${?anat_aveb}) set anat_aveb = 0.		# dvar_4dfp pre-blur
if (! ${?anat_avet}) then
	set xstr = ""				# compute DVARS censoring threshold using find_dvar_crit.awk
else
	set xstr = -x$anat_avet			# use specified DVARS censoring threshold
endif
if (! ${?autocrit_tol}) then
	set tolstr = ""				# set run_dvar_4dfp crit tolerance sd units
else
	set tolstr = -T$autocrit_tol
endif
if (! ${?autocrit_S}) @ autocrit_S = 0		# smooth DVARS histogram before finding mode
if ($autocrit_S) set tolstr = $tolstr" -S"
echo	run_dvar_4dfp $conc -m${patid1}_FSWB_on_${target:t}_333 -n$skip $tolstr $xstr -b$anat_aveb
	run_dvar_4dfp $conc -m${patid1}_FSWB_on_${target:t}_333 -n$skip $tolstr $xstr -b$anat_aveb
if ($status) exit $status
format2lst -e $concroot.format >! $concroot.dvar.format

if (${?FDthresh}) then 
	format2lst $fmtfile >! $$.format1
	format2lst ${patid}${MBstr}"_xr3d".FD.format >! $$.format2
	paste $$.format1 $$.format2 | gawk '{if($1=="x")$2="x";printf("%s",$2);}' | xargs condense >! $fmtfile
	/bin/rm $$.format1 $$.format2
endif
set str = `format2lst -e $fmtfile | gawk '{k=0;l=length($1);for(i=1;i<=l;i++)if(substr($1,i,1)=="x")k++;}END{print k, l;}'`
echo $str[1] out of $str[2] frames fail frame rejection criteria
if (! ${?min_frames}) @ min_frames = $str[2] / 2
@ j = $str[2] - $str[1]; if ($j < $min_frames) exit 1	# require at least $min_frames to pass users criterion

##################################
# compute uncensored frame average
##################################
echo	actmapf_4dfp $fmtfile $conc -aave
	actmapf_4dfp $fmtfile $conc -aave
echo	ifh2hdr	-r2000	${concroot}_ave
	ifh2hdr	-r2000	${concroot}_ave
if ($status) exit $status

COMPUTE_DEFINED:
##########################
# run compute_defined_4dfp
##########################
compute_defined_4dfp -F$fmtfile ${concroot}.conc
if ($status) exit $status
maskimg_4dfp ${concroot}_dfnd ../atlas/${patid1}_FSWB_on_${target:t}_333 ${concroot}_dfndm
if ($status) exit $status

#####################
# compute initial sd1
#####################
var_4dfp -s -F$fmtfile	${concroot}.conc
ifh2hdr -r20		${concroot}_sd1
set sd1_WB0 = `qnt_4dfp ${concroot}_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`

UOUT:
###########################
# make timeseries zero mean
###########################
echo	var_4dfp -F$fmtfile -m $conc
	var_4dfp -F$fmtfile -m $conc
if ($status) exit $status

############################################
# make movement regressors for each BOLD run
############################################
MOVEMENT:
touch $$.lst
foreach run ($fcbolds)
	mat2dat    $srcdir/bold$run/$patid"_b"$run${MBstr}"_xr3d" -I
	set file = $srcdir/bold$run/$patid"_b"$run${MBstr}"_xr3d_dat"			
	echo $file >> $$.lst
end
conc_4dfp ${patid}${MBstr}"_xr3d_dat" -l$$.lst -w
if ($status) exit $status
/bin/rm $$.lst
bandpass_4dfp ${patid}${MBstr}_xr3d_dat.conc	$TR_vol $bpss_params -EM -F$fmtfile
if ($status) exit $status
4dfptoascii   ${patid}${MBstr}_xr3d_dat_bpss.conc $patid"_mov_regressors".dat
bandpass_4dfp $conc				$TR_vol $bpss_params -EM -F$fmtfile
set concrootb = ${concroot}_bpss
@ nframe = `wc ${patid}_mov_regressors.dat | awk '{print $1}'`

set concb = $concrootb.conc
#############################################################
# make the whole brain regressor including the 1st derivative
#############################################################
GSR:
qnt_4dfp -s -d -F$fmtfile $concb ../atlas/${patid1}_FSWB_on_${target:t}_333 \
	| awk '$1!~/#/{printf("%10.4f%10.4f\n", $2, $3)}' >! ${patid}_WB_regressor_dt.dat
@ n = `wc ${patid}_WB_regressor_dt.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo ${patid}_mov_regressors.dat ${patid}_WB_regressor_dt.dat length mismatch
	exit -1
endif

CSF:
if (! ${?CSF_excl_lim}) set CSF_excl_lim = 0.126
#################################
# make extra-axial CSF regressors
#################################
imgblur_4dfp ${patid1}_FSWB_on_${target:t}_333 6			# dilate FSWB mask using blur & threshold
if ($status) exit $status
maskimg_4dfp ${patid1}_FSWB_on_${target:t}_333_b60 ${patid1}_FSWB_on_${target:t}_333_b60 -t$CSF_excl_lim -v1 temp$$0
if ($status) exit $status
scale_4dfp temp$$0 -1 -b1 						# complement dilated FSWB mask
if ($status) exit $status
maskimg_4dfp temp$$0 $REFDIR/eyes_333z_not temp$$1			# exclude eyes from complement dilated FSWB mask
if ($status) exit $status
maskimg_4dfp temp$$1 ${concroot}_dfnd temp$$2				# exclude undefined voxels
if ($status) exit $status
zero_lt_4dfp $CSF_sd1t ${concroot}_sd1 temp$$3				# threshold sd1 image
if ($status) exit $status
maskimg_4dfp temp$$3 temp$$3 temp$$4 -v1				# binarize thresholded sd1 image
if ($status) exit $status
maskimg_4dfp temp$$2 temp$$4 ${patid1}_CSF_mask					# compute extra-axial CSF mask
if (1) /bin/rm temp$$[01234]*.4dfp.* ${patid1}_FSWB_on_${target:t}_333_b60*	# delete temporary images
	@ n = `echo $CSF_lcube | awk '{print int($1^3/2)}'`	# minimum cube defined voxel count is 1/2 total
	qntv_4dfp $concb ${patid1}_CSF_mask -F$fmtfile -l$CSF_lcube -t$CSF_svdt -n$n -D	-O4 -o${patid}_CSF_regressors.dat
if ($status == 254) then
	echo $program": "computing CSF regressors with minimum ROI size 1
	qntv_4dfp $concb ${patid1}_CSF_mask -F$fmtfile -l$CSF_lcube -t$CSF_svdt -n1  -D	-O4 -o${patid}_CSF_regressors.dat
	if ($status) then
		exit -1
	endif
endif
@ n = `wc ${patid}_CSF_regressors.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo ${patid}_mov_regressors.dat ${patid1}_CSF_regressors.dat length mismatch
	exit -1
endif

###########################
# make ventricle regressors
###########################
echo "" >! ${patid}_vent_regressors.dat		# in case vent regressors cannot be computed
set file = ../atlas/${patid1}_CS_erode_on_${target:t}_333_clus.4dfp.img.rec
@ hasvent = `cat $file | gawk '/^Final number of clusters/{print $NF}'`
if (! $hasvent) goto WM
maskimg_4dfp ../atlas/${patid1}_CS_erode_on_${target:t}_333_clus ${concroot}_dfnd ${patid}_vent_mask
set file = ${patid}_vent_regressors.dat
if ($status) exit $status
	@ n = `echo $CSF_lcube | awk '{print int($1^3/2)}'`	# minimum cube defined voxel count is 1/2 total
	qntv_4dfp $concb	${patid}_vent_mask -F$fmtfile -l$CSF_lcube -t$CSF_svdt -n$n -D -O4 -o$file
if ($status == 254) then
	echo $program": "computing ventricle regressors with vent_mask
	qnt_4dfp  $concb	${patid}_vent_mask -F$fmtfile | gawk '$1~/^Mean=/{print $NF}'     >! $file
	if ($status) then
		echo $program": "unable to compute ventricle regressors - moving on
		goto WM
	endif
endif
@ n = `wc ${patid}_vent_regressors.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo ${patid}_mov_regressors.dat ${patid}_vent_regressors.dat length mismatch
	exit -1
endif

WM:
####################
# make WM regressors
####################
maskimg_4dfp ../atlas/${patid1}_WM_erode_on_${target:t}_333_clus ${concroot}_dfnd ${patid}_WM_mask
if ($status) exit $status
@ n = `echo $WM_lcube | awk '{print int($1^3/2)}'`
	qntv_4dfp $concb ${patid}_WM_mask -F$fmtfile -l$WM_lcube -t$WM_svdt -n$n -O4 -D -o${patid}_WM_regressors.dat
if ($status) exit $status
@ n = `wc ${patid}_WM_regressors.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo ${patid}_mov_regressors.dat ${patid}_WM_regressors.dat length mismatch
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
		echo ${patid}_mov_regressors.dat $task_regressor length mismatch
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
set WM = ${patid}_WM_regressors.dat
if (${?noWM}) then
	if ($noWM) set WM = ""
endif
list_regressors.csh	$WB
list_regressors.csh	${patid}_mov_regressors.dat
list_regressors.csh	${patid}_CSF_regressors.dat
list_regressors.csh	${patid}_vent_regressors.dat
list_regressors.csh	$WM
list_regressors.csh	$task_regressor

paste ${patid}_mov_regressors.dat ${patid}_CSF_regressors.dat ${patid}_vent_regressors.dat \
				${patid}_WM_regressors.dat $task_regressor >! $$.dat
covariance $fmtfile $$.dat -D250 > /dev/null	# output file will be $$_SVD<dim>.dat
paste $WB $$_SVD*.dat >! ${patid}_nuisance_regressors.dat
/bin/rm $$.dat $$_SVD*.dat
list_regressors.csh	 ${patid}_nuisance_regressors.dat

if ($WM == "") then
	echo ${program}: no white matter regressor
else
	echo ${program}: including white matter regressor $WM
endif
if ($task_regressor == "") then
	echo ${program}: no task_regressor
else
	echo ${program}: including task_regressor $task_regressor
endif
if ($WB == "") then
	echo ${program}: no GSR
else
	echo ${program}: including global signal regressor "(with derivative)" $WB
endif
##########################################################################
# run glm_4dfp to remove nuisance regressors out of volumetric time series
##########################################################################
GLM:
glm_4dfp $fmtfile ${patid}_nuisance_regressors.dat	${concrootb}.conc -rresid -o
if ($status) exit $status
ifh2hdr -r-20to20					${concrootb}_coeff
var_4dfp -s -F$fmtfile					${concrootb}_resid.conc
if ($status) exit $status
ifh2hdr -r20						${concrootb}_resid_sd1
set sd1_WB1 = `qnt_4dfp ${concrootb}_resid_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`

echo $sd1_WB0 | awk '{printf("whole brain mean sd1 before fcMRI preprocessing             = %8.4f\n",$1)}'
echo $sd1_WB1 | awk '{printf("whole brain mean sd1 after bandpass and nuisance regression = %8.4f\n",$1)}'

if ($blur != 0) then
	set blurstr = `echo $blur | gawk '{printf("_g%d", int(10.0*$1 + 0.5))}'`	# logic in gauss_4dfp.c
	gauss_4dfp ${concrootb}_resid.conc $blur
	if ($status) exit $status
	var_4dfp -s -F$fmtfile		${concrootb}_resid${blurstr}.conc
	if ($status) exit $status
	ifh2hdr -r20			${concrootb}_resid${blurstr}_sd1
	set sd1_WB2 = `qnt_4dfp		${concrootb}_resid${blurstr}_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`
echo $sd1_WB2 | awk '{printf("whole brain mean sd1 after spatial blur                     = %8.4f\n",$1)}'
endif

popd					# out of $FCdir
exit
