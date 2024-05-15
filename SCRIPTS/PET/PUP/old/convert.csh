#!/bin/csh

#########need to adjust start time in O15OC text file

set mapdrive = z

#setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/4dfp/4dfp_cygwin64"
#setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/scripts"
#setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/PPG/scripts"
setenv PATH "${PATH}:/data/nil-bluearc/raichle/suy/PPG/scripts"
#setenv RELEASE /cygdrive/$mapdrive/suy/4dfp/4dfp_cygwin64

set rawdir = /data/nil-bluearc/raichle/PPGdata/rawdata
#set rawdir = /cygdrive/$mapdrive/PPGdata/rawdata

#set pids = (TW03 NP995_09 DT04 NP995_05)
set pids = (TW03)
#set pids = (NP995_05 NP995_09 DT04)

foreach pid ($pids)
	if (! -d $pid) mkdir $pid

	set dcms = `gawk '$1=="'$pid'" {for(i=2;i<=NF;i++)print $i}' dcm_dir.txt`

	set mpr  = `gawk '$1=="'$pid'"&&$2=="MPR" {print $3}' dcm_subdir.txt`
	set ct   = `gawk '$1=="'$pid'"&&$2=="CT"  {print $3}' dcm_subdir.txt`

	pushd $pid

#	dcm_to_4dfp -b $pid"_ct"  $rawdir/$dcms[1]/[Ss]*/$ct/DICOM/*dcm;	if ($status) exit $status
#	dcm_to_4dfp -b $pid"_mpr" $rawdir/$dcms[2]/[Ss]*/$mpr/DICOM/*dcm;	if ($status) exit $status

#	reg2img $pid"_mpr" $pid"_ct";						if ($status) exit $status
#	t4img_4dfp $pid"_ct_to_"$pid"_mpr_t4" $pid"_ct" $pid"_ct_on_"$pid"_mpr" -O$pid"_mpr";	if ($status) exit $status

	set holabels = (); set oolabels = (); set oclabels = (); set fdglabels = ()
	@ i = 1
	foreach dcm ($dcms[2-])
		set mrac = `gawk '$1=="'$pid'"&&$2=="MRAC"&&$3=='$i' {print $4}' ../dcm_subdir.txt`
		if (-d MRAC_v$i) rm -r MRAC_v$i
#		~suy/bin/sortncpdcm $rawdir/$dcm/[Ss]*/$mrac/DICOM MRAC_v$i dcm
#		dcm_to_4dfp -b $pid"_MRAC_v"$i MRAC_v$i/*dcm;			if ($status) exit $status
#		reg2img $pid"_mpr" $pid"_MRAC_v"$i;				if ($status) exit $status

#		t4img_4dfp $pid"_MRAC_v"$i"_to_"$pid"_mpr_t4" $pid"_MRAC_v"$i $pid"_MRAC_v"$i"_on_"$pid"_mpr" -O$pid"_mpr";	if ($status) exit $status
#		custom_umap_4dfp $pid"_ct_on_"$pid"_mpr" $pid"_MRAC_v"$i"_on_"$pid"_mpr" temp$$;				if ($status) exit $status
#		flip_4dfp -z temp$$ $pid"_v"$i"_umap";										if ($status) exit $status
#		rm temp$$.4dfp.*

		foreach MD (FDG HO OO OC)
			set md = `echo $MD | gawk '{print tolower($0)}'`
			set newnames = ()
			if ($MD == FDG) then
				set sub = `gawk '$1=="'$pid'"&&$2=="'$MD'"&&$3=='$i' {print $NF}' ../dcm_subdir.txt`
				set s   = `gawk '$1=="'$pid'"&&$2=="'$MD'"&&$3=='$i' {print $4}'  ../dcm_subdir.txt`
				set rawdirname = $rawdir/$dcm"RawData"/*/*/$sub
				set umapdir = $rawdir/$dcm/[Ss]*/$s/DICOM
				set newnames = ($newnames $MD"_v"$i)
				set fdglabels = ($fdglabels "_v"$i)
#				if (-d $MD"_v"$i) rm -r $MD"_v"$i
#				cp -r $rawdirname $MD"_v"$i
#				if (-d $MD"_v"$i/umap) rm -r $MD"_v"$i/umap
#				~suy/bin/sortncpdcm $umapdir $MD"_v"$i/umap dcm
			else
				foreach n (`gawk '$1=="'$pid'"&&$2=="'$MD'"&&$4=='$i' {print $3}' ../dcm_subdir.txt`)
					set sub = `gawk '$1=="'$pid'"&&$2=="'$MD'"&&$4=='$i'&&$3=='$n' {print $NF}' ../dcm_subdir.txt`
					set s   = `gawk '$1=="'$pid'"&&$2=="'$MD'"&&$4=='$i'&&$3=='$n' {print $5}'  ../dcm_subdir.txt`
					set rawdirname = $rawdir/$dcm"RawData"/*/*/$sub
					set umapdir = $rawdir/$dcm/[Ss]*/$s/DICOM
					set newnames = ($newnames $MD$n"_v"$i)
