#!/bin/csh

#this will propagate a set of subjects to the designated location
#this is a custom version of propagate_scans that only propagates 
#a single scan given a source location
if(${#argv} != 4) then
	echo "************************************************"
	echo "**                                                                             "
	echo "**                propagate Scans Usage                 	  "
	echo "**															  "
	echo "**	cutsom_propagate.csh <Subject_ID> <Session_ID> <Source_Location> <Target_Study_Name>"
	echo "**															  "
    echo "**    This is a custom version of propagate_scans. It takes a "
    echo "**    specific directory containing raw data and propagates it "
    echo "**    into Target_Study_Name.                               "
	echo "**"
	echo "************************************************"

	exit 1
endif

set SubjectID = "sub-${1}_ses-${2}"
set Source_Location = ${3}
set Target_Study = ${4}

set Destination = ${PROJECTS_HOME}/${PROJECTS_DIR}/${Target_Study}

#move to where the scans are - means we can run this from basically anywhere
pushd ${PROJECTS_HOME}/Scans

set DebugFile = $Destination/propagate_scans_`date | tr '[ ]' '[_]'`.txt

if(! -d ${Target_Study} && $#argv == 1) then
	echo "The scan folder ${Target_Study} does NOT exist. Do you wish to create it? (yes/no)"
	set Create = $<

	if($Create == "yes" || $Create == "y" || $Create == "Y") then
		echo "Creating scan file structure."

		mkdir ${Target_Study}

	else if($Create == "no" || $Create == "n" || $Create == "N") then
		echo "User does not want the Study created. Aborting..."
		exit 1
	else
		echo "	Enter only yes or no"
		exit 1
	endif
endif

if(! -e ${Source_Location}) then
    echo "${Source_Location} does not exist in ${PROJECTS_HOME}/Scans..."
    exit 1
endif

decho "Propagating ${Source_Location} into ${Target_Study}..."

if(! -d ${Destination}) then
	echo "The project folder ${Target_Study} does NOT exist. Do you wish to create it? (yes/no)"
	set Create = $<

	if($Create == "yes" || $Create == "y" || $Create == "Y") then
		decho "Creating Study file structure."
		
		if(! -e ${Destination}) then
			mkdir ${Destination}
			chmod -Rf 775 $Destination
			
			decho "	Making Project Directory" $DebugFile
		endif

		if(! -e ${SCRATCH}/${Target_Study}) then
			decho "	Making Scratch Directory" $DebugFile
			mkdir ${SCRATCH}/${Target_Study}
			chmod -Rf 775 ${SCRATCH}/${Target_Study}
		endif
		
		if(! -e ${Destination}/Participants) then
			decho "	Making Participants Directory" $DebugFile
			mkdir ${Destination}/Participants
			chmod -Rf 775 ${Destination}/Participants
		endif

		if(! -e ${Destination}/Analysis) then
			decho "	Making Analysis Directory" $DebugFile
			mkdir ${Destination}/Analysis
			chmod -Rf 775 ${Destination}/Analysis
		endif

		if(! -e ${Destination}/Excluded) then
			decho "	Making Excluded Subjects Directory" $DebugFile
			mkdir ${Destination}/Excluded
			chmod -Rf 775 ${Destination}/Excluded
		endif

		if(! -e ${Destination}/InProcess) then
			decho "	Making InProcess Directory" $DebugFile
			mkdir ${Destination}/InProcess
			chmod -Rf 775 ${Destination}/InProcess
		endif
	else if($Create == "no" || $Create == "n" || $Create == "N") then
		decho "User does not want the Study created. Aborting..." $DebugFile
		exit 1
	else
		decho "	Enter only yes or no"
		exit 1
	endif
endif

#If the old Pending_PI_Review folder exists, use that instead of InProcess
if(-e ${Destination}/Pending_PI_Review) then
	set ProcessingFolder = "Pending_PI_Review"
else
	set ProcessingFolder = "InProcess"
endif
	
#see if we need to configure the study
if(! -e ${Destination}/Study.cfg) then
	decho "This study appears to not be configured yet. Please enter the configuration informations as prompted." 
	decho ""

	config_study ${Target_Study}
endif

decho "Loading Study Configuration..." $DebugFile
source ${Destination}/Study.cfg

#collect a list of folders that exist in the destination study.
#We will need to search through these to find out if the subject
#has been propagated already.
pushd $Destination
	set StudyFolders = (`ls`)
popd

#Go into the Source folder in Scans for this session.
pushd ${Source_Location}

    set Source = ${cwd}
    foreach DestStdFolder($StudyFolders)
        if(-e ${Destination}/${DestStdFolder}/${SubjectID}) then
            decho "	Subject ${SubjectID} exists in the destination ${DestStdFolder}. Exiting..." $DebugFile
            exit 1
        endif
    end

    decho "Propagating ${Target_Study}/${SubjectID} into the study..." $DebugFile
    mkdir ${Destination}/${ProcessingFolder}/${SubjectID}
    mkdir ${Destination}/${ProcessingFolder}/${SubjectID}/dicom

    decho $cwd
        
    set ImageFileList = (`find . -type f -name "*.nii*"`)
    set JsonFileList = (`find . -type f -name "*.json"`)
    set bvecFileList = (`find . -type f -name "*.bvec"`)
    set bvalFileList = (`find . -type f -name "*.bval"`)

    if($#ImageFileList == 0 || $#JsonFileList == 0) then
        #make a pseudo bids structure
        decho "No BIDS nifti or json files found. Attempting to find dicoms and create pseudo BIDS structure." $DebugFile
        rm -f BIDS_Conversion.log
        mkdir DICOMS
        mv * DICOMS
        rm -rf BIDS
        
        set ItemList = (`find . -type l`)
        
        if($#ItemList == 0) then
            set ItemList = (`find . -type f`)
        endif
        
        mkdir $SubjectID
        
        foreach Item($ItemList)
            ln -s ${cwd}/$Item $SubjectID/`basename $Item`
            
        end
        
        mkdir BIDS
        $RELEASE/dcm2niix -o BIDS -z y -v y -ba n $SubjectID >! BIDS_Conversion.log
        if($status) then
            decho "BIDS conversion failed. Attempting without compression..." $DebugFile
            $RELEASE/dcm2niix -o BIDS -z n -v 1 -ba n $SubjectID >! BIDS_Conversion.log
            if($status) then
                decho "dcm2niix failed again. You will need to do a manual BIDS conversion using some other means."  $DebugFile
                
            endif	
        endif
        
        cd BIDS
            rm -r *_i?????.* *T1w*_e?.* *T2w*_e?.* *_setter_*
            foreach file(*.*)
                set stripped = `echo "$file" | sed 's/\[//g' | sed 's/\]//g' | sed 's/(//g' | sed 's/)//g'`
                if("$stripped" != "$file") then
                    mv "${file}" "${stripped}"
                endif
            end
            
        cd ..
        
        rm -r $SubjectID
        decho $cwd
        set ImageFileList = (`find . -type f -name "*.nii*"`)
        set JsonFileList = (`find . -type f -name "*.json"`)
        set bvecFileList = (`find . -type f -name "*.bvec"`)
        set bvalFileList = (`find . -type f -name "*.bval"`)
        
    endif

    if($#ImageFileList > 0 && $#JsonFileList > 0) then
        decho "Found nifti and json, assuming pseudo BIDS structure" $DebugFile

        foreach File($ImageFileList)
        
            ln -s ${cwd}/$File ${Destination}/${ProcessingFolder}/${SubjectID}/dicom/`basename ${File}`
        end	
            
        foreach File($JsonFileList)
            ln -s ${cwd}/$File ${Destination}/${ProcessingFolder}/${SubjectID}/dicom/`basename ${File}`
        end
        
        foreach File($bvecFileList)
            ln -s ${cwd}/$File ${Destination}/${ProcessingFolder}/${SubjectID}/dicom/`basename ${File}`
        end
        
        foreach File($bvalFileList)
            ln -s ${cwd}/$File ${Destination}/${ProcessingFolder}/${SubjectID}/dicom/`basename ${File}`
        end
        
    else 
        decho "Unable to find BIDS compliant images and jsons" $DebugFile
        decho "Undoing changes..." $DebugFile
        rm -r ${Destination}/${ProcessingFolder}/${SubjectID}
        
    endif

    if($TargetAtlas != "-1") then
        pushd ${Destination}/${ProcessingFolder}
            decho "Running P1"  $DebugFile
            P1 ${SubjectID} ${TargetAtlas}
        popd
    endif
popd

decho "Propagation Complete."  $DebugFile
exit 0
