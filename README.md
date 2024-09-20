Initial readme. Will be updated.

You will need the following package:
https://wustl.box.com/s/8yc08ju7hz0cj3j8gvubppomddd81aaq

Extract it into the UnifiedNeuroimagingPipeline folder as is. It should add REFDIR to ATLAS, fslview, ROBEX, ANTs, and Synb0-DSCO folders to SCRIPTS, and empty Scans and Projects folders to the UnifiedNeuroimagingPipeline folder.

You will also need to run the fslinstaller.py script using python in the SCRIPTS folder to install FSL (some functionality in the pipeline is linked to the python distro in FSL). By default, it will want to install into SCRIPTS.

You will also need to download freesurfer and acquire a free license for it. Any version of freesurfer 6.0 and higher should work. If you only have or trust Freesurfer5.3, PET processing will fail at the partial volume correction step as gtmpvc is not a part of freesurfer 5.3 normally. I recommend extracting freesurfer to the SCRIPTS folder and renaming the freesurfer-xxxxxx folder that extracts to "freesurfer" (no quotes) so that the path to recon-all looks like: SCRIPTS/freesurfer/bin/recon-all

Your freesurfer and FSL install does not need to be in any particular place, but the PipelineEnvironment.csh script will need to be updated to point to the location of where each is installed. 
