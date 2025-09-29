#!/bin/csh

#set the environment variables for everything in the pipeline
#you want to source this script somehow (I call it from the default shell environment script in /etc)

setenv EDITOR   /usr/bin/nano

#location where the pipeline is living. Will have SCRIPTS, ATLAS, 'PROJECTS_DIR', Scans
setenv PROJECTS_HOME /path/to/where/you/checked/out/repo

#location of your scratch space. Usually a high speed storage area that
#	is used to store files that can be easily regenerated via the pipeline.
#	Things like freesurfer segmentations, intermediate BOLD registration, dtseries
#	intermediate steps, etc. are stored here.
setenv SCRATCH /path/to/where/you/temp/files/go

#path to the bin folder of where matlab is installed. Uncomment this line if MATLAB_BIN is
#	not set somewhere else before this scripts, such as in a .login file sourced when you
#	log into your system.
#setenv MATLAB_BIN /usr/local/pkg/MATLAB/R2024a/bin

#below this point you shouldn't HAVE to change any variables or paths, but if you are using different locations for FSL, Freesurfer, Workbench, etc. you may need to

##############################################
#
#	TRY NOT TO BREAK ANYTHING!
#
##############################################

#folder that holds all your projects
setenv PROJECTS_DIR "Projects"

#path to 711-2* atlases
setenv REFDIR ${PROJECTS_HOME}/ATLAS/REFDIR

#Path to the Processing Pipeline Scripts
setenv PP_SCRIPTS ${PROJECTS_HOME}/SCRIPTS

#set where workbench is installed. At one time it was called caret, history is fun.
#adjudicate between debian and rhel versions of workbench.
#if you have workbench installed somewhere else, set the path here.
#these paths assume you're using the version included in the pipeline.
if(`grep debian /etc/os-release` != "") then
	setenv CARET7DIR ${PP_SCRIPTS}/workbench/debian/bin_linux64
else
	setenv CARET7DIR ${PP_SCRIPTS}/workbench/rhel/bin_rh_linux64
endif

#path to the nil 4dfp programs/scripts
setenv RELEASE ${PP_SCRIPTS}/lin64-tools

#path to the source for the nil 4dfp programs - if you need to compile them
setenv NILSRC ${PP_SCRIPTS}/lin64-nilsrc

# Set up ANTS
setenv ANTSPATH $PP_SCRIPTS/ANTs

#path to where freesurfer is located. No subject data will actually be stored there.
#	Freesurfer is included, BUT you will need to get a license file from
#	freesurfer (is free).
setenv FREESURFER_HOME ${PP_SCRIPTS}/FreesurferVersions/fs_7_4_1
setenv FSLDIR ${PP_SCRIPTS}/fsl
setenv FSL_DIR $FSLDIR

#setup the freesurfer environment
source ${FREESURFER_HOME}/SetUpFreeSurfer.csh
setenv TEMPDIR $SCRATCH

#path to where FSL is installed - installer is included in the pipeline

source ${FSLDIR}/etc/fslconf/fsl.csh

# Set up specific environment variables for the HCP Pipeline
setenv HCPPIPEDIR ${PP_SCRIPTS}/HCP
setenv HCPPIPEDIR_Templates ${HCPPIPEDIR}/global/templates
setenv HCPPIPEDIR_Bin ${HCPPIPEDIR}/global/binaries
setenv HCPPIPEDIR_Config ${HCPPIPEDIR}/global/config
setenv HCPPIPEDIR_PreFS ${HCPPIPEDIR}/PreFreeSurfer/scripts
setenv HCPPIPEDIR_FS ${HCPPIPEDIR}/FreeSurfer/scripts
setenv HCPPIPEDIR_PostFS ${HCPPIPEDIR}/PostFreeSurfer/scripts
setenv HCPPIPEDIR_fMRISurf ${HCPPIPEDIR}/fMRISurface/scripts
setenv HCPPIPEDIR_fMRIVol ${HCPPIPEDIR}/fMRIVolume/scripts
setenv HCPPIPEDIR_tfMRI ${HCPPIPEDIR}/tfMRI/scripts
setenv HCPPIPEDIR_dMRI ${HCPPIPEDIR}/DiffusionPreprocessing/scripts
setenv HCPPIPEDIR_dMRITract ${HCPPIPEDIR}/DiffusionTractography/scripts
setenv HCPPIPEDIR_Global ${HCPPIPEDIR}/global/scripts
setenv HCPPIPEDIR_tfMRIAnalysis ${HCPPIPEDIR}/TaskfMRIAnalysis/scripts
setenv MSMBin ${HCPPIPEDIR}/MSMBinaries

#update the path with all the goodies we will use in the future.
setenv PATH ${PP_SCRIPTS}:${RELEASE}:${HCPPIPEDIR}:${CARET7DIR}:${REFDIR}:${FREESURFER_HOME}/bin:${FREESURFER_HOME}/mni/bin:${FSL_BIN}:${ANTSPATH}/bin:${ANTSPATH}/Scripts:${PP_SCRIPTS}/PET/PUP:${MATLAB_BIN}:${PATH}

