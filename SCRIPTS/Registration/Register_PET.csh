#!/bin/csh

source $1
source $2
set echo
set SubjectHome = $cwd

if(! -e Anatomical/Volume) mkdir -p Anatomical/Volume

set Costs = (corratio normmi mutualinfo normcorr leastsq)

echo "Computing average PET modalities..."
cd PET/Volume
	#register within modality images together and average
	#register each average to the T1 via some registration chain set in the params file
	#register each scan within a modality to itself and average
	foreach Modality(FDG H2O CO O2 PIB TAU FBX)		
		#get a list of all the files in this modality
		set Files = (`ls ${Modality}_*_sum_deco.nii.gz`)
		
		echo "Found Images for ${Modality}:" $Files
		if($#Files == 0) then
			continue
		endif
		
		rm -r ${SubjectHome}/Anatomical/Volume/${Modality}
		mkdir ${SubjectHome}/Anatomical/Volume/${Modality}
		if($#Files > 1) then
			#register them all to the first one in the list
			@ i = 2
			while($i <= $#Files)
				flirt -in $Files[$i] -ref $Files[1] -out $Files[$i]:r:r"_reg.nii.gz" -dof 6 #-interp nearestneighbour
				if($status) exit 1
				
				@ i++
			end
			
			#take the within modality registratio target and everything registered to it and stack them.
			fslmerge -t temp $Files[1] `ls ${Modality}_*_sum_deco_reg.nii.gz`
			if($status) exit 1
			
			fslmaths temp -Tmean ${SubjectHome}/Anatomical/Volume/${Modality}/${patid}_${Modality}".nii.gz"
			if($status) exit 1
			
			rm temp.*
		else
			#for consistency copy the averages to anatomical.
			cp $Files ${SubjectHome}/Anatomical/Volume/${Modality}/${patid}_${Modality}".nii.gz"
		endif
	end
cd ../..


echo "Computing registrations for all PET modalities..."
#for each modality that exists, iterate through the registration chain for it, computing them as needed
cd ${SubjectHome}/Anatomical/Volume
foreach Modality(FDG H2O O2 CO PIB TAU FBX)
	if(! -e $Modality) continue
	
	cd $Modality
	
		@ CostIndex = 1
		
		while($CostIndex <= $#Costs)
			if($Modality == "FDG") then
				set PET_RegMethod = $FDG_RegMethod
			else if($Modality == "H2O") then
				set PET_RegMethod = $H2O_RegMethod
			else if($Modality == "CO") then
				set PET_RegMethod = $CO_RegMethod
			else if($Modality == "O2") then
				set PET_RegMethod = $O2_RegMethod
			else if($Modality == "PIB") then
				set PET_RegMethod = $PIB_RegMethod
			else if($Modality == "TAU") then
				set PET_RegMethod = $TAU_RegMethod
			else if($Modality == "FBX") then
				set PET_RegMethod = $FBX_RegMethod
			endif
		
			if($Costs[$CostIndex] == $PET_RegMethod) then
				break;
			endif
			
			@ CostIndex++
		end
		
		if($Modality == "FDG") then
			set RegChain = ($FDG_Target FDG)
		else if($Modality == "H2O") then
			set RegChain = ($H2O_Target H2O)
		else if($Modality == "CO") then
			set RegChain = ($CO_Target CO)
		else if($Modality == "O2") then
			set RegChain = ($O2_Target O2)
		else if($Modality == "PIB") then
			set RegChain = ($PIB_Target PIB)
		else if($Modality == "TAU") then
			set RegChain = ($TAU_Target TAU)
		else if($Modality == "FBX") then
			set RegChain = ($FBX_Target FBX)
		else
			echo "Unknown modality $Modality"
			exit 1
		endif
			
		set SmoothingFWHM = 3
		if($Modality == "FDG") then
			@ SmoothingFWHM = $FDG_Smoothing
			set PET_RegMethod = $FDG_RegMethod
		else if($Modality == "H2O") then
			@ SmoothingFWHM = $H2O_Smoothing
			set PET_RegMethod = $H2O_RegMethod
		else if($Modality == "CO") then
			@ SmoothingFWHM = $CO_Smoothing
			set PET_RegMethod = $CO_RegMethod
		else if($Modality == "O2") then
			@ SmoothingFWHM = $O2_Smoothing
			set PET_RegMethod = $O2_RegMethod
		else if($Modality == "PIB") then
			@ SmoothingFWHM = $PIB_Smoothing
			set PET_RegMethod = $PIB_RegMethod
		else if($Modality == "TAU") then
			@ SmoothingFWHM = $TAU_Smoothing
			set PET_RegMethod = $TAU_RegMethod
		else if($Modality == "FBX") then
			@ SmoothingFWHM = $FBX_Smoothing
			set PET_RegMethod = $FBX_RegMethod
		endif
		
		@ i = $#RegChain
			
		set RegistrationMats = ()
		while($i > 1)
			@ j = $i - 1
				
			set NextLevel = 0
			
			set FoundParameters = 0
			
			#remember these for when we update the params file
			set StartingSmoothinhFWHM = $SmoothingFWHM
			set StartingRegMethod = $PET_RegMethod
			
			if(! -e ${SubjectHome}/Anatomical/Volume/$RegChain[$j]/${patid}_$RegChain[$j].nii.gz && $?day1_path ) then
				set TargetHome = $day1_path
				set TargetPatid = $day1_patid
			else
				set TargetHome = $SubjectHome
				set TargetPatid = $patid
			endif
				
			while(! $FoundParameters)
			
				if(! -e ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j]".mat") then
					#do the forward registration
					set SmoothingSigma = `echo $SmoothingFWHM | awk '{print($1/2.3548);}'`
					
					#smooth the image to help with registration
					fslmaths ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i] -kernel gauss $SmoothingSigma -fmean ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM}
					if($status) exit 1
									
					set TargetSmoothingFWHM = "1"
					
					if( ! $?PET_RegMethod) then
						set PET_RegMethod = corratio
					endif
					
					set Method = "-searchcost $PET_RegMethod -cost $PET_RegMethod"
					
					if($RegChain[$j] == "FDG") then
						set TargetSmoothingFWHM = $FDG_Smoothing
					else if($RegChain[$j] == "H2O") then
						set TargetSmoothingFWHM = $H2O_Smoothing
					else if($RegChain[$j] == "CO") then
						set TargetSmoothingFWHM = $CO_Smoothing
					else if($RegChain[$j] == "O2") then
						set TargetSmoothingFWHM = $O2_Smoothing
					else if($RegChain[$j] == "PIB") then
						set TargetSmoothingFWHM = $PIB_Smoothing
					else if($RegChain[$j] == "TAU") then
						set TargetSmoothingFWHM = $TAU_Smoothing
					else if($RegChain[$j] == "FBX") then
						set TargetSmoothingFWHM = $FBX_Smoothing
					endif
					set TargetSmoothingSigma = `echo $SmoothingFWHM | awk '{print($1/2.3548);}'`
					
					if(! -e ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM}.nii.gz) then
						
						fslmaths ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j] -kernel gauss $TargetSmoothingSigma -fmean ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM}
						if($status) exit 1
					endif
					
					flirt -in ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM} -ref ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM} -out ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j] -omat ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j]".mat" -dof 6 $Method #-coarsesearch 30 -finesearch 9 #-interp nearestneighbour
					if($status) exit 1
					
					#see if we want to check how far a voxel displaces
					if($MaximumRegDisplacement != 0) then
						#do the backwards registration
						
						flirt -in ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM} -ref ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm${SmoothingFWHM}" -omat ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${TargetPatid}_$RegChain[$j]"_to_"${patid}_$RegChain[$i]"_rev.mat" -dof 6 $Method #-coarsesearch 30 -finesearch 9 #-interp nearestneighbour
						if($status) exit 1
						
						set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i] ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j] ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j].mat ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${TargetPatid}_$RegChain[$j]"_to_"${patid}_$RegChain[$i]"_rev.mat" 0 50 0`
						decho "2 way registration displacement: $Displacement" ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${patid}_$RegChain[$j]_displacement.txt
						
						if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i] ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j] ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j].mat ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${TargetPatid}_$RegChain[$j]"_to_"${patid}_$RegChain[$i]"_rev.mat" 0 50 0 $MaximumRegDisplacement`) then
							decho "	Registration from $RegChain[$i] to $RegChain[$j] and $RegChain[$j] to $RegChain[$i] has a displacement of "$Displacement
							decho "		Trying with masking..."
							
							if(! -e ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM}_brain.nii.gz) then
								bet ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM} ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM}_brain -f 0.5 -R
								if($status) exit 1
								
								fslmaths ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM} -thr `fslstats ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM}_brain -P 50` ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM}_brain
								if($status) exit 1
							endif
							
							if(! -e ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM}_brain.nii.gz) then
								bet ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM} ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM}_brain -f 0.5 -R
								if($status) exit 1
								
								fslmaths ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM} -thr `fslstats ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM}_brain -P 50` ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM}_brain
								if($status) exit 1
								
							endif
							
							set TargetBrain = ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j]"_sm"${TargetSmoothingFWHM}_brain
							
							flirt -in ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm"${SmoothingFWHM}_brain -ref $TargetBrain -out ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j] -omat ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j]".mat" -dof 6 $Method #-coarsesearch 30 -finesearch 9 #-interp nearestneighbour
							if($status) exit 1
							
							flirt -in $TargetBrain -ref ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_sm${SmoothingFWHM}"_brain -omat ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${TargetPatid}_$RegChain[$j]"_to_"${patid}_$RegChain[$i]"_rev.mat" -dof 6 $Method #-coarsesearch 30 -finesearch 9 #-interp nearestneighbour
							if($status) exit 1
							
							set Displacement = `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i] ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j] ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j].mat ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${TargetPatid}_$RegChain[$j]"_to_"${patid}_$RegChain[$i]"_rev.mat" 0 50 0`
							decho "Brain Masked 2 way registration displacement: $Displacement" ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${patid}_$RegChain[$j]_displacement.txt
							
							if(! `$PP_SCRIPTS/Utilities/IsRegStable.csh ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i] ${TargetHome}/Anatomical/Volume/$RegChain[$j]/${TargetPatid}_$RegChain[$j] ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j].mat ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${TargetPatid}_$RegChain[$j]"_to_"${patid}_$RegChain[$i]"_rev.mat" 0 50 0 $MaximumRegDisplacement`) then
								decho "	Error: Registration from $RegChain[$i] to $RegChain[$j] and $RegChain[$j] to $RegChain[$i] has a displacement of "$Displacement
								set NextLevel = 1
							endif
						endif
						
					endif
					rm ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]_sm${SmoothingFWHM}.nii*
					
				endif
				
				if($NextLevel) then
					#since the registration failed, see if we can increase the smoothing
					#if not, reset the smoothing and try the next cost function
					if($SmoothingFWHM >= 8 && $CostIndex < $#Costs) then
						@ CostIndex++
						@ SmoothingFWHM = $StartingSmoothinhFWHM
						decho "Unable to find a smoothing fwhm for cost function $PET_RegMethod for $RegChain[$i] to $RegChain[$j] and $RegChain[$j] to $RegChain[$i]!"
						set PET_RegMethod = $Costs[$CostIndex]	#progress to the next cost function  with the same current smoothing
						decho "	Trying next cost function: $PET_RegMethod"
					else if($SmoothingFWHM < 8 && $CostIndex <= $#Costs) then
						@ SmoothingFWHM++	#move to the next smoothing level
						decho "Increasing smoothing to $SmoothingFWHM"
					else
						#we have exhausted our search, bail out.
						decho "Unable to find a smoothing and cost function combination from $RegChain[$i] to $RegChain[$j] and $RegChain[$j] to $RegChain[$i]"
						exit 1
					endif
					#remove what we did and try again.
					rm ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j]".mat"
					set NextLevel = 0
				else
					#we succeeded in a good registration, update the params file
					set FoundParameters = 1
					decho "Found good registration parameters: $SmoothingFWHM mm and $PET_RegMethod cost. Updating params file."
			
					cat ${SubjectHome}/$1 | sed 's/set '$RegChain[$i]'_Smoothing = '$StartingSmoothinhFWHM'/set '$RegChain[$i]'_Smoothing = '$SmoothingFWHM'/g' >! temp
					cat temp | sed 's/set '$RegChain[$i]'_RegMethod = '$StartingRegMethod'/set '$RegChain[$i]'_RegMethod = '$PET_RegMethod'/g' >! ${SubjectHome}/$1
					
					#build the list of matrices we will need
					set RegistrationMats = ($RegistrationMats ${SubjectHome}/Anatomical/Volume/$RegChain[$i]/${patid}_$RegChain[$i]"_to_"${TargetPatid}_$RegChain[$j]".mat")
					@ i--
				endif
			end
		end
		
		#set the final T1 target to what the day1 target is
		if($?day1_path) then
			set TargetPatid = $day1_patid
		endif
		
		if($#RegistrationMats > 1) then
			#create out one step resample matrix from the list
			@ i = 1
			while($i < $#RegistrationMats)
				@ j = $i + 1
				if($i == 1) then
					set AtoB = $RegistrationMats[$i]
				else
					set AtoB = curr_reg.mat
				endif
				
				set BtoC = $RegistrationMats[$j]
				convert_xfm -omat temp.mat -concat $BtoC $AtoB
				if($status) exit 1
				
				mv temp.mat curr_reg.mat
				@ i++
			end
		
			mv curr_reg.mat ${SubjectHome}/Anatomical/Volume/${Modality}/${patid}_${Modality}_to_${TargetPatid}_T1.mat
		endif
		
		flirt -in ${patid}_${Modality} -ref ${TargetHome}/Anatomical/Volume/T1/${TargetPatid}_T1 -out ${patid}_${Modality}_to_${TargetPatid}_T1 -init ${SubjectHome}/Anatomical/Volume/${Modality}/${patid}_${Modality}_to_${TargetPatid}_T1.mat -applyxfm #-interp nearestneighbour
		if($status) exit 1
		
		set SmoothingFWHM = 1
		if($Modality == "FDG") then
			set SmoothingSigma = `echo $FDG_Smoothing | awk '{print($1/2.3548);}'`
		else if($Modality == "H2O") then
			set SmoothingSigma = `echo $H2O_Smoothing | awk '{print($1/2.3548);}'`
		else if($Modality == "CO") then
			set SmoothingSigma = `echo $CO_Smoothing | awk '{print($1/2.3548);}'`
		else if($Modality == "O2") then
			set SmoothingSigma = `echo $O2_Smoothing | awk '{print($1/2.3548);}'`
		else if($Modality == "PIB") then
			set SmoothingSigma = `echo $PIB_Smoothing | awk '{print($1/2.3548);}'`
		else if($Modality == "TAU") then
			set SmoothingSigma = `echo $TAU_Smoothing | awk '{print($1/2.3548);}'`
		else if($Modality == "FBX") then
			set SmoothingSigma = `echo $FBX_Smoothing | awk '{print($1/2.3548);}'`
		else
			set SmoothingSigma = "0"
		endif
		
		if($SmoothingSigma != "0") then
			fslmaths ${patid}_${Modality}_to_${TargetPatid}_T1 -kernel gauss $SmoothingSigma -fmean ${patid}_${Modality}_to_${TargetPatid}_T1
			if($status) exit 1
		endif
	cd ..

end

exit 0
###############################
