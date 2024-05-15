#!/bin/csh

if(! -e ../Study.cfg) then
	echo "Cannot find ../Study.cfg. Be sure to run this from the Participants, Excluded, or Pending_PI_Review folder."
	exit 1
endif

source ../Study.cfg

set SubjectList = ($1)

set Date = `date | tr '[ ]' '[_]'`

set Output = Exported_QC_${Date}.csv

touch $Output
set AtlasName = `basename $target`

echo "ParticipantID,Non-Linearly Aligned T1 -> ${AtlasName} ETA,Linearly Aligned T1 -> ${AtlasName} ETA,Non-Linearly Aligned T2 -> T1 ETA,Linearly Aligned T2 -> T1 ETA,Non-Linearly Aligned FLAIR -> T1 ETA,Linearly Aligned FLAIR -> T1 ETA,Final Aligned + Distortion Corrected BOLD_ref -> ${AtlasName} ETA,Final Aligned + Distortion Corrected BOLD_ref -> TargetModality ETA,Final Aligned + Distortion Corrected BOLD_ref -> Day1 BOLD_ref,Final Aligned + Distortion Corrected asl1_ref -> ${AtlasName} ETA,Final Aligned + Distortion Corrected asl1_ref -> TargetModality ETA,Non-Linearly T1 Edge Overlap -> ${AtlasName} ,Linearly T1 Edge Overlap -> ${AtlasName},Percent BOLD Remaining,BOLD Time Remaining,BOLD Total Time Remaining,BOLD RMS Movement,Aligned BOLD SD,Denoised BOLD SD" >> $Output