#					if (-d $MD$n"_v"$i) rm -r $MD$n"_v"$i
#					cp -r $rawdirname $MD$n"_v"$i
#					if (-d $MD"_v"$i/umap) rm -r $MD$n"_v"$i/umap
#					~suy/bin/sortncpdcm $umapdir $MD$n"_v"$i/umap dcm
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

			foreach newname ($newnames)
				set imgname  = `echo $newname | gawk '{print "'$pid'"tolower($1)"_sumall"}'`
				set umapname = `echo $newname | gawk '{print "'$pid'"tolower($1)"_umap"}'`
#				if (! -e $imgname.4dfp.img) then
#					if (-d $newname"-Converted") rm -r $newname"-Converted"
#					cscript C:/JSRecon12/JSRecon12.js $newname C:/JSRecon12/O15NAC.txt
#					sed -i '/Run-05/d' $newname"-Converted"/$newname"-LM-00/Run-99-"$newname"-LM-00-ALL.bat"
#					$newname"-Converted"/$newname"-LM-00/Run-99-"$newname"-LM-00-ALL.bat"
#					IFhdr_to_4dfp $newname"-Converted"/$newname"-LM-00"/$newname"-LM-00-FBP_000_000.v.hdr" $imgname
#					IFhdr_to_4dfp $newname"-Converted"/$newname"-LM-00"/$newname"-LM-00-umap.v.hdr"        $umapname
#					rm $imgname"fz".* $umapname"fz".*
#				endif
			end
		end

		@ i ++
	end

#	echo "set TARGET	= TRIO_Y_NDC"			>! $pid.params
#	echo "set TARGETPATH	= /data/cninds01/data2/atlas"	>> $pid.params
#	echo "set PATID		= "$pid				>> $pid.params
#	echo "set MPR		= "$pid"_mpr"			>> $pid.params
#	echo "set  HO_LABELS	= ("$holabels")"		>> $pid.params
#	echo "set  OO_LABELS	= ("$oolabels")"		>> $pid.params
#	echo "set  OC_LABELS	= ("$oclabels")"		>> $pid.params
#	echo "set FDG_LABELS	= ("$fdglabels")"		>> $pid.params
#	echo "set  HO_NAME	= sumall"			>> $pid.params
#	echo "set  OO_NAME	= sumall"			>> $pid.params
#	echo "set  OC_NAME	= sumall"			>> $pid.params
#	echo "set FDG_NAME	= sumall"			>> $pid.params
#	echo "set  HO_CROSS_PET_OPTIONS	= ()"			>> $pid.params
#	echo "set  OO_CROSS_PET_OPTIONS	= ()"			>> $pid.params
#	echo "set  OC_CROSS_PET_OPTIONS	= (-oc)"		>> $pid.params
#	echo "set FDG_CROSS_PET_OPTIONS	= ()"			>> $pid.params
#	echo "set KEEP_MPR_T4 = 1"				>> $pid.params
#	echo "set PET_RESOLVE_SCHEME	= /data/petsun4/data1/src_solaris/pet_4dfp/default.scheme"	>> $pid.params
#	pet2atl_4dfp $pid.params

	@ i = 1
	foreach dcm ($dcms[2-])
		foreach cdir ({FDG,HO,OO,OC}*_v$i)
			set txt = `echo $cdir | gawk '/^FDG/{print "F18dyn"} /^[HO]O/{print "O15dyn"} /^OC/{print "O15OC"}'`
			set img = `echo $cdir | gawk '{print "'$pid'"tolower($0)}'`
#			t4_inv $img"_sumall_to_"$pid"_mpr_t4"
#			t4img_4dfp $pid"_mpr_to_"$img"_sumall_t4" $pid"_v"$i"_umap" $cdir"-Converted"/$cdir"-LM-00"/$cdir"-LM-00-umap.v"

#			if (-d $cdir"-Converted") rm -r $cdir"-Converted"
#			cscript C:/JSRecon12/JSRecon12.js $cdir C:/JSRecon12/$txt.txt
#			if (`echo $cdir | gawk '{if ($0~/^[HO]O/) print 1; else print 0}'`) then
#				gawk 'BEGIN{go=0;stop=0} /set cmd=/{go=1} go==1&&stop==0&&$0!~/set cmd=/{print "set cmd= %cmd% --abs"; go=0; stop=1} {print $0}' $cdir"-Converted"/$cdir"-LM-00/Run-04-"$cdir"-LM-00-OP.bat" >! temp$$
#				mv temp$$ $cdir"-Converted"/$cdir"-LM-00/Run-04-"$cdir"-LM-00-OP.bat"
#			endif
#			sed -i '/Run-05/d' $cdir"-Converted"/$cdir"-LM-00"/"Run-99-"$cdir"-LM-00-ALL.bat"
#			sed -i '/FBP/d'    $cdir"-Converted"/$cdir"-LM-00"/"Run-99-"$cdir"-LM-00-ALL.bat"
#			sed -i '/PSF/d'    $cdir"-Converted"/$cdir"-LM-00"/"Run-99-"$cdir"-LM-00-ALL.bat"
#			$cdir"-Converted"/$cdir"-LM-00"/"Run-99-"$cdir"-LM-00-ALL.bat"
			~suy/bin/scripts/sif_4dfp $cdir"-Converted"/$cdir"-LM-00"/$cdir"-LM-00-OP.mhdr" $img
		end
		@ i ++	
	end

	popd
end

exit 0
