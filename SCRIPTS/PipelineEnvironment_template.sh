#below this point you shouldn't HAVE to change any variables or paths, but if you are using different locations for FSL, Freesurfer, Workbench, etc. you may need to

##############################################
#
#	TRY NOT TO BREAK ANYTHING!
#
##############################################
#folder that holds all your projects
export PROJECTS_DIR="Projects"

#Path to the Processing Pipeline Scripts
export PP_SCRIPTS=${PROJECTS_HOME}/SCRIPTS

#set where workbench is installed. At one time it was called caret, history is fun.
export CARET7DIR=${PP_SCRIPTS}/SurfacePipeline/caret7/bin_rh_linux64

#path to the nil 4dfp programs/scripts
export RELEASE=${PP_SCRIPTS}/lin64-tools

#path to the source for the nil 4dfp programs - if you need to compile them
export NILSRC=${PP_SCRIPTS}/lin64-nilsrc

#path to where freesurfer is located. No subject data will actually be stored there.
#	Freesurfer is included, BUT you will need to get a license file from
#	freesurfer (is free).
export FREESURFER_HOME=${PP_SCRIPTS}/freesurfer
export FSFAST_HOME=${FREESURFER_HOME}/fsfast
export MNI_DIR=${FREESURFER_HOME}/mni

#setup the freesurfer environment
source ${FREESURFER_HOME}/SetUpFreeSurfer.sh

#path to where FSL is installed - a version is included in the pipeline
export FSLDIR=${PP_SCRIPTS}/fsl
export FSLBIN=$FSLDIR/bin
source ${FSLDIR}/etc/fslconf/fsl.sh

# Set up specific environment variables for the HCP Pipeline
export HCPPIPEDIR=${PP_SCRIPTS}/SurfacePipeline/HCP
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
export PATH=${PP_SCRIPTS}:${RELEASE}:${HCPPIPEDIR}:${CARET7DIR}:${FSLDIR}/bin:${PATH}
