Initial readme. Will be updated.

If you use this pipeline, please use the following citation:

M.S. Goyal, T. Blazey, N.V. Metcalf, M.P. McAvoy, J.F. Strain, M. Rahmani, T.J. Durbin, C. Xiong, T.L. Benzinger, J.C. Morris, M.E. Raichle, A.G. Vlassenko, Brain aerobic glycolysis and resilience in Alzheimer disease, Proc. Natl. Acad. Sci. U.S.A.
120 (7) e2212256120,
https://doi.org/10.1073/pnas.2212256120 (2023).


You will need the following package:
https://wustl.box.com/s/8yc08ju7hz0cj3j8gvubppomddd81aaq

Extract it into the UnifiedNeuroimagingPipeline folder as is. It should add REFDIR to ATLAS, fslview, ROBEX, ANTs, and Synb0-DSCO folders to SCRIPTS, and empty Scans and Projects folders to the UnifiedNeuroimagingPipeline folder.

You will also need to run the fslinstaller.py script using python in the SCRIPTS folder to install FSL (some functionality in the pipeline is linked to the python distro in FSL). By default, it will want to install into SCRIPTS.

You will also need to download freesurfer and acquire a free license for it. Any version of freesurfer 6.0 and higher should work. If you only have or trust Freesurfer5.3, PET processing will fail at the partial volume correction step as gtmpvc is not a part of freesurfer 5.3 normally. I recommend extracting freesurfer to the SCRIPTS folder and renaming the freesurfer-xxxxxx folder that extracts to "freesurfer" (no quotes) so that the path to recon-all looks like: SCRIPTS/freesurfer/bin/recon-all

Your freesurfer and FSL install does not need to be in any particular place, but the PipelineEnvironment.csh script will need to be updated to point to the location of where each is installed. 

Lastly, you will need to update PipelineEnvironment.csh (generally just the top section variables) to set the full paths to the place where the pipeline is living (include the UnifiedNeuroimagingPipeline) and where you want temporary files stored/written.

Super brief pipeline setup:

1) Edit PipelineEnvironment.csh/sh

2) Create the following folders at the same level of SCRIPTS:
    Scans
    Projects

3) within Scans, create a folder for your projects (these names are going to be the name for the project when you propagate to Projects)
4) Within each project, create a folder for each participant (like with BIDS)
5) Within each participant, create a folder for each session.
6) Within each session, put the dicoms/nifti+jsons
7) run:
8)   propagate_scans <project name>
9)    you do not include the <>, just the folder name of the project in Scans
10) if the project hasn't been configured, you will be prompted to configure the project level parameters.
11) Each participant + session will be linked into the InProcess folder of Projects/<project name>, dicoms will be converted to nifti+jsons, parameters will be attempted to be detected automatically.
12) Goto Projects/<project name>/Inprocess and within each folder will be a file with <participant name>_<session ID>.params. Open this text file and make sure the file names and parameters are correct.
13) Run:
      P2 "list of folders" -reg
      This will perform the registrations + movement alignments of the sequences in the params file of each folder. Run P2 without arguements to see all operations available.
14) If all goes well, you will have registered data. Note, DTI has it's own commandline directive (-DTIp).
