#!/bin/csh

set PythonBin = ${FSLBIN}/python3.11
set ExecutionPath = ${PP_SCRIPTS}/python3/ProjectManager
set Operations = ( "manage run download sync analyze" )

#source the echo formatting variables
source $PP_SCRIPTS/Utilities/echo_format_variables
if($status) then
	echo "ERROR: Could not source echo_format_variables!"
	exit 1
endif

if($#argv == 0) then
    echo "################### ${BLUE_F}USAGE${NORMAL} ######################"
    echo ""
    echo "ProjectManager "\""<operation to execute>"\"" [options]"
    echo "Allowed Operations: ${Operations}"
    echo ""
    echo "################################################"
	exit 1
endif

set OperationTaken = ${argv[1]}
set OperationArguments = () 

# Initialize the counter variable
@ i = 2
while ($i <= $#argv)
    set OperationArguments = ($OperationArguments \"${argv[$i]}\")
    @ i++
end

set Valid = 0
foreach Op ($Operations)
    if ($Op == $OperationTaken) then
        set Valid = 1
    endif
end

if (! $Valid) then
    echo "The operation ${OperationTaken} is not valid. Please enter a valid operation or specify no options for help."
    exit 1
endif

#Ensure that the path is correct.
set ScriptPath = `readlink -f $0`
set CurrentPath = $cwd
cd `dirname ${ScriptPath}`
eval "$PythonBin ${ExecutionPath}/${OperationTaken}.py --execution_path ${CurrentPath} ${OperationArguments}"
