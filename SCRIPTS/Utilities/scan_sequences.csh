#!/bin/csh

#scan the given folder for subfolders
#make a list and proceed recursively through all sub folders
#for each folder found with dicoms, link them to the given location

set SubjectID = $1
set DestinationFolder = $2

set DCM_ROOT = ${1}".HEAD.MR"	#this is what we will put in front of the dicom files

#oof, this is gonna be different
pushd ${cwd}/${1}
	set CurrDir = `pwd`
	set FolderList = (`find ${CurrDir} -type d -ls | awk '{printf $11" "}'`) #list of all folders found
popd

# rm test.txt
# touch test.txt
# set home = $cwd

#iterate through our list and find the folders with dcm or ima
foreach Folder($FolderList)
	pushd $Folder
		set FileList = (`ls *.ima *.IMA *.dcm *.DCM *.*.*[0-9]`)
		
		#if no files, goto the next one
		if($#FileList == 0) continue
		
		#determine how many fields we have
		
		@ NumberOfFields = 1
		while(`echo $FileList[1] | cut -d. -f${NumberOfFields}` != "")
			@ NumberOfFields++
		end
		
		#went one too far, too lazy to make this better
		@ NumberOfFields--
		
		#echo "Number of Fields = $NumberOfFields"
		
		#now see when the sequence numbering starts
		@ SequenceStartField = 2
		while(`echo $FileList[1] | head -1 | cut -d. -f${SequenceStartField} | grep '^[0-9]*$'` == "")
			@ SequenceStartField++
		end
		
		#make a string for the fields that will be appended to the dcmroot
		set Fields = "$SequenceStartField"
		@ SequenceStartField++ #progress 1 as we know there must be at least 1 field
		
		while($SequenceStartField <= $NumberOfFields)
			set Fields = ${Fields}","${SequenceStartField}
			@ SequenceStartField++
		end
		
		#echo "Fields to append to dcm root = $Fields"
		
		@ NextToLastField = $NumberOfFields - 1
		foreach Record(${FileList})
		
			#so... because the cnda changed the order of its filename fields, we now
			#need to check the nexto to last field for if it has hyphens... if so
			#then we need to parse it and attach it to the front of the suffix...
			if(`echo $Record | cut -d. -f${NextToLastField} | grep "-"` != "") then
				#pull out the next to last field and break it into the sequence number and image number
				set CNDA_seq_scan = `echo $Record | cut -d. -f${NextToLastField}`
				set sequence = `echo $CNDA_seq_scan | cut -d"-" -f2`
				#echo $sequence
				
				set scan = `echo $CNDA_seq_scan | cut -d"-" -f3`
				#echo $scan
				
				set suffix = `echo $Record | tr -cd 'A-Za-z0-9.' | cut -d. -f${Fields}`
				#echo $suffix
				
				set FILE_SUFFIX = ${sequence}"."${scan}"."${suffix}
			else
				set FILE_SUFFIX = `echo $Record | tr -cd 'A-Za-z0-9.' | cut -d. -f${Fields}`
			endif
			
			#echo ${FILE_SUFFIX}
			
			set FILE = ${DCM_ROOT}.${FILE_SUFFIX}
 			#echo "ln -s ${cwd}/${Record} ${DestinationFolder}/${SubjectID}/dicom/${FILE}" >> ${home}/test.txt
 			
			ln -s ${cwd}/${Record} ${DestinationFolder}/${SubjectID}/dicom/${FILE}
		end
		
	popd
end




