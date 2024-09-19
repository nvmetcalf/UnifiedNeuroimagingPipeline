#set the environment variables for everything in the pipeline
#you want to source this script somehow (I call it from the default shell environment script in /etc)

setenv EDITOR   /usr/bin/nano

#location where the pipeline is living. Will have SCRIPTS, ATLAS, 'PROJECTS_DIR', Scans
setenv PROJECTS_HOME /data/nil-bluearc/vlassenko/Pipeline

#location of your scratch space. Usually a high speed storage area that
#	is used to store files that can be easily regenerated via the pipeline.
#	Things like freesurfer segmentations, intermediate BOLD registration, dtseries
#	intermediate steps, etc. are stored here.
setenv SCRATCH /data/vglab/data2/temp

#below this point you shouldn't HAVE to change any variables or paths, but if you are using different locations for FSL, Freesurfer, Workbench, etc. you may need to

##############################################
#
#	TRY NOT TO BREAK ANYTHING!
#
##############################################

#folder that holds all your projects
setenv PROJECTS_DIR "Projects"

#path to 711-2* atlases
setenv REFDIR /data/nil-bluearc/vlassenko/Pipeline/ATLAS/REFDIR

#Path to the Processing Pipeline Scripts
setenv PP_SCRIPTS /data/nil-bluearc/vlassenko/Pipeline/SCRIPTS

#set where workbench is installed. At one time it was called caret, history is fun.
setenv CARET7DIR ${PP_SCRIPTS}/caret7/bin_rh_linux64

#path to the nil 4dfp programs/scripts
setenv RELEASE ${PP_SCRIPTS}/lin64-tools

#path to the source for the nil 4dfp programs - if you need to compile them
setenv NILSRC ${PP_SCRIPTS}/lin64-nilsrc

# Set up ANTS
setenv ANTSPATH $PP_SCRIPTS/ANTs

#path to where freesurfer is located. No subject data will actually be stored there.
#	Freesurfer is included, BUT you will need to get a license file from
#	freesurfer (is free).
setenv FREESURFER_HOME ${PP_SCRIPTS}/freesurfer
#setenv FREESURFER_HOME /usr/local/pkg/freesurfer53-HCP
setenv FSFAST_HOME ${FREESURFER_HOME}/fsfast
setenv MNI_DIR ${FREESURFER_HOME}/mni

#setup the freesurfer environment
source ${FREESURFER_HOME}/SetUpFreeSurfer.csh
setenv TEMPDIR $SCRATCH

#path to where FSL is installed - a version is included in the pipeline
source ${PP_SCRIPTS}/fsl/etc/fslconf/fsl.csh
setenv FSLBIN ${PP_SCRIPTS}/fsl/bin

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
setenv PATH ${PP_SCRIPTS}:${RELEASE}:${HCPPIPEDIR}:${CARET7DIR}:${REFDIR}:${PP_SCRIPTS}/freesurfer/bin:${PP_SCRIPTS}/freesurfer/mni/bin:${FSLBIN}:${ANTSPATH}/bin:${ANTSPATH}/Scripts:${PATH}
