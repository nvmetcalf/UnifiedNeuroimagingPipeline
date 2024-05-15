#!/bin/csh
#set echo

set R = /data/nil-bluearc/raichle/ryan/MSC/TESTING

pushd $R
set F = (`ls */*/FCmaps/*atl.dvar.format`)
popd

foreach f ($F[1-40])
	echo $f
	set str = `format2lst -e $R/$f`
	echo $str
	echo
end
