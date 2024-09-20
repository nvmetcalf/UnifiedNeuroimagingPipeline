#!/bin/csh -f

set program = $0; set program = $program:t
set rcsid = '$Id: Generate_FS_Masks_333.csh,v 1.2 2018/08/16 05:11:17 avi Exp $'
echo $rcsid

if (${#argv} < 2) then
	echo "Usage:	$program <patid> <aparc+aseg_333>"
	exit 1
endif 
date
uname -a

set patid	= $1
set asegimg	= $2; if ($asegimg:e == "img") set asegimg = $asegimg:r; if ($asegimg:e == "4dfp") set asegimg = $asegimg:r;
set atl		= TRIO_Y_NDC

################
# create WB mask
################
maskimg_4dfp $asegimg $asegimg ${patid}_FSWB_on_${atl}_333 -v1
if ($status) goto ABORT

###########################
# initialize ROI list files
###########################
set GMasegnames	= ${patid}_GM_roinames.txt
set WMasegnames	= ${patid}_WM_roinames.txt
set CSFsegnames	= ${patid}_CS_roinames.txt
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
	foreach e (img ifh hdr img.rec)
		/bin/mv -f ${asegimg}_${r}_v1.4dfp.$e ${asegimg}_${r}.4dfp.$e
	end
	echo ${asegimg}_${r}.4dfp.img >> $GMasegnames
end
zero_ltgt_4dfp 1000to2999 $asegimg ${asegimg}_ctx
if ($status) goto ABORT
maskimg_4dfp ${asegimg}_ctx ${asegimg}_ctx ${asegimg}_ctx_v1 -v1 -R
if ($status) goto ABORT
foreach e (img ifh hdr img.rec)
	/bin/mv -f ${asegimg}_ctx_v1.4dfp.$e ${asegimg}_ctx.4dfp.$e
end
echo ${asegimg}_ctx.4dfp.img >> $GMasegnames
imgopr_4dfp -a${patid}_GM_on_${atl}_333 -l$GMasegnames
if ($status) goto ABORT

###############
# build WM mask
###############
echo building white matter mask
foreach r ($WMkeeprgns)
	zero_ltgt_4dfp ${r}to${r} $asegimg ${asegimg}_${r}
	maskimg_4dfp ${asegimg}_${r} ${asegimg}_${r} ${asegimg}_${r}_v1 -v1 -R
	rm ${asegimg}_${r}.*
	foreach e (img ifh hdr img.rec)
		/bin/mv -f ${asegimg}_${r}_v1.4dfp.$e ${asegimg}_${r}.4dfp.$e
	end
	echo ${asegimg}_${r}.4dfp.img >> $WMasegnames
end
imgopr_4dfp -a${patid}_WM_on_${atl}_333 -l$WMasegnames
if ($status) goto ABORT

################
# build CSF mask
################
echo building white matter mask
foreach r ($CSFeeprgns)
	zero_ltgt_4dfp ${r}to${r} $asegimg ${asegimg}_${r}
	maskimg_4dfp ${asegimg}_${r} ${asegimg}_${r} ${asegimg}_${r}_v1 -v1 -R
	rm ${asegimg}_${r}.*
	foreach e (img ifh hdr img.rec)
		/bin/mv -f ${asegimg}_${r}_v1.4dfp.$e ${asegimg}_${r}.4dfp.$e
	end
	echo ${asegimg}_${r}.4dfp.img >> $CSFsegnames
end
imgopr_4dfp -a${patid}_CS_on_${atl}_333 -l$CSFsegnames
if ($status) goto ABORT

#############################################
# blur grey matter and remove from WM and CSF
#############################################
set GM = ${patid}_GM_on_${atl}_333
set WM = ${patid}_WM_on_${atl}_333
set CS = ${patid}_CS_on_${atl}_333
scale_4dfp $GM -1 -b1 -acomp 
imgblur_4dfp ${GM}_comp 6
ifh2hdr -r1  ${GM}_comp_b60
maskimg_4dfp $WM ${GM}_comp_b60 ${patid}_WM_erode_on_${atl}_333 -t0.9
if ($status) goto ABORT
cluster_4dfp ${patid}_WM_erode_on_${atl}_333 -n100
if ($status) goto ABORT
maskimg_4dfp $CS ${GM}_comp_b60 ${patid}_CS_erode_on_${atl}_333 -t0.9
if ($status) exit $status
cluster_4dfp ${patid}_CS_erode_on_${atl}_333 -n15
if ($status) goto ABORT

echo $program sucessfully completed
exit 0

ABORT:
exit -1

