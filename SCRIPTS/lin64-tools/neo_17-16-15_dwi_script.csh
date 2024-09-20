#!/bin/csh -f

set idstr = '$Id: neo_17-16-15_dwi_script.csh,v 1.4 2018/08/17 05:50:56 avi Exp $'
echo $idstr
set program = $0; set program = $program:t

if (${#argv} < 1) then
	echo "Usage:	"$program" params_file [instructions_file]"
	exit 1
endif
set prmfile = $1
echo "prmfile="$prmfile
if (! -e $prmfile) then
	echo $program": "$prmfile not found
	exit -1
endif
cat	$prmfile
source	$prmfile
if (${#argv} > 1) then
	set instructions = $2
	if (! -e $instructions) then
		echo $program": "$instructions not found
		exit -1
	endif
	cat	$instructions
	source	$instructions
endif
echo $program": patid="$patid

if (! ${?sorted}) then
	@ sorted = 0
endif
if (! $sorted) then
#################
# compute dcmroot
#################
	if (! ${?dcmroot}) then
		pushd $inpath
		set dcmroot = `ls *IMA | head -1 | gawk '{for(l=length;l>0;l--)if(substr($1,l,1)=="."){k++;if(k==11)break;}print(substr($1,1,l-1))}'`
		popd
	endif
	echo "dcmroot="$dcmroot
endif

set target = 711-2N		# hard coded for neonatal atlas transforms
set tarstr = -T$target

##########################
# execute final step re-do
##########################
if (${?gotoDWI})	then
	goto DWI
endif
if (${?gotoDWI1})	then
	pushd DWI
	goto DWI1
endif
if (${?gotoDWI2})	then
	pushd DWI
	goto DWI2
endif
if (${?gotoDTI})	then
	pushd DWI
	goto DTI
endif
if (${?gotoDTI1})	then
	pushd DWI
	goto DTI1
endif

######################
# atlas transformation
######################
if (! -d atlas) mkdir atlas
pushd atlas			# into atlas

T2W:
#########################
# compute atlas transform
#########################
if (! ${?tse})	set tse = ()
if (! ${?pdt2})	set pdt2 = ()
@ ntse = ${#tse}
if ($ntse) then
	set tselst = ()
	@ k = 1
	while ($k <= $ntse)
		set filenam = $patid"_t2w"
		if ($ntse > 1) set filenam = $filenam$k
		if ($sorted) then
			echo	dcm_to_4dfp -b $filenam $inpath/study$tse[$k]
				dcm_to_4dfp -b $filenam $inpath/study$tse[$k]
		else
			echo	dcm_to_4dfp -b $filenam $inpath/$dcmroot.$tse[$k]."*"
			 	dcm_to_4dfp -b $filenam $inpath/$dcmroot.$tse[$k].*
		endif
		if ($status) exit $status
		set tselst = ($tselst $filenam)
		@ k++
	end
	if ($ntse  > 1) then
		echo	collate_slice_4dfp $tselst $patid"_t2w"
			collate_slice_4dfp $tselst $patid"_t2w"
	endif
else if (${#pdt2}) then
	if ($sorted) then
		echo	dcm_to_4dfp -b $patid"_pdt2" $inpath/study$pdt2
			dcm_to_4dfp -b $patid"_pdt2" $inpath/study$pdt2
	else
		echo	dcm_to_4dfp -b $patid"_pdt2" $inpath/$dcmroot.$pdt2."*"
		 	dcm_to_4dfp -b $patid"_pdt2" $inpath/$dcmroot.$pdt2.*
	endif
	if ($status) exit $status

	echo	extract_frame_4dfp $patid"_pdt2" 2 -o$patid"_t2w"
		extract_frame_4dfp $patid"_pdt2" 2 -o$patid"_t2w"
	if ($status) exit $status
endif

set log = ${patid}_t2w_neo_t2w2atl1_4dfp.log
date								>>! $log
echo	neo_t2w2atl1_4dfp ${patid}_t2w $neo_atlas_target
echo	neo_t2w2atl1_4dfp ${patid}_t2w $neo_atlas_target	>>  $log
	neo_t2w2atl1_4dfp ${patid}_t2w $neo_atlas_target	>>  $log
if ($status) exit $status

########################
# make generous T2W mask
########################
echo	msktgen_4dfp ${patid}_t2w 100 $tarstr
	msktgen_4dfp ${patid}_t2w 100 $tarstr
if ($status) exit $status

popd				# out of atlas

DWI:
#####
# DWI
#####
if (! -d DWI) mkdir DWI
pushd DWI			# into DWI
###########################
# convert DWI dicom to 4dfp
###########################
@ I0vol = 1
@ k = 1
while ($k <= ${#DWI})
	set root = ${patid}_dwi_$DWItyp[$k]
	if ($sorted) then
		echo	dcm_to_4dfp -b $$ $inpath/study$DWI[$k]
			dcm_to_4dfp -b $$ $inpath/study$DWI[$k]
	else
		echo	dcm_to_4dfp -b $$ $inpath/$dcmroot.$DWI[$k]."*"
			dcm_to_4dfp -b $$ $inpath/$dcmroot.$DWI[$k].*
	endif
	if ($status) exit $status

	echo	unpack_4dfp $$ ${root} -V -nx$dwinx -ny$dwiny
		unpack_4dfp $$ ${root} -V -nx$dwinx -ny$dwiny
	if ($status) exit $status
	/bin/rm $$.4dfp.*
	@ k++
end

DWI1:
#############################
# paste DWI 17,16,15 together
#############################
set lst = ${patid}_dwi.lst
if (-e $lst) /bin/rm $lst
touch $lst
foreach typ ($DWItyp)
	@ k = `cat ${patid}_dwi_$typ.4dfp.ifh | awk '/matrix size \[4\]/{print $NF}'`
	echo ${patid}_dwi_$typ	1	$k	>> $lst
end
paste_4dfp -a ${patid}_dwi.lst	${patid}_dwi
if ($status) exit $status
set root =			${patid}_dwi

#########################
# register DWI to t2w and
# compute generous mask
#########################
	@ I0vol = 1
	set oristr = (T C S)
	set modes = (0 0 0 0 0)
	@ modes[1] = 4096 + 3
	@ modes[2] = 3072 + 3
	@ modes[3] = 2048 + 3
	@ modes[4] = 2048 + 3 + 4
	@ modes[5] = 2048 + 3 + 4 + 8192
	set t4file = ${root}_to_${patid}_t2w_t4
	extract_frame_4dfp $root $I0vol
	if ($status) exit $status
	set log = ${root}_to_${patid}_t2w.log
	date >! $log
	@ ori = `awk '/orientation/{print $NF - 1}' ../atlas/${patid}_t2w.4dfp.ifh`
	t4_inv $RELEASE/$oristr[$ori]_t4 $t4file	# assume DWI is transverse
	if ($status) exit $status
	@ k = 1
	while ($k < ${#modes})
		echo	imgreg_4dfp ../atlas/${patid}_t2w ../atlas/${patid}_t2w_mskt ${root}_frame$I0vol none $t4file $modes[$k] >> $log
			imgreg_4dfp ../atlas/${patid}_t2w ../atlas/${patid}_t2w_mskt ${root}_frame$I0vol none $t4file $modes[$k] >> $log
		tail -14 $log
		@ k++
	end
	t4img_4dfp $t4file ${root}_frame$I0vol ${root}_frame${I0vol}_on_${patid}_t2w -O../atlas/${patid}_t2w
	if ($status) exit $status
	t4_mul $t4file ../atlas/${patid}_t2w_to_${target:t}_t4 ${root}_to_${target:t}_t4
	msktgen_4dfp $root 100 $tarstr
	if ($status) exit $status

#######################
# run dwi_xalign3d_4dfp
#######################
	set log = ${root}_dwi_xalign3d_4dfp.log
	date >! $log
echo	dwi_xalign3d_4dfp -sm $grpstr $root $root"_mskt" >> $log
	dwi_xalign3d_4dfp -sm $grpstr $root $root"_mskt" >> $log
	if ($status) exit $status

##############################
# transform DWI to atlas space
##############################
t4img_4dfp ${patid}_dwi_to_${target:t}_t4 ${patid}_dwi_xenc	${patid}_dwi_xenc_on_${target:t}_111 -O111
if ($status) exit $status
ifh2hdr -r800							${patid}_dwi_xenc_on_${target:t}_111

DTI:
#############
# compute DTI
#############
diff_4dfp	$diff_4dfp_opts		$dtiprm	${patid}_dwi_xenc
if ($status) exit $status
diffRGB_4dfp	$diffRGB_4dfp_opts	$dtiprm	${patid}_dwi_xenc 
if ($status) exit $status
ifh2hdr -r-1to3.5				${patid}_dwi_xenc_dti
whisker_prepare	$diff_4dfp_opts		$dtiprm	${patid}_dwi_xenc
if ($status) exit $status
diffRGB_4dfp	$diffRGB_4dfp_opts	$dtiprm	${patid}_dwi_xenc_on_${target:t}_111 -T${patid}_dwi_to_${target:t}_t4
if ($status) exit $status
diff_4dfp	$diff_4dfp_opts 	$dtiprm	${patid}_dwi_xenc_on_${target:t}_111
if ($status) exit $status

DTI1:
###############################
# extract DTI parameter volumes
###############################
set F = ${patid}_dwi_xenc_dti.4dfp.img.rec
@ V_FA = `awk '$1=="Volume" && $0~/Fractional/	{printf $2}' $F`
@ V_L1 = `awk '$1=="Volume" && $0~/Lambda1/	{printf $2}' $F`
@ V_L2 = `awk '$1=="Volume" && $0~/Lambda2/	{printf $2}' $F`
@ V_L3 = `awk '$1=="Volume" && $0~/Lambda3/	{printf $2}' $F`
echo V-FA=$V_FA
echo V_L1=$V_L1
echo V_L2=$V_L2
echo V_L3=$V_L3

extract_frame_4dfp ${patid}_dwi_xenc_dti 1 		-o${patid}_Dbar;	ifh2hdr -r4 ${patid}_Dbar
extract_frame_4dfp ${patid}_dwi_xenc_dti 2 		-o${patid}_Asigma;	ifh2hdr -r1 ${patid}_Asigma
extract_frame_4dfp ${patid}_dwi_xenc_dti $V_FA 		-o${patid}_FA;		ifh2hdr -r1 ${patid}_FA
if ($V_L3) then
	extract_frame_4dfp ${patid}_dwi_xenc_dti $V_L3 	-o${patid}_AxialD;	ifh2hdr -r4 ${patid}_AxialD
	extract_frame_4dfp ${patid}_dwi_xenc_dti $V_L1	-o${patid}_dwi_xenc_L1
	extract_frame_4dfp ${patid}_dwi_xenc_dti $V_L2	-o${patid}_dwi_xenc_L2
	imgopr_4dfp ${patid}_dwi_xenc_L[12].4dfp.img	-e${patid}_RadialD;	ifh2hdr -r4 ${patid}_RadialD
	/bin/rm     ${patid}_dwi_xenc_L[12].4dfp.*
endif

extract_frame_4dfp ${patid}_dwi_xenc_on_${target:t}_111_dti 1		-o${patid}_on_${target:t}_111_Dbar;	ifh2hdr -r4 ${patid}_on_${target:t}_111_Dbar
extract_frame_4dfp ${patid}_dwi_xenc_on_${target:t}_111_dti 2		-o${patid}_on_${target:t}_111_Asigma;	ifh2hdr -r1 ${patid}_on_${target:t}_111_Asigma
extract_frame_4dfp ${patid}_dwi_xenc_on_${target:t}_111_dti $V_FA	-o${patid}_on_${target:t}_111_FA;	ifh2hdr -r1 ${patid}_on_${target:t}_111_FA
if ($V_L3) then
	extract_frame_4dfp ${patid}_dwi_xenc_on_${target:t}_111_dti $V_L3	-o${patid}_on_${target:t}_111_AxialD;	ifh2hdr -r4 ${patid}_on_${target:t}_111_AxialD
	extract_frame_4dfp ${patid}_dwi_xenc_on_${target:t}_111_dti $V_L1	-o${patid}_dwi_xenc_on_${target:t}_111_L1
	extract_frame_4dfp ${patid}_dwi_xenc_on_${target:t}_111_dti $V_L2	-o${patid}_dwi_xenc_on_${target:t}_111_L2
	imgopr_4dfp ${patid}_dwi_xenc_on_${target:t}_111_L[12].4dfp.img	-e${patid}_on_${target:t}_111_RadialD;	ifh2hdr -r4 ${patid}_on_${target:t}_111_RadialD
	/bin/rm     ${patid}_dwi_xenc_on_${target:t}_111_L[12].4dfp.*
endif
popd				# out of DWI

exit