foreach Subject($SubjectList)
	set Line = ($Subject)
	
	echo $Subject
	
	unset mprs
	unset tse
	unset flair
	unset BOLD
	unset ASL
	unset day1_patid
	
	source ${Subject}/${Subject}.params
	
	if(! $?Reg_Target) set Reg_Target = "T2"
	
	#export the ETA's for each transform
	#MPR->NonLinAtl ETA
	if(! -e ${Subject}/Anatomical/Volume/T1/${Subject}_T1_111_fnirt.nii.gz || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Non-Linearly Aligned T1 ->${AtlasName}" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
# 	if($value == "") then
# 		set value = "0"
# 	else if(`echo $value | awk '{if($1 < 0.55) print 0}'` == 0) then
# 		set value = "0"
# 	else
# 		set value = "1"
# 	endif
	
	set Line = ($Line ","$value)
	
	#Linearly Aligned T1 ETA
	if(! -e ${Subject}/Anatomical/Volume/T1/${Subject}_T1_111.nii.gz || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Linearly Aligned T1 ->${AtlasName}" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
# 	if($value == "") then
# 		set value = "0"
# 	else if(`echo $value | awk '{if($1 < 0.44) print 0}'` == 0) then
# 		set value = "0"
# 	else
# 		set value = "1"
# 	endif
	
	set Line = ($Line ","$value)
	
	#Non-Linearly Aligned T2 -> T1 ETA
	if(! -e ${Subject}/Anatomical/Volume/T2/${Subject}_T2_111_fnirt.nii.gz || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Non-Linearly Aligned T2 -> T1" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Linearly Aligned T2 -> T1 ETA
	if(! -e ${Subject}/Anatomical/Volume/T2/${Subject}_T2_111.nii.gz || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Linearly Aligned T2 -> T1" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	
	#Non-Linearly Aligned FLAIR -> T1 ETA
	if(! -e ${Subject}/Anatomical/Volume/FLAIR/${Subject}_FLAIR_111_fnirt.nii.gz || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Non-Linearly Aligned FLAIR -> T1" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Linearly Aligned FLAIR -> T1 ETA
	if(! -e ${Subject}/Anatomical/Volume/FLAIR/${Subject}_FLAIR_111.nii.gz || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Linearly Aligned FLAIR -> T1" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Final Aligned + Distortion Corrected BOLD_ref -> ${AtlasName} ETA
	if(! $?BOLD || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Final Aligned + Distortion Corrected BOLD_ref ->${AtlasName}" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Final Aligned + Distortion Corrected BOLD_ref -> ${Reg_Target} ETA
	if(! $?BOLD || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Final Aligned + Distortion Corrected BOLD_ref ->${Reg_Target}" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Final Aligned + Distortion Corrected BOLD_ref -> Day1 BOLD Ref ETA
	if(! $?BOLD || ! $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Final Aligned + Distortion Corrected BOLD_ref -> ${day1_patid}" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Final Aligned + Distortion Corrected asl1_ref -> ${AtlasName} ETA
	if(! $?ASL || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Final Aligned + Distortion Corrected asl1_ref ->${AtlasName}" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Final Aligned + Distortion Corrected asl1_ref -> ${Reg_Target} ETA
	if(! $?ASL || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Final Aligned + Distortion Corrected asl1_ref ->${Reg_Target}" ${Subject}/QC/ETA.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Non-Linearly T1 Edge Overlap -> ${AtlasName} ETA
	if(! $?mprs || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Non-Linearly T1 Edge Overlap ->${AtlasName}" ${Subject}/QC/EdgeOverlap.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#Linearly T1 Edge Overlap -> ${AtlasName} ETA
	if(! $?mprs || $?day1_patid) then
		set value = "-"
	else
		set value = `grep "Linearly T1 Edge Overlap ->${AtlasName}" ${Subject}/QC/EdgeOverlap.txt | tail -1 | cut -d":" -f2`
	endif
	
	set Line = ($Line ","$value)
	
	#export the runs percent remaining
	if(! $?BOLD) then
		set value = "-"
	else
		set value = ()
		@ i = 2
		@ runs = $#BOLD + 1
		while($i <= $runs)
			set percent = `head -$i ${Subject}/QC/${Subject}_BOLD_frame_count_by_run.txt | tail -1 | awk '{print $4}'`
# 			set usable = "1"
# 			if(`echo $percent 30 | awk '{if($1 < $2) print 0}'` == 0) then
# 				set usable = "0"
# 			endif
			
			set value = ($value " "$percent)
			@ i++
		end
	endif
	
	set Line = ($Line ","$value)
	
	#export the runs time remaining
	if(! $?BOLD) then
		set value = "-"
		set TotalTime = "-"
	else
		set value = ()
		@ i = 2
		@ runs = $#BOLD + 1
		@ TotalTime = 0
		while($i <= $runs)
			set time = `head -$i ${Subject}/QC/${Subject}_BOLD_frame_count_by_run.txt | tail -1 | awk '{print $5}'`
# 			set usable = "1"
# 			if(`echo $percent 30 | awk '{if($1 < $2) print 0}'` == 0) then
# 				set usable = "0"
# 			endif

			if($time != "") @ TotalTime += $time
			
			set value = ($value " "$time)
			@ i++
		end
	endif
	
	set Line = ($Line ","$value)
	set Line = ($Line ","$TotalTime)
	
	#export the rms movement
	if(! $?BOLD) then
		set value = "-"
	else
		set value = ()
		@ i = 1
		while($i <= $#BOLD)
			set rms = `head -$i ${Subject}/QC/RMS_movements.txt | tail -1 | awk '{print $7}'`
# 			set usable = "1"
# 			if(`echo $percent 30 | awk '{if($1 < $2) print 0}'` == 0) then
# 				set usable = "0"
# 			endif
			
			set value = ($value " "$rms)
			@ i++
		end
	endif
	
	set Line = ($Line ","$value)
	
	#export the mean sd before denoising
	if(! $?BOLD) then
		set value = "-"
	else
		set value = `head -1 ${Subject}/QC/fMRI_denoising.txt | tail -1 | cut -d":" -f2`
	endif

	set Line = ($Line ","$value)
	
	#export the mean sd after denoising
	if(! $?BOLD) then
		set value = "-"
	else
		set value = `head -2 ${Subject}/QC/fMRI_denoising.txt | tail -1 | cut -d":" -f2`
	endif

	set Line = ($Line ","$value)
	
	echo $Line >> $Output
end
