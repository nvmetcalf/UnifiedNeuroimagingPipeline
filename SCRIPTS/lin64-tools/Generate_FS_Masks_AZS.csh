#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/Generate_FS_Masks_AZS.csh,v 1.16 2020/05/11 02:14:26 avi Exp $
#$Log: Generate_FS_Masks_AZS.csh,v $
# Revision 1.16  2020/05/11  02:14:26  avi
# option -N added to nifti_4dfp -4 calls
#
# Revision 1.15  2018/11/11  05:22:15  avi
# find and copy day1 FS orig to atlas t4 file
# tolerate target named with "4dfp.img" extensions
#
# Revision 1.14  2018/08/20  22:59:30  avi
# remove incorrect 'exit'
#
# Revision 1.13  2018/08/17  05:24:55  avi
# invoke with -f
#
# Revision 1.12  2018/08/01  23:17:52  avi
# call to freesurfer2mpr_4dfp includes optional '-e$etaFS'
#
# Revision 1.11  2016/10/10  23:39:33  avi
# accepts S2T modified mprs (${patid1}_mpr1T)
#
# Revision 1.10  2016/08/25  04:07:13  avi
# do not attempt to rename non-existent rec files (existence suppressed by -R option in maskimg_4dfp)
#
# Revision 1.9  2016/08/25  02:49:37  avi
# remove useless ${patid1}_aparc+aseg.4dfp.img_to_atlas_t4 (if it exists)
#
# Revision 1.8  2016/08/24  01:58:28  avi
# save ${patid1}_aparc+aseg.4dfp in $atldir
#
# Revision 1.7  2016/07/07  23:52:25  avi
# do not write in FreeSurfer area
#
# Revision 1.6  2016/07/03  03:28:58  avi
# further reduce screen output
#
# Revision 1.5  2016/07/03  03:06:21  avi
# reduce screen output
#
# Revision 1.4  2014/06/02  21:27:53  avi
# typo
#
# Revision 1.3  2014/06/02  02:54:57  avi
# tolerate $day1_patid == ""
#
# Revision 1.2  2014/02/22  03:31:33  avi
# note $?day1_patid and set patid1 accordingly
#
# Revision 1.1  2014/02/22  03:03:51  avi
# Initial revision
#
set program = $0; set program = $program:t

set rcsid = '$Id: Generate_FS_Masks_AZS.csh,v 1.16 2020/05/11 02:14:26 avi Exp $'
echo $rcsid

