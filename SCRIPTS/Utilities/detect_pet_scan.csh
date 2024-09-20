#!/bin/csh
#detects the scan index of the first valid scan it finds and echo's it
#PET scans have to be detected from the json

set ScansToCheckFor = (`echo "$1"`)
set DicomDir = $2
set Scan = ()
set home = $cwd
cd $DicomDir
	@ i = 1
	#checks the P1.cfg file name string for valid file names
	while($i <= $#ScansToCheckFor)
		
		foreach image(*.nii *.nii.gz)
			set Radiopharmaceutical = `grep Radiopharmaceutical $image:r:r".json" | grep "$ScansToCheckFor[$i]" | awk '{print($2)}' | sed 's/\"//g' | sed 's/,//g'`
			if($#Radiopharmaceutical == 0)then
				set Radiopharmaceutical = `grep ProcedureStepDescription $image:r:r".json" | grep "$ScansToCheckFor[$i]" | awk '{print($2)}' | sed 's/\"//g' | sed 's/,//g'`
			endif
			if($#Radiopharmaceutical != 0) then
				if(`echo $Radiopharmaceutical[1] $ScansToCheckFor[$i] | awk '{if($1 == $2) print("1"); else print("0");}'` == "1") then
					set Scan = ($Scan $image)
				endif
				
			endif
			
		end
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
