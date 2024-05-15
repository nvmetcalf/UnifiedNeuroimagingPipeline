#!/bin/csh

set mapdrive = z

setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/4dfp/4dfp_cygwin64"
setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/scripts"
setenv PATH "${PATH}:/cygdrive/$mapdrive/suy/PPG/scripts"
setenv RELEASE /cygdrive/$mapdrive/suy/4dfp/4dfp_cygwin64

set rawdir = /cygdrive/$mapdrive/PPGdata/rawdata

set MDS = (FDG HO OO OC)
set pid = $argv[1]
if ($#argv > 1) set MDS = $argv[2-]

set dcms = `gawk '$1=="'$pid'" {for(i=2;i<=NF;i++)print $i}' dcm_dir.txt`

pushd $pid

@ i = 1
foreach dcm ($dcms[2-])
	set mrac = `gawk '$1=="'$pid'"&&$2=="MRAC"&&$3=='$i' {print $4}' ../dcm_subdir.txt`

	foreach MD ($MDS)
		set md = `echo $MD | gawk '{print tolower($0)}'`
		set newnames = ()
		if ($MD == FDG) then
			set sub = `gawk '$1=="'$pid'"&&$2=="'$MD'"&&$3=='$i' {print $NF}' ../dcm_subdir.txt`
			set s   = `gawk '$1=="'$pid'"&&$2=="'$MD'"&&$3=='$i' {print $4}'  ../dcm_subdir.txt`
			set rawdirname = $rawdir/$dcm"RawData"/*/*/$sub
			set umapdir = $rawdir/$dcm/[Ss]*/$s/DICOM
			set newnames = ($newnames $MD"_v"$i)
		else
			foreach n (`gawk '$1=="'$pid'"&&$2=="'$MD'"&&$4=='$i' {print $3}' ../dcm_subdir.txt`)
				set sub = `gawk '$1=="'$pid'"&&$2=="'$MD'"&&$4=='$i'&&$3=='$n' {print $NF}' ../dcm_subdir.txt`
				set s   = `gawk '$1=="'$pid'"&&$2=="'$MD'"&&$4=='$i'&&$3=='$n' {print $5}'  ../dcm_subdir.txt`
				set rawdirname = $rawdir/$dcm"RawData"/*/*/$sub
				set umapdir = $rawdir/$dcm/[Ss]*/$s/DICOM
				set newnames = ($newnames $MD$n"_v"$i)
			end
		endif

		foreach newname ($newnames)
			set imgname  = `echo $newname | gawk '{print "'$pid'"tolower($1)"_sumall"}'`
			set umapname = `echo $newname | gawk '{print "'$pid'"tolower($1)"_umap"}'`
			#if (! -e $imgname.4dfp.img) then
				if (-d $newname"-Converted") rm -r $newname"-Converted"
				cscript C:/JSRecon12/JSRecon12.js $newname C:/JSRecon12/O15NAC.txt
				sed -i '/Run-05/d' $newname"-Converted"/$newname"-LM-00/Run-99-"$newname"-LM-00-ALL.bat"
				$newname"-Converted"/$newname"-LM-00/Run-99-"$newname"-LM-00-ALL.bat"
				IFhdr_to_4dfp $newname"-Converted"/$newname"-LM-00"/$newname"-LM-00-FBP_000_000.v.hdr" $imgname
				IFhdr_to_4dfp $newname"-Converted"/$newname"-LM-00"/$newname"-LM-00-umap.v.hdr"        $umapname"_e7"
				rm $imgname"fz".* $umapname"_e7fz".*
				find . -name '*sino*.s' -delete
			#endif
		end
	end
	@ i ++
end

popd

exit 0
