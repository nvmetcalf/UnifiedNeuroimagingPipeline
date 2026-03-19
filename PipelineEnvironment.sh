#!/bin/csh

#set the environment variables for everything in the pipeline
#you want to source this script somehow (I call it from the default shell environment script in /etc)

export EDITOR=/usr/bin/nano

#location where the pipeline is living. Will have SCRIPTS, ATLAS, 'PROJECTS_DIR', Scans
export PROJECTS_HOME=/data/nil-bluearc/vlassenko/Pipeline

#location of your scratch space. Usually a high speed storage area that
#	is used to store files that can be easily regenerated via the pipeline.
#	Things like freesurfer segmentations, intermediate BOLD registration, dtseries
#	intermediate steps, etc. are stored here.
export SCRATCH=/data/vglab/data2/temp

#path to the bin folder of where matlab is installed. Uncomment this line if MATLAB_BIN is
#	not set somewhere else before this scripts, such as in a .login file sourced when you
#	log into your system.
#export MATLAB_BIN /usr/local/pkg/MATLAB/R2024a/bin

#below this point you shouldn't HAVE to change any variables or paths, but if you are using different locations for FSL, Freesurfer, Workbench, etc. you may need to

##############################################
#
#	TRY NOT TO BREAK ANYTHING!
#
##############################################

#folder that holds all your projects
export PROJECTS_DIR="Projects"

#path to 711-2* atlases
export REFDIR=${PROJECTS_HOME}/ATLAS/REFDIR

#Path to the Processing Pipeline Scripts
export PP_SCRIPTS=${PROJECTS_HOME}/SCRIPTS

#set where workbench is installed. At one time it was called caret, history is fun.
#adjudicate between debian and rhel versions of workbench.
#if you have workbench installed somewhere else, set the path here.
#these paths assume you're using the version included in the pipeline.
if(`grep debian /etc/os-release` != "") then
	export CARET7DIR=${PP_SCRIPTS}/workbench/debian/bin_linux64
else
	export CARET7DIR=${PP_SCRIPTS}/workbench/rhel/bin_rh_linux64
endif

#Path to shared libraries that the pipelines programs need. Mostly
#4dfp stuff and old fslview
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$PP_SCRIPTS/libs

#path to the nil 4dfp programs/scripts
export RELEASE=${PP_SCRIPTS}/lin64-tools

#path to the source for the nil 4dfp programs - if you need to compile them
export NILSRC=${PP_SCRIPTS}/lin64-nilsrc

# Set up ANTS
export ANTSPATH=$PP_SCRIPTS/ANTs

#path to where freesurfer is located. No subject data will actually be stored there.
#	Freesurfer is included, BUT you will need to get a license file from
#	freesurfer (is free).
export FREESURFER_HOME=${PP_SCRIPTS}/FreesurferVersions/fs_7_4_1
export FSLDIR=${PP_SCRIPTS}/fsl
export FSL_DIR=$FSLDIR

#setup the freesurfer environment
source ${FREESURFER_HOME}/SetUpFreeSurfer.sh
export TEMPDIR=$SCRATCH

#path to where FSL is installed - installer is included in the pipeline

source ${FSLDIR}/etc/fslconf/fsl.sh

# Set up specific environment variables for the HCP Pipeline
export HCPPIPEDIR=${PP_SCRIPTS}/HCP
export HCPPIPEDIR_Templates=${HCPPIPEDIR}/global/templates
export HCPPIPEDIR_Bin=${HCPPIPEDIR}/global/binaries
export HCPPIPEDIR_Config=${HCPPIPEDIR}/global/config
export HCPPIPEDIR_PreFS=${HCPPIPEDIR}/PreFreeSurfer/scripts
export HCPPIPEDIR_FS=${HCPPIPEDIR}/FreeSurfer/scripts
export HCPPIPEDIR_PostFS=${HCPPIPEDIR}/PostFreeSurfer/scripts
export HCPPIPEDIR_fMRISurf=${HCPPIPEDIR}/fMRISurface/scripts
export HCPPIPEDIR_fMRIVol=${HCPPIPEDIR}/fMRIVolume/scripts
export HCPPIPEDIR_tfMRI=${HCPPIPEDIR}/tfMRI/scripts
export HCPPIPEDIR_dMRI=${HCPPIPEDIR}/DiffusionPreprocessing/scripts
export HCPPIPEDIR_dMRITract=${HCPPIPEDIR}/DiffusionTractography/scripts
export HCPPIPEDIR_Global=${HCPPIPEDIR}/global/scripts
export HCPPIPEDIR_tfMRIAnalysis=${HCPPIPEDIR}/TaskfMRIAnalysis/scripts
export MSMBin=${HCPPIPEDIR}/MSMBinaries

#update the path with all the goodies we will use in the future.
export PATH=${PP_SCRIPTS}:${RELEASE}:${HCPPIPEDIR}:${CARET7DIR}:${REFDIR}:${FREESURFER_HOME}/bin:${FREESURFER_HOME}/mni/bin:${FSL_BIN}:${ANTSPATH}/bin:${ANTSPATH}/Scripts:${PP_SCRIPTS}/PET/PUP:${MATLAB_BIN}:${PATH}
