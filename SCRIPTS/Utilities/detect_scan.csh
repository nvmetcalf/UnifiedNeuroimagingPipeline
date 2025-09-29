#!/bin/csh

#detects the scan index of the first valid scan it finds and echo's it
if($#argv == 2) then
	set ScansToCheckFor = (`echo "$1"`)
	set ScansToExclude = ()
	set DicomDir = $2
else
	set ScansToCheckFor = (`echo "$1"`)
	set ScansToExclude = (`echo "$2"`)
	set DicomDir = $3
endif

set Scan = ()
set home = $cwd

cd $DicomDir

@ i = 1
#checks the P1.cfg file name string for valid file names
while($i <= $#ScansToCheckFor)
	set query = (`ls *.nii *.nii.gz | grep "$ScansToCheckFor[$i]"`)
	if($#query > 0) then
		set Scan = (`echo $Scan $query`)
	endif
	@ i++
end

#go through the list of strings to exlude and remove the files from the list that have them
@ i = 1
while($i <= $#ScansToExclude)
	set Scan = (`echo $Scan | tr " " "\n" | grep -v $ScansToExclude[$i] | tr "\n" " "`)
	@ i++
end

cd $home

#check the scan list to make sure there arent any duplicates

set DedupedList = ()

foreach Image($Scan)
	@ unique = 1
	foreach Check($DedupedList)
		if($Image == $Check) then
			@ unique = 0
			break
		endif
	end

	if($unique) then
		set DedupedList = ($DedupedList $Image)
	endif
end

echo $DedupedList