if (${#argv} < 1) then
	echo "Usage:	$program <parameters file> [instructions]"
	echo "e.g.,	$program FCS_039_A_1.params ../uwrp_process_Stroke_SMG_Subjects.params"
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
if (! ${?day1_patid}) set day1_patid = ""
if ($day1_patid != "") then
	set patid1 = $day1_patid
else
	set patid1 = $patid
endif
echo "patid1	=" $patid1
echo "FSdir	=" $FSdir
set atl		= ${target:t}
if (${atl:e} == "img")  set atl = ${atl:r}
if (${atl:e} == "4dfp") set atl = ${atl:r}
echo "atl	=" $atl

##################################
# check existence of prerequisites
##################################
set atldir = $cwd/atlas
if (! -e $atldir) then
	echo $program": "$atldir not found
	exit -1
endif
if (! -e $FSdir) then
	echo $program": "$FSdir not found
	exit -1
endif
if (! -r $FSdir/mri/orig.mgz) then
	echo $program": "read enabled $FSdir/mri/orig.mgz not found
	exit -1
endif
if (! -r $FSdir/mri/aparc+aseg.mgz) then
	echo $program": "read enabled $FSdir/mri/aparc+aseg.mgz not found
	exit -1
endif
if ($patid1 != $patid) then
	set t4file = $day1_path/${patid1}_orig_to_${atl}_t4
	if (! -e $t4file) then
		echo $program":" $day1_path/${patid1}_orig_to_${atl}_t4 not found
		exit -1
	else
		/bin/cp $t4file $atldir
	endif
endif

pushd $atldir			# into atlas directory
################
# freesurfer2mpr
################
if (! -e ${patid1}_orig_to_${atl}_t4) then
	if (! -r orig.mgz) /bin/cp $FSdir/mri/orig.mgz .
	mri_convert -it mgz -ot nii orig.mgz ${patid1}_orig.nii
	if ($status) exit $status
	/bin/rm -f orig.mgz
	nifti_4dfp -4 ${patid1}_orig.nii ${patid1}_orig -N
	if ($status) exit $status
	/bin/rm -f ${patid1}_orig.nii
	if ( -e ${patid1}_mpr1T_to_${atl}_t4) then
		set mpr = ${patid1}_mpr1T.4dfp.img
	else if ( -e ${patid1}_mpr1_to_${atl}_t4) then
		set mpr = ${patid1}_mpr1.4dfp.img
	else
		echo ${patid1}_mpr atlas transform file not found
		exit -1
	endif
	echo running freesurfer2mpr
	if ( $?etaFS ) then
		freesurfer2mpr_4dfp $mpr ${patid1}_orig -T$target -e$etaFS
	else
		freesurfer2mpr_4dfp $mpr ${patid1}_orig -T$target 
	endif
	if ($status) then
		/bin/rm $atldir/${patid1}_orig_to_*_t4
		exit -1
	endif
endif
popd				# out of atlas directory

####################################
# create temporary working directory
####################################
set D = /tmp/${patid1}$$
mkdir $D
pushd $D > /dev/null		# into temp dir
if ($status) exit -1

########################
# apply t4 to aseg image
########################
echo applying freesurfer2mpr t4 to aseg image
mri_convert -it mgz -ot nii $FSdir/mri/aparc+aseg.mgz ${patid1}_aparc+aseg.nii
if ($status) goto ABORT

nifti_4dfp -4 ${patid1}_aparc+aseg.nii ${patid1}_aparc+aseg -N
if ($status) goto ABORT
t4img_4dfp $atldir/${patid1}_orig_to_${atl}_t4 ${patid1}_aparc+aseg ${patid1}_aparc+aseg_on_${atl}_333 -O333 -n
if ($status) goto ABORT
set asegimg = ${patid1}_aparc+aseg_on_${atl}_333

################
# create WB mask
################
maskimg_4dfp ${patid1}_aparc+aseg ${patid1}_aparc+aseg ${patid1}_FSWB -v1
if ($status) goto ABORT
t4img_4dfp $atldir/${patid1}_orig_to_${atl}_t4 ${patid1}_FSWB ${patid1}_FSWB_on_${atl}_333 -O333 -n
if ($status) goto ABORT
ifh2hdr -r1	${patid1}_FSWB_on_${atl}_333
/bin/mv		${patid1}_FSWB_on_${atl}_333.4dfp.* $atldir >& /dev/null

###########################
# initialize ROI list files
###########################
set GMasegnames	= ${patid1}_GM_roinames.txt
set WMasegnames	= ${patid1}_WM_roinames.txt
set CSFsegnames	= ${patid1}_CS_roinames.txt
set GMkeeprgns	= ( 7 8 10 11 12 13 16 17 18 26 28 46 47 49 50 51 52 53 54 58 60 )
set WMkeeprgns	= ( 2 41 )
set CSFeeprgns	= ( 4 14 15 43 )
touch $GMasegnames
touch $WMasegnames
touch $CSFsegnames

########################
# build grey matter mask
########################
echo building grey matter mask
foreach r ($GMkeeprgns)
	zero_ltgt_4dfp ${r}to${r} $asegimg ${asegimg}_${r}
	maskimg_4dfp ${asegimg}_${r} ${asegimg}_${r} ${asegimg}_${r}_v1 -v1 -R
	if ($status) goto ABORT
	foreach e (img ifh hdr)
		/bin/mv -f ${asegimg}_${r}_v1.4dfp.$e ${asegimg}_${r}.4dfp.$e
	end
	echo ${asegimg}_${r}.4dfp.img >> $GMasegnames
end
zero_ltgt_4dfp 1000to2999 $asegimg ${asegimg}_ctx
if ($status) goto ABORT
maskimg_4dfp ${asegimg}_ctx ${asegimg}_ctx ${asegimg}_ctx_v1 -v1 -R
if ($status) goto ABORT
foreach e (img ifh hdr)
	/bin/mv -f ${asegimg}_ctx_v1.4dfp.$e ${asegimg}_ctx.4dfp.$e
end
echo ${asegimg}_ctx.4dfp.img >> $GMasegnames
imgopr_4dfp -a${patid1}_GM_on_${atl}_333 -l$GMasegnames
if ($status) goto ABORT

###############
# build WM mask
###############
echo building white matter mask
foreach r ($WMkeeprgns)
	zero_ltgt_4dfp ${r}to${r} $asegimg ${asegimg}_${r}
	maskimg_4dfp ${asegimg}_${r} ${asegimg}_${r} ${asegimg}_${r}_v1 -v1 -R
	rm ${asegimg}_${r}.*
	foreach e (img ifh hdr)
		/bin/mv -f ${asegimg}_${r}_v1.4dfp.$e ${asegimg}_${r}.4dfp.$e
	end
	echo ${asegimg}_${r}.4dfp.img >> $WMasegnames
end
imgopr_4dfp -a${patid1}_WM_on_${atl}_333 -l$WMasegnames
if ($status) goto ABORT

################
# build CSF mask
################
echo building white matter mask
foreach r ($CSFeeprgns)
	zero_ltgt_4dfp ${r}to${r} $asegimg ${asegimg}_${r}
	maskimg_4dfp ${asegimg}_${r} ${asegimg}_${r} ${asegimg}_${r}_v1 -v1 -R
	rm ${asegimg}_${r}.*
	foreach e (img ifh hdr)
		/bin/mv -f ${asegimg}_${r}_v1.4dfp.$e ${asegimg}_${r}.4dfp.$e
	end
	echo ${asegimg}_${r}.4dfp.img >> $CSFsegnames
end
imgopr_4dfp -a${patid1}_CS_on_${atl}_333 -l$CSFsegnames
if ($status) goto ABORT

#############################################
# blur grey matter and remove from WM and CSF
#############################################
set GM = ${patid1}_GM_on_${atl}_333
set WM = ${patid1}_WM_on_${atl}_333
set CS = ${patid1}_CS_on_${atl}_333
scale_4dfp $GM -1 -b1 -acomp 
imgblur_4dfp ${GM}_comp 6
ifh2hdr -r1  ${GM}_comp_b60
maskimg_4dfp $WM ${GM}_comp_b60 ${patid1}_WM_erode_on_${atl}_333 -t0.9
if ($status) goto ABORT
cluster_4dfp ${patid1}_WM_erode_on_${atl}_333 -n100
if ($status) goto ABORT
maskimg_4dfp $CS ${GM}_comp_b60 ${patid1}_CS_erode_on_${atl}_333 -t0.9
if ($status) exit $status
cluster_4dfp ${patid1}_CS_erode_on_${atl}_333 -n15
if ($status) goto ABORT

########################################
# mv generated images to atlas directory
########################################
/bin/rm -f *.4dfp.img_to_atlas_t4 >& /dev/null;		# existence of these useless files depends on FreeSurfer version
/bin/mv ${patid1}_GM*.4dfp.* ${patid1}_WM*.4dfp.* ${patid1}_CS*.4dfp.* ${patid1}_aparc+aseg.4dfp.* ${patid1}_aparc+aseg_on_${atl}_333.4dfp.* $atldir >& /dev/null

###############################
# clean up intermediate results
###############################
popd > /dev/null		# out of temp dir
/bin/rm -rf $D
echo $program sucessfully completed
exit 0

ABORT:
popd > /dev/null		# out of temp dir
/bin/rm -rf $D
exit -1


