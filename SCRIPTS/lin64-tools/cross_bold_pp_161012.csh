#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/cross_bold_pp_161012.csh,v 1.22 2021/03/29 04:59:04 avi Exp $
#$Log: cross_bold_pp_161012.csh,v $
# Revision 1.22  2021/03/29  04:59:04  avi
# unset echo
#
# Revision 1.21  2021/03/29  04:53:43  avi
# prevent exit on call to niftigz_4dfp -n if ${base}_BF.nii.gz exists
#
# Revision 1.20  2020/10/16  22:36:12  tanenbauma
# Prevent deletion of raw image if $E4dfp == 1
#
# Revision 1.19  2020/07/31  21:51:34  avi
# remove superfluous endif
#
# Revision 1.18  2020/07/31  00:57:16  avi
# nifti_4dfp -4 -> nifitgz_4dfp -4
#
# Revision 1.17  2020/07/24  21:29:17  avi
# usedcm2niix option
# dbnd_flag control depending on interleave status to accommodate MB sequences
#
# Revision 1.15  2019/08/09  21:56:09  avi
# correct typo in setting norm_cmd
#
# Revision 1.14  2018/10/25  06:27:39  avi
# variable $csh_norm controls mode1000_4dfp vs. original normalize_4dfp
#
# Revision 1.13  2018/08/17  05:36:58  avi
# invoke with -f
#
# Revision 1.12  2018/04/11  22:37:59  avi
# -seqstr
#
# Revision 1.11  2017/12/26  23:45:33  avi
# trap sefm_pp_AZS.csh errors
#
# Revision 1.10  2017/07/08  04:33:25  avi
# extensive revision to accommodate field map correction using sefm
#
# Revision 1.9  2017/06/14  05:37:33  avi
# initialize  ${patid}${MBstr}_xr3d.lst for appending
#
# Revision 1.8  2017/04/26  01:16:25  avi
# correct anat_ave creation bug
#
# Revision 1.7  2017/03/22  22:14:07  avi
# extensive new code to implement bias field correction ($BiasField != 0)
#
# Revision 1.6  2016/11/07  01:49:44  avi
# correct bug that would emerge with axial MP-RAGE data
#
# Revision 1.5  2016/11/01  00:26:31  avi
# bring FD logic into liine with fcMRI_preproc_161012.csh logic
# lomotil logic
#
# Revision 1.4  2016/10/25  21:32:46  avi
# correct $day1_path bug
#
# Revision 1.3  2016/10/25  00:18:04  avi
# modified FD logic
#
# Revision 1.2  2016/10/17  23:57:23  avi
# correct several minor errors
#
# Revision 1.1  2016/10/12  20:10:54  avi
# Initial revision
#
# Revision 1.14  2016/08/12  00:06:04  avi
# perform dcm2nii if measured field mapping studies are listed in $gre()
#
# Revision 1.13  2016/06/12  02:28:39  avi
# use $fmtfile instead of $format in all calls to actmapf_4dfp, var_4dfp, and format2lst
#
# Revision 1.12  2016/06/01  00:38:29  avi
# new params variable $MBfac
#
# Revision 1.11  2016/05/16  22:59:29  avi
# correct typo
#
# Revision 1.10  2016/05/16  21:40:09  avi
# prevent accumulation over repeat script invocations of format specification for func_vols_ave
#
# Revision 1.9  2015/06/08  05:31:30  avi
# accommodate not defining $anat_avet in params
#
# Revision 1.8  2014/07/15  02:20:27  avi
# cross-day fucntional in cases with t2w data
#
# Revision 1.7  2014/07/11  01:01:53  avi
# smoother Et2w logic
#
# Revision 1.6  2014/03/12  22:29:20  avi
# code working for measured field maps
#
# Revision 1.5  2014/02/22  07:40:34  avi
# $min_frames instead of hard coded 240
#
# Revision 1.4  2014/02/21  07:00:51  avi
# correct minor bug in computation of ${patid}_func_vols
#
# Revision 1.3  2014/02/21  04:39:14  avi
# handle cross-day data (but t2w must be in current atlas directory)
#
# Revision 1.2  2013/11/08  06:23:59  avi
# optional pre-blur (parameter $anat_aveb) on func_vols run_dvar_4dfp
#
# Revision 1.1  2013/11/08  05:38:02  avi
# Initial revision
#

# set echo
set idstr = '$Id: cross_bold_pp_161012.csh,v 1.22 2021/03/29 04:59:04 avi Exp $'
echo $idstr
set program = $0; set program = $program:t
echo $program $argv[1-]

