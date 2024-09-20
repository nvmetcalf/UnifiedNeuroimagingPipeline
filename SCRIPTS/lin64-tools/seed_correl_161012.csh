#!/bin/csh -f
##############################################
# single-subject multi-ROI correlation mapping
##############################################
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/seed_correl_161012.csh,v 1.2 2020/10/01 00:33:29 avi Exp $
#$Log: seed_correl_161012.csh,v $
# Revision 1.2  2020/10/01  00:33:29  avi
# correct bug in concroot finder foreach
#
# Revision 1.1  2020/07/31  04:16:31  avi
# Initial revision
#
# Revision 1.12  2018/08/17  05:52:21  avi
# invoke with -f
#
# Revision 1.11  2016/12/28  04:36:13  avi
# restore use of either ${concroot}_dfnd or ${concroot}_uout_dfnd for backward compatibility
#
# Revision 1.10  2016/10/14  00:22:58  avi
# correct dumb typo
#
# Revision 1.9  2016/10/12  20:18:47  avi
# invoke covariance using $fmtfile
# optional use params-specified $fmtfile
#
# Revision 1.8  2016/04/21  00:55:50  avi
# remove option -V from qntm_4dfp call
#
# Revision 1.7  2016/03/10  00:19:01  avi
# add $concroot and $blurstr
#
# Revision 1.6  2015/02/16  00:24:12  avi
# better usage
#
# Revision 1.5  2015/02/15  22:24:31  avi
# append option -a idstr to seed regressor data filename
#
# Revision 1.4  2015/02/15  04:48:31  avi
# make compatible with $conc defined in params
#
# Revision 1.3  2014/08/09  02:21:17  avi
# option -a
#
# Revision 1.2  2014/07/15  02:34:34  avi
# use either ${patid}_faln_dbnd_xr3d_uwrp_atl_dfnd or ${patid}_faln_dbnd_xr3d_uwrp_atl_uout_dfnd in final maskimg_4dfp step
#
# Revision 1.1  2014/02/21  07:11:10  avi
# Initial revision
#

set program = $0
set program = $program:t
set rcsid = '$Id: seed_correl_161012.csh,v 1.2 2020/10/01 00:33:29 avi Exp $'
echo $rcsid

