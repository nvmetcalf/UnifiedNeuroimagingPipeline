#!/bin/csh

#setup and run the cross bold processing

#source params file
source $1

#source processing parameters
source $2

if (! -e $1) then
	echo "$1 not found!"
	exit 1
endif

if (! -e $2) then
	echo "$2 not found!"
	exit 1
endif

#set default parameters if they haven't been set yet
if(! $?BoldDirName) set BoldDirName = "bold"

#goto SKIP_CLEAN
decho "Removing any existing Anatomical Processing" ${DebugFile}
#rm -fr Anatomical/Volume/*

#removes the bold folders and links
if($?RunIndex && -e $ScratchFolder/${patid}) then
	decho "Removing any existing BOLD processing for bolds $RunIndex." ${DebugFile}
	rm -rf Functional/Volume/* 	
endif

if($?ScratchFolder && -e $ScratchFolder/${patid}) then
	decho "Using Scratch Space. Cleaning old results (if any)." ${DebugFile}
	pushd $ScratchFolder/${patid}
		rm -rf ${BoldDirName}*
	popd
endif

rm -rf ${BoldDirName}*

SKIP_CLEAN:

## Only feed in what the dicom log says are bold runs. Else an error will occur
decho "	Running Anatomical Alignment" ${DebugFile}

##################################
##
## Actually Run Imageery Registration
##
##################################

echo "running registration"
${PP_SCRIPTS}/Registration/Register_MRI.csh $ParamsFile $2 >> ${DebugFile}

if($status) then
	decho "		Error: Register_MRI did not execute correctly!" >> ${DebugFile}
	tail -10 ${DebugFile}
	exit 1
endif

decho "		Finished." ${DebugFile}
exit 0