if (${#argv} < 1) then
	echo "usage:	"$program" params_file [instructions_file]"
	exit 1
endif
set prmfile = $1
echo "prmfile="$prmfile

if (! -e $prmfile) then
	echo $program": "$prmfile not found
	exit -1
endif
source $prmfile
set instructions = ""
if (${#argv} > 1) then
	set instructions = $2
	if (! -e $instructions) then
		echo $program": "$instructions not found
		exit -1
	endif
	cat $instructions
	source $instructions
endif

##########
# check OS
##########
set OS = `uname -s`
if ($OS != "Linux") then
	echo $program must be run on a linux machine
	exit -1
endif

if ($target:h != $target) then
	set tarstr = -T$target
else
	set tarstr = $target
endif

@ runs = ${#irun}
if ($runs != ${#fstd}) then
	echo "irun fstd mismatch - edit "$prmfile
	exit -1
endif

if (! ${?scrdir}) set scrdir = ""
@ usescr = `echo $scrdir | awk '{print length ($1)}'`
if ($usescr) then 
	if (! -e $scrdir) mkdir $scrdir
	if ($status) exit $status
endif
set sourcedir = $cwd
if (! ${?sorted}) @ sorted = 0



if ( ! $?usedcm2niix ) set usedcm2niix = 0

set squeezestr = ""
if (${?sx}) then
	set squeezestr = $squeezestr" -sx"$sx
endif
if (${?sy}) then
	set squeezestr = $squeezestr" -sy"$sy
endif

if (! ${?E4dfp}) @ E4dfp = 0
if (${E4dfp}) then
	echo "4dfp files have been pre-generated. Option E4dfp set with value $E4dfp. Skipping dcm_to_4dfp"
endif

if (! ${?use_anat_ave}) @ use_anat_ave = 0
if ($use_anat_ave) then
	set epi_anat = $patid"_anat_ave"
else
	set epi_anat = $patid"_func_vols_ave"
endif
if (! ${?min_frames}) @ min_frames = 240
if (! ${?day1_patid}) set day1_patid = "";
if ($day1_patid != "") then
	set patid1	= $day1_patid
	set day1_path	= `echo $day1_path | sed 's|/$||g'`
else
	set patid1	= $patid
endif

if (${?goto_UNWARP}) goto UNWARP

date
###################
# process BOLD data
###################
if (${?epi_zflip}) then
	if ($epi_zflip) set zflip = "-z"
else
	set zflip = ""
endif

###################################
# set up slice timing and debanding
###################################
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
	if ( ${?seqstr} ) then
		set STR = "-seqstr "$seqstr;
	else
		set STR = ""
	endif 

	if ($dbnd_flag) then
		set MBstr = _faln_dbnd
	else
		set MBstr = _faln
	endif
else 
	set MBstr = ""
endif

@ err = 0
@ k = 1
while ($k <= $runs)
	if (! $E4dfp) then
		if ($usescr) then		# test to see if user requested use of scratch disk
			if (-e bold$irun[$k]) /bin/rm bold$irun[$k]	# remove existing link
			if (! -d $scrdir/bold$irun[$k]) mkdir $scrdir/bold$irun[$k]
			ln -s $scrdir/bold$irun[$k] bold$irun[$k]
		else
			if (! -d bold$irun[$k]) mkdir bold$irun[$k]
		endif
	endif
	pushd bold$irun[$k]
	set y = $patid"_b"$irun[$k]${MBstr}
	if (-e $y.4dfp.img && -e $y.4dfp.ifh) goto POP
	if (! $E4dfp) then
		if ( ! $usedcm2niix ) then
			if ($sorted) then
				echo		dcm_to_4dfp -q -b study$fstd[$k] $inpath/study$fstd[$k]
				if ($go)	dcm_to_4dfp -q -b study$fstd[$k] $inpath/study$fstd[$k]
			else
				echo		dcm_to_4dfp -q -b study$fstd[$k] $inpath/$dcmroot.$fstd[$k]."*"
				if ($go)	dcm_to_4dfp -q -b study$fstd[$k] $inpath/$dcmroot.$fstd[$k].*
			endif
		else
			dcm2niix -o . -f study$fstd[$k] $inpath/study$fstd[$k] || exit -1
			niftigz_4dfp -4  study$fstd[$k] $patid"_b"$irun[$k] -N || exit -1
			/bin/rm study$fstd[$k].*
		endif 
	endif
	if (! ${?nounpack} && ! $usedcm2niix) then 
		echo		unpack_4dfp -V study$fstd[$k] $patid"_b"$irun[$k] -nx$nx -ny$ny $squeezestr $zflip
		if ($go)	unpack_4dfp -V study$fstd[$k] $patid"_b"$irun[$k] -nx$nx -ny$ny $squeezestr $zflip
		if ($status) then
			@ err++
			/bin/rm $patid"_b"$irun[$k]*
			goto POP
		endif
		echo		/bin/rm  study$fstd[$k]."*"
		if ($go)	/bin/rm  study$fstd[$k].*
	endif 
	if (! $MB) then 
		echo		frame_align_4dfp $patid"_b"$irun[$k] $skip -TR_vol $TR_vol -TR_slc $TR_slc -d $epidir $interleave -m $MBfac $STR
		if ($go)	frame_align_4dfp $patid"_b"$irun[$k] $skip -TR_vol $TR_vol -TR_slc $TR_slc -d $epidir $interleave -m $MBfac $STR
		if ($dbnd_flag) then
			echo		deband_4dfp -n$skip $patid"_b"$irun[$k]"_faln"
			if ($go)	deband_4dfp -n$skip $patid"_b"$irun[$k]"_faln"
			if ($status)	exit $status
			if ($economy > 3) then
				echo		/bin/rm $patid"_b"$irun[$k]"_faln".4dfp."*"
				if ($go)	/bin/rm $patid"_b"$irun[$k]"_faln".4dfp.*
			endif
		endif
		if ($economy > 2 && ! $E4dfp) then
			echo		/bin/rm $patid"_b"$irun[$k].4dfp."*"
			if ($go)	/bin/rm $patid"_b"$irun[$k].4dfp.*
		endif
	endif
	
POP:
	popd	# out of bold$irun[$k]
	@ k++
end
if ($err) then
	echo $program": one or more BOLD runs failed preliminary processing"
	exit -1
endif
if ($epi2atl == 2) goto ATL

if (-e  $patid"_xr3d".lst)	/bin/rm $patid"_xr3d".lst;	touch $patid"_xr3d".lst
@ k = 1
while ($k <= $runs)
	echo bold$irun[$k]/$patid"_b"$irun[$k]${MBstr} >>	$patid"_xr3d".lst
	@ k++
end

echo cat	$patid"_xr3d".lst
cat		$patid"_xr3d".lst
echo		cross_realign3d_4dfp -n$skip -qv$normode -l$patid"_xr3d".lst
if ($go)	cross_realign3d_4dfp -n$skip -qv$normode -l$patid"_xr3d".lst
if ($status)	exit $status

##############################################
# bias field correct (if no prescan normalize)
##############################################
if (! $?BiasField)  @ BiasField = 0;
if ($BiasField) then
# create average across all runs	
	if (-e ${patid}${MBstr}_xr3d.lst) /bin/rm ${patid}${MBstr}_xr3d.lst
	touch ${patid}${MBstr}_xr3d.lst
	@ k = 1
	while ($k <= $runs)
		echo bold$irun[$k]/$patid"_b"$irun[$k]${MBstr}_xr3d >> ${patid}${MBstr}_xr3d.lst
		@ k++
	end
	conc_4dfp  ${patid}${MBstr}_xr3d -l${patid}${MBstr}_xr3d.lst
	set  format = `conc2format ${patid}${MBstr}_xr3d.conc $skip`	
	actmapf_4dfp $format ${patid}${MBstr}_xr3d.conc -aavg
	if ($status) exit $status
	set base = ${patid}${MBstr}_xr3d_avg
	nifti_4dfp -n ${base} ${base}
	if ($status) exit $status
	$FSLDIR/bin/bet ${base} ${base}_brain -f 0.3
	if ($status) exit $status
# compute bias field within brain mask
	$FSLDIR/bin/fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -B -o ${base}_brain ${base}_brain
	if ($status) exit $status
	niftigz_4dfp -4 ${base}_brain_restore ${base}_brain_restore
	if ($status) exit $status
# compute extended bias field
	extend_fast_4dfp -G ${base} ${base}_brain_restore ${base}_BF
	if ($status) exit $status
	if (! -e ${base}_BF.nii.gz) niftigz_4dfp -n ${base}_BF ${base}_BF
	if ($status) exit $status
	@ k = 1
	while ($k <= $runs)
		pushd bold$irun[$k]
##################################
# bias field correct the whole run
##################################
		imgopr_4dfp -p$patid"_b"$irun[$k]${MBstr}_xr3d_BC $patid"_b"$irun[$k]${MBstr}_xr3d ../${base}_BF 
		if ($status) exit $status
		/bin/rm -r   $patid"_b"$irun[$k]${MBstr}_xr3d.4dfp* 
		popd
		@ k++	
	end
	if ($status) exit $status
	set BC = "_BC"
else 
	set BC = ""
endif  

date
#################################
# compute mode 1000 normalization
#################################
if (! ${?csh_norm}) @ csh_norm = 0
if (${csh_norm}) then
	set norm_cmd = normalize_4dfp.csh;	# csh script using compiled executable mode1000_4dfp
else
	set norm_cmd = normalize_4dfp;		# original compiled executable
endif
@ k = 1
while ($k <= $runs)
	pushd bold$irun[$k]
	if ($BiasField) then 
		set format = `cat $patid"_b"$irun[$k]${MBstr}_xr3d_BC.4dfp.ifh | \
			gawk 'BEGIN{skip = 1} {if  (/\[4\]/) {f = $NF}} END{printf("%dx%d+",skip,f-skip)}' skip=$skip`
		actmapf_4dfp $format $patid"_b"$irun[$k]${MBstr}_xr3d_BC -aavg 
		if ($status) exit $status		
		echo 		$norm_cmd $patid"_b"$irun[$k]${MBstr}_xr3d_BC_avg -h
		if ($go)	$norm_cmd $patid"_b"$irun[$k]${MBstr}_xr3d_BC_avg -h
		if ($status) exit $status	
		if ($economy > 4 && $epi2atl == 0) /bin/rm $patid"_b"$irun[$k]${MBstr}_xr3d_BC_avg.4dfp."*"
	else 
		echo 		$norm_cmd $patid"_b"$irun[$k]${MBstr}"_r3d_avg" -h	
		if ($go)	$norm_cmd $patid"_b"$irun[$k]${MBstr}"_r3d_avg" -h
		if ($status) exit $status	
		if ($economy > 4 && $epi2atl == 0) /bin/rm $patid"_b"$irun[$k]${MBstr}"_r3d_avg".4dfp."*"
	endif
	popd	# out of bold$irun[$k]
	@ k++
end

date
###############################
# apply mode 1000 normalization
###############################
if (-e  $patid"_anat".lst) /bin/rm $patid"_anat".lst; touch $patid"_anat".lst
@ k = 1
while ($k <= $runs)
	pushd bold$irun[$k]
	if ($BiasField) then
		set file = $patid"_b"$irun[$k]${MBstr}_xr3d_BC_avg_norm.4dfp.img.rec
	else 
		set file = $patid"_b"$irun[$k]${MBstr}_r3d_avg_norm.4dfp.img.rec
	endif
	set f = 1.0; if (-e $file) set f = `head $file | awk '/original/{print 1000/$NF}'`
	echo		scale_4dfp $patid"_b"$irun[$k]${MBstr}_xr3d${BC} $f -anorm
	if ($go)	scale_4dfp $patid"_b"$irun[$k]${MBstr}_xr3d${BC} $f -anorm
	echo		/bin/rm $patid"_b"$irun[$k]${MBstr}_xr3d${BC}.4dfp."*"
	if ($go)	/bin/rm $patid"_b"$irun[$k]${MBstr}_xr3d${BC}.4dfp.*
	popd	# out of bold$irun[$k]
	echo bold$irun[$k]/$patid"_b"$irun[$k]${MBstr}_xr3d${BC}_norm >>	$patid"_anat".lst	
	if ($BiasField) /bin/rm $patid"_b"$irun[$k]${MBstr}_xr3d_BC_avg_norm.4dfp.*
	@ k++
end
/bin/cp $patid"_anat".lst $patid"_func_vols".lst

date
###################
# movement analysis
###################
if (! -d movement) mkdir movement
if (! ${?lomotil}) then
	set lstr = ""
else
	set lstr = "-l$lomotil TR_vol=$TR_vol"
endif
@ k = 1
while ($k <= $runs)
	echo		mat2dat bold$irun[$k]/"*_xr3d".mat -RD -n$skip $lstr
	if ($go)	mat2dat bold$irun[$k]/*"_xr3d".mat -RD -n$skip $lstr
	echo		/bin/mv bold$irun[$k]/"*_xr3d.*dat"	movement
	if ($go)	/bin/mv bold$irun[$k]/*"_xr3d".*dat	movement
	@ k++
end

date

if (! -d atlas) mkdir atlas
if ($BiasField) then
	/bin/mv ${base}_brain.* ${base}_brain_restore.* atlas/
endif
######################################
# make EPI first frame (anatomy) image
######################################
echo cat	$patid"_anat".lst
cat		$patid"_anat".lst
echo		paste_4dfp -p1 $patid"_anat".lst	$patid"_anat_ave"
if ($go)	paste_4dfp -p1 $patid"_anat".lst	$patid"_anat_ave"
echo		ifh2hdr	-r2000				$patid"_anat_ave"
if ($go)	ifh2hdr	-r2000				$patid"_anat_ave"
echo		/bin/mv $patid"_anat*" atlas
if ($go)	/bin/mv $patid"_anat"* atlas

#######################################
# make func_vols_ave using actmapf_4dfp
#######################################
echo	conc_4dfp ${patid}_func_vols -l${patid}_func_vols.lst
	conc_4dfp ${patid}_func_vols -l${patid}_func_vols.lst
if ($status) exit $status
cat			${patid}_func_vols.conc
echo		/bin/mv	${patid}_func_vols."*" atlas
if ($go)	/bin/mv	${patid}_func_vols.*   atlas

pushd movement
if (-e ${patid}${MBstr}"_xr3d".FD) /bin/rm	${patid}${MBstr}"_xr3d".FD
touch						${patid}${MBstr}"_xr3d".FD
@ k = 1
while ($k <= $runs)
	gawk -f $RELEASE/FD.awk $patid"_b"$irun[$k]${MBstr}"_xr3d".ddat >> ${patid}${MBstr}"_xr3d".FD
	@ k++
end
if ($?FDthresh) then 
	if (! $?FDtype) set FDtype = 1
	conc2format ../atlas/${patid}_func_vols.conc $skip | xargs format2lst > $$.format0
	gawk '{c="+";if ($'$FDtype' > crit)c="x"; printf ("%s\n",c)}' crit=$FDthresh ${patid}${MBstr}"_xr3d".FD > $$.format1
	paste $$.format0 $$.format1 | awk '{if($1=="x")$2="x";printf("%s",$2)}' > ${patid}${MBstr}"_xr3d".FD.format
	/bin/rm $$.format0 $$.format1
	/bin/mv ${patid}${MBstr}"_xr3d".FD.format ../atlas/
endif 
popd	

pushd atlas		# into atlas
if (! ${?anat_aveb}) set anat_aveb = 0.
if (! ${?anat_avet}) then			# set anat_avet excessively high if you wish not to use DVARS as a frame censoring technique 
	set xstr = ""				# compute threshold using find_dvar_crit.awk
else
	set xstr = -x$anat_avet
endif
set  format = `conc2format ${patid}_func_vols.conc $skip`	
echo $format >! ${patid}_func_vols.format	
echo	actmapf_4dfp ${patid}_func_vols.format ${patid}_func_vols.conc -aave_tmp
	actmapf_4dfp ${patid}_func_vols.format ${patid}_func_vols.conc -aave_tmp
if ($status) exit $status
nifti_4dfp -n ${patid}_func_vols_ave_tmp ${patid}_func_vols_ave_tmp
$FSLDIR/bin/bet ${patid}_func_vols_ave_tmp.nii ${patid}_func_vols_ave_tmp_msk -f 0.3
if ($status) exit $status
niftigz_4dfp -4  ${patid}_func_vols_ave_tmp_msk.nii.gz  ${patid}_func_vols_ave_tmp_msk
echo	run_dvar_4dfp ${patid}_func_vols.conc -m${patid}_func_vols_ave_tmp_msk -n$skip $xstr -b$anat_aveb
	run_dvar_4dfp ${patid}_func_vols.conc -m${patid}_func_vols_ave_tmp_msk -n$skip $xstr -b$anat_aveb
if ($status) exit $status	
rm  ${patid}_func_vols_ave_tmp*
if ($?FDthresh) then 
	format2lst ${patid}_func_vols.format > $$.format1
	format2lst ${patid}${MBstr}"_xr3d".FD.format > $$.format2
	paste $$.format1 $$.format2 | gawk '{if($1=="x")$2="x";printf("%s",$2);}' | xargs condense  > ${patid}_func_vols.format
	rm $$.format1 $$.format2
endif

set str = `format2lst -e ${patid}_func_vols.format | gawk '{k=0;l=length($1);for(i=1;i<=l;i++)if(substr($1,i,1)=="x")k++;}END{print k, l;}'`
echo "$str[1] out of $str[2] frames fails user's frame rejection criterion"
@ j = $str[2] - $str[1]; if ($j < $min_frames) exit 1	# require at least $min_frames below FD and/or dvar threshold to proceed

actmapf_4dfp ${patid}_func_vols.format ${patid}_func_vols.conc -aave
if ($status) exit $status

if ($day1_patid != "") then
##########################################
# compute cross-day $epi_anat registration
##########################################
	set stretch_flag = ""
	if (! ${?cross_day_nostretch}) @ cross_day_nostretch = 0;
	if ($cross_day_nostretch) set stretch_flag = -nostretch
	if ($use_anat_ave) then
		set trailer = anat_ave
	else
		set trailer = func_vols_ave
	endif
	echo		cross_day_imgreg_4dfp $patid $day1_path $day1_patid $tarstr $stretch_flag -a$trailer
	if ($go)	cross_day_imgreg_4dfp $patid $day1_path $day1_patid $tarstr $stretch_flag -a$trailer
	if ($status) exit $status
	if ($trailer != anat_ave) then
		/bin/rm -f						${patid}_anat_ave_to_${target:t}_t4 
		ln -s $cwd/${patid}_func_vols_ave_to_${target:t}_t4	${patid}_anat_ave_to_${target:t}_t4
	endif
	@ Et2w = 0
	if (-e $day1_path/$patid1"_t2wT".4dfp.img) then
		set t2w = $patid1"_t2wT"
		@ Et2w = 1
	else if (-e $day1_path/$patid1"_t2w".4dfp.img) then
		set t2w = $patid1"_t2w"
		@ Et2w = 1
	endif 
	if (-e $day1_path/$patid1"_mpr1T".4dfp.img) then 
		set mpr = $patid1"_mpr1T"
	else if ( -e $day1_path/$patid1"_mpr1".4dfp.img) then
		set mpr = $patid1"_mpr1"
	else 
		echo "no structual image in day1_path"
		exit -1
	endif
	if ($day1_path != $cwd) then
		/bin/cp -t . \
			$day1_path/${day1_patid}_${trailer}_to_*_t4 \
			$day1_path/${mpr}.4dfp.* \
			$day1_path/${mpr}_to_${target:t}_t4 
		if ($status) exit $status
	endif
	if ($Et2w) then
		echo "t2w="$t2w
		if ($day1_path != $cwd) then
			/bin/cp $day1_path/${t2w}.4dfp.* $day1_path/${t2w}_to_${target:t}_t4 .
			if ($status) exit $status
		endif
		t4_mul ${epi_anat}_to_${day1_patid}_${trailer}_t4 ${day1_patid}_${trailer}_to_${t2w}_t4 ${epi_anat}_to_${t2w}_t4
		if ($status) exit $status
		t4_mul ${epi_anat}_to_${t2w}_t4 ${t2w}_to_${target:t}_t4
		if ($status) exit $status
	else
		t4_mul ${epi_anat}_to_${day1_patid}_${trailer}_t4 ${day1_patid}_${trailer}_to_${mpr}_t4 ${epi_anat}_to_${mpr}_t4
		if ($status) exit $status
		if ( $day1_path != $cwd  && (! ${?gre} && ! ${?FMmag}) && $?FMmean && $?FMbases ) then 
			/bin/cp -t . \
				$day1_path/${patid1}_aparc+aseg_on_${target:t}_333.4dfp.* \
				$day1_path/${patid1}_FSWB_on_${target:t}_333.4dfp.* \
				$day1_path/${patid1}_CS_erode_on_${target:t}_333_clus.4dfp.* \
				$day1_path/${patid1}_WM_erode_on_${target:t}_333_clus.4dfp.* \
				$day1_path/${patid1}_aparc+aseg.4dfp.* \
				$day1_path/${patid1}_orig_to_${mpr}_t4
			if ($status) exit $status
		endif
	endif 
	goto EPI_to_ATL
endif
######################
# make MP-RAGE average
######################
@ nmpr = ${#mprs}
if ($nmpr < 1) exit 0
set mprave = $patid"_mpr_n"$nmpr
set mprlst = ()
@ k = 1
while ($k <= $nmpr)
	if (! $E4dfp) then
		if ( ! $usedcm2niix ) then 
			if ($sorted) then
				echo		dcm_to_4dfp -b $patid"_mpr"$k $inpath/study$mprs[$k]
				if ($go)	dcm_to_4dfp -b $patid"_mpr"$k $inpath/study$mprs[$k]
			else
				echo		dcm_to_4dfp -b $patid"_mpr"$k $inpath/$dcmroot.$mprs[$k]."*"
				if ($go)	dcm_to_4dfp -b $patid"_mpr"$k $inpath/$dcmroot.$mprs[$k].*
			endif
			if ($status) exit $status
		else
			dcm2niix -o . -f $patid"_mpr"$k -w 1 $inpath/study$mprs[$k] || exit -1
			niftigz_4dfp -4  $patid"_mpr"$k $patid"_mpr"$k -N || exit -1
			rm $patid"_mpr"$k.nii
		endif 
	endif
	set mprlst = ($mprlst $patid"_mpr"$k)
	@ k++
end

date
#########################
# compute atlas transform
#########################
if (! ${?tse}) 	set tse = ()
if (! ${?t1w})	set t1w = ()
if (! ${?pdt2})	set pdt2 = ()
if (! ${?Gad})	set Gad = 0;		# Gadolinium contrast given: @ Gad = 1

if ($#tse == 0 && ! ${?FMmag} && ! ${?gre}) then
	set mprlstT = ()
		foreach mpr ($mprlst)  
		@ ori = `awk '/orientation/{print $NF}' ${mpr}.4dfp.ifh`
		switch ($ori)
		case 2:
					set mprlstT = ($mprlstT ${mpr});  breaksw;
		case 3:
			C2T_4dfp $mpr;	set mprlstT = ($mprlstT ${mpr}T); breaksw;
		case 4:
			S2T_4dfp $mpr;	set mprlstT = ($mprlstT ${mpr}T); breaksw;
		default:
			echo $program": illegal "$mpr" orientation"; exit -1; breaksw;
		endsw
	end
	set mprlst = ($mprlstT)
endif 

set mpr = $mprlst[1]
if ($Gad) then
	mpr2atl1_4dfp $mpr $tarstr useold
	if ($status) exit $status
	set episcript = epi2t2w2mpr2atl3_4dfp;
else
	echo		avgmpr_4dfp $mprlst $mprave $tarstr useold
	if ($go)	avgmpr_4dfp $mprlst $mprave $tarstr useold
	if ($status) exit $status
	set episcript = epi2t2w2mpr2atl2_4dfp;
endif
foreach O (111 222 333)
	ifh2hdr -r1600 ${patid}_mpr_n${nmpr}_${O}_t88
end

@ ntse = ${#tse}
if (${#t1w}) then
	if (! $E4dfp) then
		if ( ! $usedcm2niix ) then 
			if ($sorted) then
				echo		dcm_to_4dfp -b $patid"_t1w" $inpath/study$t1w
				if ($go)	dcm_to_4dfp -b $patid"_t1w" $inpath/study$t1w
			else
				echo		dcm_to_4dfp -b $patid"_t1w" $inpath/$dcmroot.$t1w."*"
				if ($go) 	dcm_to_4dfp -b $patid"_t1w" $inpath/$dcmroot.$t1w.*
			endif
		else 
			dcm2niix -o . -f $patid"_t1w" -w 1 $inpath/study$t1w || exit -1
			niftigz_4dfp -4  $patid"_t1w" $patid"_t1w" -N || exit -1
			rm $patid"_t1w".nii
		endif 
	endif
	echo		t2w2mpr_4dfp $patid"_mpr1" $patid"_t1w" $tarstr
	if ($go)	t2w2mpr_4dfp $patid"_mpr1" $patid"_t1w" $tarstr
	if ($status) exit $status

	echo		epi2t1w_4dfp ${epi_anat} $patid"_t1w" $tarstr
	if ($go)	epi2t1w_4dfp ${epi_anat} $patid"_t1w" $tarstr
	if ($status) exit $status

	echo		t4_mul ${epi_anat}_to_$patid"_t1w_t4" $patid"_t1w_to_"$target:t"_t4"
	if ($go)	t4_mul ${epi_anat}_to_$patid"_t1w_t4" $patid"_t1w_to_"$target:t"_t4"
else if ($ntse) then
	set tselst = ()
	@ k = 1
	while ($k <= $ntse)
		set filenam = $patid"_t2w"
		if ($ntse > 1) set filenam = $filenam$k
		if (! $E4dfp) then
			if ( ! $usedcm2niix ) then 
				if ($sorted) then
					echo		dcm_to_4dfp -b $filenam $inpath/study$tse[$k]
					if ($go)	dcm_to_4dfp -b $filenam $inpath/study$tse[$k]
				else
					echo		dcm_to_4dfp -b $filenam $inpath/$dcmroot.$tse[$k]."*"
					if ($go) 	dcm_to_4dfp -b $filenam $inpath/$dcmroot.$tse[$k].*
				endif
				if ($status) exit $status
			else 
				dcm2niix -o . -f $filenam -w 1 $inpath/study$tse[$k] || exit -1
				niftigz_4dfp -4  $filenam $filenam -N || exit -1
				rm $filenam.nii
			endif 
		endif
		set tselst = ($tselst $filenam)
		@ k++
	end
	if ($ntse  > 1) then
		echo		collate_slice_4dfp $tselst $patid"_t2w"
		if ($go)	collate_slice_4dfp $tselst $patid"_t2w"
	endif
else if (${#pdt2}) then
	if (! $E4dfp) then
		if ( ! $usedcm2niix ) then 
			if ($sorted) then
				echo		dcm_to_4dfp -b $patid"_pdt2" $inpath/study$pdt2
				if ($go)	dcm_to_4dfp -b $patid"_pdt2" $inpath/study$pdt2
			else
				echo		dcm_to_4dfp -b $patid"_pdt2" $inpath/$dcmroot.$pdt2."*"
				if ($go) 	dcm_to_4dfp -b $patid"_pdt2" $inpath/$dcmroot.$pdt2.*
			endif
			if ($status) exit $status
		else
			dcm2niix -o . -f $patid"_pdt2" -w 1 $inpath/study$pdt2 || exit -1
			niftigz_4dfp -4  $patid"_pdt2" $patid"_pdt2" -N || exit -1
			rm $patid"_pdt2".nii
		endif
	endif
	echo		extract_frame_4dfp $patid"_pdt2" 2 -o$patid"_t2w"
	if ($go)	extract_frame_4dfp $patid"_pdt2" 2 -o$patid"_t2w"
	if ($status) exit $status
endif

@ Et2w = (-e $patid"_t2w".4dfp.img && -e $patid"_t2w".4dfp.ifh)
if ($Et2w) then
#################################################
# if unwarp is needed make sure t2w is transverse
#################################################
	set t2w = $patid"_t2w"
	@ ori = `awk '/orientation/{print $NF}' $patid"_t2w".4dfp.ifh`
	switch ($ori)
	case 2:
		breaksw;
	case 3:
		C2T_4dfp $patid"_t2w"; set t2w = $patid"_t2wT"; breaksw;
	case 4:
		S2T_4dfp $patid"_t2w"; set t2w = $patid"_t2wT"; breaksw;
	default:
		echo $program": illegal $patid"_t2w" orientation"; exit -1; breaksw;
	endsw
	echo		$episcript ${epi_anat} $t2w $patid"_mpr1" useold $tarstr
	if ($go)	$episcript ${epi_anat} $t2w $patid"_mpr1" useold $tarstr
else
	echo		epi2mpr2atl2_4dfp ${epi_anat} $mpr useold $tarstr
	if ($go)	epi2mpr2atl2_4dfp ${epi_anat} $mpr useold $tarstr
endif
if ($status) exit $status

EPI_to_ATL:
if (! $use_anat_ave && $day1_patid == "") then
	/bin/rm ${patid}_anat_ave_to_${target:t}_t4
	ln -s ${patid}_func_vols_ave_to_${target:t}_t4 ${patid}_anat_ave_to_${target:t}_t4
endif

########################################################################
# make atlas transformed epi_anat and t2w in 111 222 and 333 atlas space
########################################################################
set t4file = ${patid}_anat_ave_to_${target:t}_t4
foreach O (111 222 333)
	echo		t4img_4dfp $t4file  ${epi_anat}	${epi_anat}_on_${target:t}_$O -O$O
	if ($go)	t4img_4dfp $t4file  ${epi_anat}	${epi_anat}_on_${target:t}_$O -O$O
	echo		ifh2hdr	 -r2000			${epi_anat}_on_${target:t}_$O
	if ($go)	ifh2hdr	 -r2000			${epi_anat}_on_${target:t}_$O
end
if ($status) exit $status

if ($day1_patid != "" || ! $Et2w) goto SKIPT2W
set t4file = ${t2w}_to_${target:t}_t4
foreach O (111 222 333)
	echo		t4img_4dfp $t4file  ${t2w}	${t2w}_on_${target:t}_$O -O$O
	if ($go)	t4img_4dfp $t4file  ${t2w}	${t2w}_on_${target:t}_$O -O$O
	echo		ifh2hdr	 -r1000			${t2w}_on_${target:t}_$O
	if ($go)	ifh2hdr	 -r1000			${t2w}_on_${target:t}_$O
end
if ($status) exit $status
SKIPT2W:
/bin/rm *t4% >& /dev/null
popd		# out of atlas

UNWARP:
##############################################################
# logic to adjudicate between measured vs. computed field maps
##############################################################
if (! ${?gre})  set gre = ()					# gradient echo measured field maps
if (! ${?sefm}) set sefm = ()					# spin echo measured field maps
set D = /data/petsun4/data1/solaris/csh_scripts
if (${#sefm}) then
	if (! -e sefm/${patid}_sefm_mag_brain.nii.gz) then
		sefm_pp_AZS.csh ${prmfile} ${instructions}	# creates sefm subdirectory
		if ($status) exit $status
	else
		echo sefm exists - skipping sefm_pp_AZS.csh
	endif
	set uwrp_args  = (-map $patid atlas/${epi_anat} sefm/${patid}_sefm_mag.nii.gz sefm/${patid}_sefm_pha.nii.gz $dwell $TE_vol $ped 0)
	set log	= ${patid}_fmri_unwarp_170616_se.log
else if (${#gre}) then
	if (! ${?delta}) then
		echo $program":" parameter delta must be defined with gradient echo field mapping
		exit -1
	endif
	if (${#gre} != 2) then
		echo $program":" gradient echo field mapping requires exactly 2 scans
		exit -1
	endif
	dcm2nii -a y -d n -e n -f n -g n -i n -p n -r n -o . $inpath/study$gre[1] >! $$.txt
	if ($status) exit $status
	set F = `cat $$.txt | gawk '/^Saving/{print $NF}'`
	mv $F		${patid}_mag.nii
	if ($status) exit $status
	dcm2nii -a y -d n -e n -f n -g n -i n -p n -r n -o . $inpath/study$gre[2] >! $$.txt
	set F = `cat $$.txt | gawk '/^Saving/{print $NF}'`
	mv $F		${patid}_pha.nii
	if ($status) exit $status
	/bin/rm $$.txt
	set uwrp_args  = (-map $patid atlas/${epi_anat} ${patid}_mag.nii ${patid}_pha.nii $dwell $TE_vol $ped $delta)
	set log	= ${patid}_fmri_unwarp_170616_gre.log
else if ($?FMmean && $?FMbases) then
#########################################################
# unwarping script now expects t2w to be in current atlas
#########################################################
	if ($Et2w) then
		set uwrp_args   = (-basis atlas/${epi_anat} atlas/${t2w} $FMmean $FMbases atlas/${epi_anat}_to_${t2w}_t4 atlas/${epi_anat}_to_${target:t}_t4 $dwell $ped $nbasis)
	else
		if ($day1_patid == "") then 
			if ($go) Generate_FS_Masks_AZS.csh $prmfile $instructions		
			if ($status) exit $status
		endif
		pushd atlas			
			t4img_4dfp ${patid1}_orig_to_${mpr}_t4 ${patid1}_aparc+aseg ${patid1}_aparc+aseg_on_$mpr -O$mpr -n
			if ($status) exit $status
			niftigz_4dfp -n ${patid1}_aparc+aseg_on_$mpr ${patid1}_aparc+aseg_on_$mpr
			if ($status) exit $status			
			$FSLDIR/bin/fslmaths ${patid1}_aparc+aseg_on_$mpr.nii.gz -bin -dilF -dilF -fillh -ero ${patid1}_brain_mask.nii.gz
			if ($status) exit $status			
			niftigz_4dfp -4 ${patid1}_brain_mask ${patid1}_brain_mask
			if ($status) exit $status			
		popd
		set uwrp_args = (-basis atlas/${epi_anat} atlas/$mpr $FMmean $FMbases atlas/${epi_anat}_to_${mpr}_t4 atlas/${epi_anat}_to_${target:t}_t4 $dwell $ped $nbasis atlas/${patid1}_brain_mask)
	endif
	set log	= ${patid}_fmri_unwarp_170616_basis.log
else if ($?FMmean) then
	set uwrp_args = (-mean atlas/${epi_anat} $FMmean atlas/${epi_anat}_to_${target:t}_t4 $dwell $ped)
	set log	= ${patid}_fmri_unwarp_170616_mean.log
else 
	echo "destortion correction can not be done"
	exit -1
endif
##################################
# compute field mapping correction
##################################
date						>! $log
echo	fmri_unwarp_170616.tcsh $uwrp_args	>> $log
	fmri_unwarp_170616.tcsh $uwrp_args	>> $log

###################################################
# compute unwarp/${epi_anat}_uwrp_to_${target:t}_t4
###################################################
if (${#sefm} || ${#gre} || ! $?FMbases) then
	if ($Et2w) then
		niftigz_4dfp -n atlas/$t2w atlas/$t2w
		bet atlas/$t2w atlas/${t2w}_brain -m -f 0.4 -R
		niftigz_4dfp -4 atlas/${t2w}_brain_mask atlas/${t2w}_brain_mask -N
		@ mode = 8192 + 2048 + 3
		/bin/cp atlas/${epi_anat}_to_${t2w}_t4 unwarp/${epi_anat}_uwrp_to_${t2w}_t4
		imgreg_4dfp atlas/$t2w atlas/${t2w}_brain_mask unwarp/${epi_anat}_uwrp none unwarp/${epi_anat}_uwrp_to_${t2w}_t4 $mode \
			>! unwarp/${epi_anat}_uwrp_to_${t2w}.log
		if ($status) exit $status

		t4_mul unwarp/${epi_anat}_uwrp_to_${t2w}_t4 atlas/${t2w}_to_${target:t}_t4 unwarp/${epi_anat}_uwrp_to_${target:t}_t4
		if ($status) exit $status
	else
		pushd atlas; msktgen_4dfp $mpr -T$target; popd;
		@ mode = 8192 + 2048 + 3
		/bin/cp atlas/${epi_anat}_to_${mpr}_t4 unwarp/${epi_anat}_uwrp_to_${mpr}_t4
		imgreg_4dfp atlas/${mpr} atlas/${mpr}_mskt unwarp/${epi_anat}_uwrp none unwarp/${epi_anat}_uwrp_to_${mpr}_t4 $mode \
			>! unwarp/${epi_anat}_uwrp_to_${mpr}.log
		if ($status) exit $status
		t4_mul unwarp/${epi_anat}_uwrp_to_${mpr}_t4 atlas/${mpr}_to_${target:t}_t4 unwarp/${epi_anat}_uwrp_to_${target:t}_t4
		if ($status) exit $status
	endif
else 
	if ($Et2w) then 
		set struct = $t2w
	else
		set struct = $mpr
	endif 
	echo	t4_mul	unwarp/${epi_anat}_uwrp_to_${struct}_t4 atlas/${struct}_to_${target:t}_t4 unwarp/${epi_anat}_uwrp_to_${target:t}_t4
		t4_mul	unwarp/${epi_anat}_uwrp_to_${struct}_t4 atlas/${struct}_to_${target:t}_t4 unwarp/${epi_anat}_uwrp_to_${target:t}_t4
	set t4file = unwarp/${epi_anat}_uwrp_to_${target:t}_t4
	if ($status) exit $status
	echo	t4img_4dfp unwarp/${epi_anat}_uwrp_to_${struct}_t4 unwarp/${epi_anat}_uwrp 	unwarp/${epi_anat}_uwrp_on_${struct} -Oatlas/${struct}
		t4img_4dfp unwarp/${epi_anat}_uwrp_to_${struct}_t4 unwarp/${epi_anat}_uwrp 	unwarp/${epi_anat}_uwrp_on_${struct} -Oatlas/${struct}
	if ($status) exit $status
	ifh2hdr -r2000										unwarp/${epi_anat}_uwrp_on_${struct}
endif
foreach O (111 222 333)
	echo		t4img_4dfp unwarp/${epi_anat}_uwrp_to_${target:t}_t4 unwarp/${epi_anat}_uwrp	unwarp/${epi_anat}_uwrp_on_${target:t}_$O -O$O
	if ($go)	t4img_4dfp unwarp/${epi_anat}_uwrp_to_${target:t}_t4 unwarp/${epi_anat}_uwrp	unwarp/${epi_anat}_uwrp_on_${target:t}_$O -O$O
	echo		ifh2hdr	 -r2000									unwarp/${epi_anat}_uwrp_on_${target:t}_$O
	if ($go)	ifh2hdr	 -r2000									unwarp/${epi_anat}_uwrp_on_${target:t}_$O
end

ATL:
#################################
# one step resample unwarped fMRI
#################################
if (! $epi2atl) exit 0
set x = ${rsam_cmnd:t}; set x = $x:r
set log		= ${patid}_$x.log
date						>! $log
echo	$rsam_cmnd $prmfile $instructions	 > $log
	$rsam_cmnd $prmfile $instructions	>& $log
if ($status) exit $status

####################################################################
# remake single resampled 333 atlas space fMRI volumetric timeseries
####################################################################
set lst = ${patid}${MBstr}_xr3d_uwrp_atl.lst
if (-e $lst) /bin/rm $lst
touch $lst
@ k = 1
while ($k <= $#irun)
	echo bold$irun[$k]/${patid}_b$irun[$k]${MBstr}_xr3d_uwrp_atl.4dfp.img >> $lst
	@ k++
end
conc_4dfp ${lst:r}.conc -l$lst
if ($status) exit $status
set fmtfile = atlas/${patid}_func_vols.format
if (! -e $fmtfile) exit $status
actmapf_4dfp $fmtfile ${patid}${MBstr}_xr3d_uwrp_atl.conc -aave
if ($status) exit $status
ifh2hdr -r2000 		${patid}${MBstr}_xr3d_uwrp_atl_ave
mv			${patid}${MBstr}_xr3d_uwrp_atl_ave.4dfp.*	atlas
var_4dfp -sF$fmtfile	${patid}${MBstr}_xr3d_uwrp_atl.conc
ifh2hdr -r20		${patid}${MBstr}_xr3d_uwrp_atl_sd1
mv			${patid}${MBstr}_xr3d_uwrp_atl_sd1*		atlas
mv			${patid}${MBstr}_xr3d_uwrp_atl.conc*		atlas

echo $program complete status=$status
exit 0
