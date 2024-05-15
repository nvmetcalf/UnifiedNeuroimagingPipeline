#!/bin/csh

setenv PATH "${PATH}:/data/nil-bluearc/raichle/suy/PPG/scripts"

set rawdir = /data/nil-bluearc/raichle/PPGdata/rawdata

set MDS = (FDG HO OO OC)
set pid = $argv[1]
if ($#argv > 1) set MDS = $argv[2-]

set dcms = `gawk '$1=="'$pid'" {for(i=2;i<=NF;i++)print $i}' dcm_dir.txt`

set mpr  = `gawk '$1=="'$pid'"&&$2=="MPR" {print $3}' dcm_subdir.txt`
set ct   = `gawk '$1=="'$pid'"&&$2=="CT"  {print $3}' dcm_subdir.txt`

pushd $pid

set holabels = (); set oolabels = (); set oclabels = (); set fdglabels = ()
#@ i = 1
@ i = 2
#foreach dcm ($dcms[2-])
foreach dcm ($dcm2[3-])
	set mrac = `gawk '$1=="'$pid'"&&$2=="MRAC"&&$3=='$i' {print $4}' ../dcm_subdir.txt`

	foreach MD ($MDS)
		set md = `echo $MD | gawk '{print tolower($0)}'`
		if ($MD == FDG) then
			set fdglabels = ($fdglabels "_v"$i)
		else
			foreach n (`gawk '$1=="'$pid'"&&$2=="'$MD'"&&$4=='$i' {print $3}' ../dcm_subdir.txt`)
				switch ($MD)
				case "HO":
					set holabels = ($holabels $n"_v"$i); breaksw;
				case "OO":
					set oolabels = ($oolabels $n"_v"$i); breaksw;
				case "OC":
					set oclabels = ($oclabels $n"_v"$i); breaksw;
				endsw
			end
		endif
	end

	@ i ++
end

#echo "set TARGET	= TRIO_Y_NDC"			>! $pid.params
#echo "set TARGETPATH	= /data/cninds01/data2/atlas"	>> $pid.params
#echo "set PATID		= "$pid				>> $pid.params
#echo "set MPR		= "$pid"_mpr"			>> $pid.params
#echo "set  HO_LABELS	= ("$holabels")"		>> $pid.params
#echo "set  OO_LABELS	= ("$oolabels")"		>> $pid.params
#echo "set  OC_LABELS	= ("$oclabels")"		>> $pid.params
#echo "set FDG_LABELS	= ("$fdglabels")"		>> $pid.params
#echo "set  HO_NAME	= sumall"			>> $pid.params
#echo "set  OO_NAME	= sumall"			>> $pid.params
#echo "set  OC_NAME	= sumall"			>> $pid.params
#echo "set FDG_NAME	= sumall"			>> $pid.params
#echo "set  HO_CROSS_PET_OPTIONS	= ()"			>> $pid.params
#echo "set  OO_CROSS_PET_OPTIONS	= ()"			>> $pid.params
#echo "set  OC_CROSS_PET_OPTIONS	= (-oc)"		>> $pid.params
#echo "set FDG_CROSS_PET_OPTIONS	= ()"			>> $pid.params
#echo "set KEEP_MPR_T4 = 1"				>> $pid.params
#echo "set PET_RESOLVE_SCHEME	= /data/petsun4/data1/src_solaris/pet_4dfp/default.scheme"	>> $pid.params

#pet2atl_4dfp $pid.params

gauss_4dfp $pid"_mpr" 0.8;										if ($status) exit $status
t4img_4dfp $pid"_mpr_to_"$pid"_ct_t4" $pid"_mpr_g8" $pid"_mpr_g8_on_"$pid"_ct" -O$pid"_ct";		if ($status) exit $status
maskimg_4dfp -p5.0 -v1.0 $pid"_mpr_g8_on_"$pid"_ct" $pid"_mpr_g8_on_"$pid"_ct" $pid"_ct_mask";		if ($status) exit $status
scale_4dfp $pid"_ct_mask" -1.0 -b1.0;									if ($status) exit $status
cluster_4dfp $pid"_ct_mask" -n`cluster_4dfp $pid"_ct_mask" | gawk '/^region/{getline; print $2}'`;	if ($status) exit $status
scale_4dfp $pid"_ct_mask_clus" -1.0 -b1.0;								if ($status) exit $status
maskimg_4dfp $pid"_ct" $pid"_ct_mask_clus" $pid"_ct_msk";						if ($status) exit $status

@ i = 1
foreach dcm ($dcms[2-])
	foreach MD ($MDS)
	foreach cdir ($MD*_v$i)
		set img  = `echo $cdir | gawk '{print "'$pid'"tolower($0)}'`
		set umap = `echo $cdir | gawk '{print "'$pid'"tolower($1)"_umap"}'`
		t4_inv $img"_sumall_to_"$pid"_mpr_t4";									if ($status) exit $status
		t4_mul $pid"_ct_to_"$pid"_mpr_t4" $pid"_mpr_to_"$img"_sumall_t4";					if ($status) exit $status
		t4img_4dfp $pid"_ct_to_"$img"_sumall_t4" $pid"_ct_msk" $pid"_ct_on_"$img"_sumall" -O$img"_sumall";	if ($status) exit $status
		custom_umap_4dfp $pid"_ct_on_"$img"_sumall" $umap"_e7" temp$$;						if ($status) exit $status
		flip_4dfp -z temp$$ $img"_umap";									if ($status) exit $status
		rm temp$$.4dfp.*
	end
	end
	@ i ++
end

popd

exit 0
