#!/bin/csh

#detects the scan index of the first valid scan it finds and echo's it
set ScansToCheckFor = (`echo "$1"`)
set DicomDir = $2
set Scan = ()
set home = $cwd
cd $DicomDir
	@ i = 1
	#checks the P1.cfg file name string for valid file names
	while($i <= $#ScansToCheckFor)
# 		if($ScansToCheckFor[$i]:r != "") then
			set query = (`ls *.nii *.nii.gz | grep "$ScansToCheckFor[$i]"`)
# 		else
# 			#if a . was found in the file name string (denoting a file extension to look for)
# 			#then we will look for files that match that file extension and then put the
# 			#nifti image in it's place that are found
# 			set temp = `ls *$ScansToCheckFor[$i]`
# 			set query = ()
# 			foreach file($temp)
# 				if(-e $file:r".nii.gz") then
# 					set query = ($query $file:r".nii.gz")
# 				else if(-e $file:r".nii") then
# 					set query = ($query $file:r".nii")
# 				endif
# 			end
# 		endif
		
		if($#query > 0) then
			set Scan = (`echo $Scan $query`)
		endif
		
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