if (${#argv} < 1) then
	echo "Usage:	$program <parameters file> [instructions] [options]"
	echo "e.g.,	$program VB16168.params"
	echo "	options"
	echo "	-noblur	analyze unblurred version of preprocessed data"
	echo "	-A	use _func_vols.format in atlas directory"
	echo "	-P	use format string defined in either params or instructions"
	echo "N.B.:	default format is _xr3d_uwrp_atl.format in FCdir"
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

@ useblur = 1
@ A_flag = 0
@ P_flag = 0
foreach swi ($argv[3-])
	switch ($swi)
		case -noblur:
			@ useblur = 0
			breaksw;
		case -A:
			@ A_flag++
			breaksw;
		case -P:
			@ P_flag++
			breaksw;
	endsw
end
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

echo "FCdir 	= $FCdir"
echo "patid 	= $patid"
echo "skip	= $skip"
echo "ROIdir	= $ROIdir"; 		if ($status) exit $status

#####################################
# identify state of preprocessed data
#####################################
if (! ${?blur}) set blur = 0
if (! ${?bpss_params}) set bpss_params = ""
@ bpss = ${#bpss_params}	# run bandpass_4dfp flag

###########
# ROI image
###########
if (${?ROIimg}) then
	set ROIsrc = $ROIdir/$ROIimg
	if ($ROIsrc:e == "img")  set ROIsrc = $ROIsrc:r
	if ($ROIsrc:e == "4dfp") set ROIsrc = $ROIsrc:r
	@ nROI = `awk '/matrix size \[4\]/{print $NF}' $ROIsrc.4dfp.ifh`
else
	if (${?ROIlistfile}) then
		@ nROI = `wc $ROIlistfile | awk '{print $1}'`
	else
		echo "ROIlist = $ROIlist"; 	if ($status) exit $status
		@ nROI = ${#ROIlist}
	endif
	set ROIs = $cwd/$$ROIs.lst; if (-e $ROIs) /bin/rm $ROIs; touch $ROIs
	@ k = 1
	while ($k <= $nROI)
		if (${?ROIlistfile}) then
			set ROI = `head -$k $ROIlistfile | tail -1`
			echo $ROIdir/$ROI		>> $ROIs
		else
			echo $ROIdir/$ROIlist[$k]	>> $ROIs
		endif
		@ k++
	end
	paste_4dfp -ap1 $ROIs $$ROIs
	if ($status) exit $status
	set ROIsrc = $cwd/$$ROIs
endif

pushd $FCdir		# into $FCdir
if ($status) exit $status

##################################
# identify fcMRI preprocessed conc
##################################
if (! ${?conc}) then
	foreach MBstr ("" _faln _faln_dbnd) 
		if (-e ${patid}${MBstr}_xr3d_uwrp_atl.conc) set conc = ${patid}${MBstr}_xr3d_uwrp_atl.conc
	end	
endif					# conc specified in params
if (! -e $conc) then
	echo $program error: $conc not found
	exit -1
endif
set concroot = $conc:r

######################
# identify format file
######################
if (${?format} && $P_flag) then
	echo $format   >! $concroot.format
	set fmtfile     = $concroot.format
endif
if (! ${?fmtfile}) then
	if ($A_flag) then
		set fmtfile = ../atlas/${patid}_func_vols.format
	else
		set fmtfile = $concroot.format
	endif
endif
if (! -e $fmtfile) then
	echo $fmtfile not found
	exit -1
endif

##########################################
# determine seed correlation conc filename
##########################################
if ($bpss) then
	set concrootb = ${concroot}_bpss
else
	set concrootb = ${concroot}_uout
endif
if ($blur == 0 || $useblur == 0) then
	set blurstr = ""
else
	set blurstr = `echo $blur | gawk '{printf("_g%d", int(10.0*$1 + 0.5))}'`		# logic in gauss_4dfp.c
endif
set residroot	= ${concrootb}_resid${blurstr}
set resid	= $residroot.conc

set lst	= ${patid}_seed_regressors.dat
set rec	= ${patid}_seed_regressors.rec; if (-e $rec) /bin/rm $rec;
#####
# rec
#####
if (${?ROIimg}) then
	ln -s $ROIsrc.4dfp.img.rec $rec
else
	touch $rec
	@ k = 1
	while ($k <= $nROI)
		set region = `head -$k $ROIs | tail -1`
		if ($region:e == "img")  set region = $region:r
		if ($region:e == "4dfp") set region = $region:r
		echo Volume $k"	"$region >> $rec
		@ k++
	end
endif

###########
# qntm_4dfp
###########
qntm_4dfp $resid $ROIsrc -o$lst
if ($status) exit $status

###########################################################
# compute total correlations and update _tcorr.4dfp.img.rec
###########################################################
glm_4dfp $fmtfile $lst $resid -t
if ($status) exit $status
set l = `wc -l	${residroot}_tcorr.4dfp.img.rec | awk '{print $1}'`
@ l--
head -$l	${residroot}_tcorr.4dfp.img.rec	>! $$.rec
cat $rec					>> $$.rec
tail -1		${residroot}_tcorr.4dfp.img.rec	>> $$.rec
/bin/mv $$.rec	${residroot}_tcorr.4dfp.img.rec

##############################
# mask tcorr by defined voxels
##############################
if (-e ${concroot}_dfnd.4dfp.img) then
	set dfnd = ${concroot}_dfnd
else if (-e ${concroot}_uout_dfnd.4dfp.img) then
	set dfnd = ${concroot}_uout_dfnd
else
	echo ${concroot}"*"dfnd not found
	eist -1
endif
maskimg_4dfp	${residroot}_tcorr $dfnd -1 ${residroot}_tcorr_dfnd
if ($status) exit $status
ifh2hdr -r-1to1	${residroot}_tcorr_dfnd

######################################
# Fisher z transform total correlation
######################################
rho2z_4dfp	${residroot}_tcorr_dfnd
if ($status) exit $status
ifh2hdr -r-1to1	${residroot}_tcorr_dfnd_zfrm

#############################################
# compute zero-lag ROI-ROI correlation matrix
#############################################
covariance -uom0 $fmtfile $lst 
if ($status) exit $status
/bin/rm ${lst:r}_ROI*_CCR.dat

popd			# out of $FCdir
##########
# clean up
##########
if (! ${?ROIimg}) /bin/rm $$ROIs*
echo "status="$status
exit
