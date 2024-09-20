function job = moh_cfg_ALI
% Configuration file for the Automatic Lesion Identification (ALI)
%_______________________________________________________________________
% Copyright (C) 2009 Wellcome Trust Centre for Neuroimaging
%
% Mohamed Seghier, 28.05.2009 // updated 13.03.2014
% =========================

if ~isdeployed, addpath(fullfile(spm('dir'),'toolbox','ALI'),'-end'); end


% %______________________________________________________________________
% 
% entry = inline(['struct(''type'',''entry'',''name'',name,'...
%         '''tag'',tag,''strtype'',strtype,''num'',num)'],...
%         'name','tag','strtype','num');
% 
% files = inline(['struct(''type'',''files'',''name'',name,'...
%         '''tag'',tag,''filter'',fltr,''num'',num)'],...
%         'name','tag','fltr','num');
% 
% mnu = inline(['struct(''type'',''menu'',''name'',name,'...
%         '''tag'',tag,''labels'',{labels},''values'',{values})'],...
%         'name','tag','labels','values');
% 
% branch = inline(['struct(''type'',''branch'',''name'',name,'...
%         '''tag'',tag,''val'',{val})'],...
%         'name','tag','val');
% 
% repeat = inline(['struct(''type'',''repeat'',''name'',name,''tag'',tag,'...
%          '''values'',{values})'],'name','tag','values');
%      
% choice = inline(['struct(''type'',''choice'',''name'',name,''tag'',tag,'...
%          '''values'',{values})'],'name','tag','values');
%      
% %______________________________________________________________________
% 



% -------------------------------------------------------------------------
% configuation for STEP 1: iterative unified segmentation-normalisation
% -------------------------------------------------------------------------
 
 
step1data    = cfg_files;
step1data.tag     = 'step1data';
step1data.name    = 'Images to segment';
step1data.filter  = 'image';
step1data.ufilter = '.*';
step1data.num     = [0 Inf];
step1data.help    = {[...
'Specify the input images for the unified segmentation. ',...
'This should be your anatomical/structural images (e.g. T1 images)',...
' of a single or many patients...']};


prior_filename     = fullfile(spm('Dir'), 'toolbox',...
    'ALI', 'Priors_extraClass', 'wc4prior0.nii') ; 
step1prior    = cfg_files;
step1prior.tag     = 'step1prior';
step1prior.name    = 'Prior EXTRA class';
step1prior.filter  = 'image';
step1prior.ufilter = '.*';
step1prior.num     = [1 1];
step1prior.val{1}     = {prior_filename};
step1prior.help    = {[...
'Select the prior (1st guess) for the EXTRA class. ',...
'This prior will be combined with the other six (by default) priors ',...
' for the iterative NEW unified segmentation routine. In the absence of any ',...
' hypothesis, this prior is empirically set to 05*(CSF + WM). In the ',...
' presence of abnormality, this prior will be updated at every iteration ',...
' of the segmentation procedure so it will then approximate the location ',...
' of the lesion for next segmentation runs. However, users can modify the ',...
' definition of the prior of the EXTRA class (used at iteration 1 as a ',...
' first guess) and include other informed spatial priors. For instance, ',...
' this prior can be limited to left hemisphere only if all lesions are ',...
' located in the LH...etc. ']};
 
 
 
step1niti    = cfg_entry;
step1niti.name    = 'Number of iterations';
step1niti.tag     = 'step1niti';
step1niti.strtype = 'r';
step1niti.num     = [1 1];
step1niti.val     = {2};
step1niti.help    = {[...
'Specify the number of iterations for the new iterative unified ',...
' segmentation-normalisation procedure. This number will define the number',...
' of segmentation runs. The updated EXTRA class of run (n-1) will be used ',...
' as prior for the EXTRA class of run (n).']};



step1thr_prob    = cfg_entry;
step1thr_prob.name    = 'Threshold: probability';
step1thr_prob.tag     = 'step1thr_prob';
step1thr_prob.strtype = 'r';
step1thr_prob.num     = [1 1];
step1thr_prob.val     = {1/3};
step1thr_prob.help    = {[...
'Specify the thershold for the probability of the EXTRA class: ', ...
' at each iteration, the EXTRA class will be cleaned up before ',...
' used as a prior for the next segmentation run. This step will ',...
' help to limit the serach for abnormality for only voxels with ',...
' high probability in the EXTRA class (i.e. voxels with high prob ',...
' are those that cannot be fully explained by the expected GM, WM, ',...
' and CSF classes.']};


step1thr_size    = cfg_entry;
step1thr_size.name    = 'Threshold: size [in cm3]';
step1thr_size.tag     = 'step1thr_size';
step1thr_size.strtype = 'r';
step1thr_size.num     = [1 1];
step1thr_size.val     = {0.8}; % if voxel size = 2mm
step1thr_size.help    = {[...
'Specify the thershold for the size (in cm3) of the EXTRA class: ', ...
' at each iteration, the EXTRA class will be cleaned up. Only abnornal ',...
' regions with a relatively big size (> thershold) will considered for ',...
' the definition of the prior for the EXTRA class.']};


step1coregister    = cfg_menu;
step1coregister.tag     = 'step1coregister';
step1coregister.name    = 'Coregister to MNI space';
step1coregister.labels = {'YES', 'NO'} ;
step1coregister.values = {1 0} ;
step1coregister.val = {1} ;
step1coregister.help    = {['you can coregister your anatomical images ',...
    'to MNI space (e.g. target=T1_template). This would help the ', ...
    'accuracy of the segmentation algorithm (e.g. avoid having input ',...
    ' images with abherant centres/locations).']};






step1mask    = cfg_files;
step1mask.tag     = 'step1mask';
step1mask.name    = '(optional) Cost function mask CFM';
step1mask.filter  = 'image';
step1mask.ufilter = '.*';
step1mask.num     = [0 1];
step1mask.val{1}     = {''};
step1mask.help    = {[...
'The option can be used if a manual segmentation of the lesion',...
' is available (as in cost function masking CFM). ',...
'The segmentation can then be masked by an image that conforms',...
' to the same space as the images to be segmented.  If an image',... 
' is selected, then it must match the image(s) voxel-for voxel,',...
' and have the same voxel-to-world mapping.  Regions containing',...
' a value of zero in this image do not contribute',...
' when estimating the various parameters. ']};


step1vox         = cfg_entry;
step1vox.tag     = 'step1vox';
step1vox.name    = 'Voxel sizes [in mm]';
step1vox.help    = {'The voxel sizes (isotropic, in mm) of the written normalised images.'};
step1vox.strtype = 'r';
step1vox.num     = [1 1];
step1vox.val     = {2};


step1fwhm    = cfg_entry;
step1fwhm.name    = 'Smooth: FWHM';
step1fwhm.tag     = 'step1fwhm';
step1fwhm.strtype = 'e';
step1fwhm.num     = [1 3];
step1fwhm.val     = {[8 8 8]};
step1fwhm.help    = {[...
'The segmented GM and WM tissue images are spatially smoothed to ',...
'account for typical (normal) between-subject variability in anatomy. ',...
'Specify the full-width at half maximum (FWHM) of the Gaussian smoothing ',...
'kernel [in mm]: three values denoting the FWHM in the ',...
'x, y and z directions.']};



% unified_segmentation.type    = 'branch';
unified_segmentation    = cfg_exbranch;
unified_segmentation.tag     = 'unified_segmentation';
unified_segmentation.name    = 'Brain segmentation';
unified_segmentation.val     = {step1data step1prior step1niti ...
    step1thr_prob step1thr_size step1coregister step1mask step1vox step1fwhm};
unified_segmentation.help    = {...
    'Segment/normalize all structural images using',...
    ' the NEW unified segmentation-normalisation procedure.'};
unified_segmentation.prog    = @segment_unified ; 
 
 

%
% % old version in ALI 2.0
% % -------------------------------------------------------------------------
% % configuation for STEP 2: spatial smoothing of segmented GM/WM classes
% % -------------------------------------------------------------------------
% 
%  
% step2data.type    = 'files';
% step2data.tag     = 'step2data';
% step2data.name    = 'Images to smooth';
% step2data.filter  = 'image';
% step2data.ufilter = '.*';
% step2data.num     = [0 Inf];
% step2data.help    = {[...
% 'Select your segmented GM and WM images: ',...
% ' all images will be spatially smoothed. Both patients and controls images',...
% ' can be selected.']};
%  
%  
% step2fwhm.type    = 'entry';
% step2fwhm.name    = 'FWHM';
% step2fwhm.tag     = 'step2fwhm';
% step2fwhm.strtype = 'e';
% step2fwhm.num     = [1 3];
% step2fwhm.val     = {[8 8 8]};
% step2fwhm.help    = {[...
% 'Specify the full-width at half maximum (FWHM) of the Gaussian smoothing ',...
% 'kernel [in mm]: three values denoting the FWHM in the ',...
% 'x, y and z directions.']};
%  
%  
% spatial_smoothing.type    = 'branch';
% spatial_smoothing.tag     = 'spatial_smoothing';
% spatial_smoothing.name    = 'Spatial smoothing';
% spatial_smoothing.val     = {step2data step2fwhm};
% spatial_smoothing.help    = {...
%     'STEP 2: spatial smoothing of segmented gray and white matter images.'};
% spatial_smoothing.prog    = @smooth_spatial ;
 


% -------------------------------------------------------------------------
% configuation for STEP 3: outliers detection (detection of abnormality)
% -------------------------------------------------------------------------

% step3directory.type    = 'files';
% step3directory.tag     = 'step3directory';
% step3directory.name    = 'Select a directory';
% step3directory.help    = {'Select a directory where to save the results.'};
% step3directory.filter  = 'dir';
% step3directory.num     = 1;


step3patients    = cfg_files;
step3patients.tag     = 'step3patients';
step3patients.name    = 'Patients: volumes';
step3patients.filter  = 'image';
step3patients.ufilter = '^swc/*';
step3patients.num     = [0 Inf];
step3patients.help    = {[...
'Specify the smoothed segmented tissue images of your patients. ',...
'These images will then be compared, voxel by voxel, to the smoothed ',...
'segmented tissue images of all your controls. Any voxel in the patient image ',...
'that deviates from the normal range will be considered as an outlier, and ',...
'thus included in the lesion. By definition, lesion = set of ',...
'abnornal/outlier voxels.']};


step3controls    = cfg_files;
step3controls.tag     = 'step3controls';
step3controls.name    = 'Controls: volumes';
step3controls.filter  = 'image';
step3controls.ufilter = '^swc/*';
step3controls.num     = [0 Inf];
step3controls.help    = {[...
'Specify the smoothed segmented tissue images of your healthy controls. ',...
'These images are used to assess the dergee of "normality" at each voxel ',...
'(e.g. what is the "normal" variability in the healthy controls group?)... ']};


step3Alpha    = cfg_entry;
step3Alpha.name    = 'Alpha parameter';
step3Alpha.tag     = 'step3Alpha';
step3Alpha.strtype = 'r';
step3Alpha.num     = [1 1];
step3Alpha.val     = {0.5};
step3Alpha.help    = {[...
'Specify the value of Alpha: this is the factor of sensitivity ',...
'(tunning factor), equal here to 0.5 (i.e. half the probability interval). ']};

step3Lambda    = cfg_entry;
step3Lambda.name    = 'Lambda parameter';
step3Lambda.tag     = 'step3Lambda';
step3Lambda.strtype = 'r';
step3Lambda.num     = [1 1];
step3Lambda.val     = {-4};
step3Lambda.help    = {[...
'Specify the value of Lambda: equivalent to the fuzziness index "m" in ',... 
'standard FCM algorithm (m=1-2/Lambda). By default, Lambda = -4.']};


% ---------------------------------------------------------------------
% Tissue
% ---------------------------------------------------------------------
step3tissue         = cfg_branch;
step3tissue.tag     = 'step3tissue';
step3tissue.name    = 'Tissue';
step3tissue.val     = {step3patients step3controls step3Alpha step3Lambda };
step3tissue.help    = {'For each tissue of interest, you need to include',...
    ' images/volumes for both patients and controls; provided both have ',...
    'been processed similarly. '};
% ---------------------------------------------------------------------
% Images
% ---------------------------------------------------------------------
step3images         = cfg_repeat;
step3images.tag     = 'step3images';
step3images.name    = 'Images';
step3images.val     = {step3tissue };
step3images.help    = {' Identify abnormalities in each tissue image. ',...
    'For instance, you can search for abnormalities in gray (GM) and white',...
    ' (WM) matter. Replicate "Tissue" for each tissue class. '};
step3images.values  = {step3tissue };
step3images.num     = [1 Inf];


%mask_filename     = fullfile(spm('Dir'), 'tpm','mask_ICV.nii'); vox=1.5mm
mask_filename     = fullfile(spm('Dir'), 'toolbox',...
    'ALI', 'Mask_image', 'mask_controls_vox2mm.nii') ;
step3mask    = cfg_files;
step3mask.tag     = 'step3mask';
step3mask.name    = 'Mask (regions of interest)';
step3mask.filter  = 'image';
step3mask.ufilter = '.*';
step3mask.num     = [1 1];
step3mask.val{1}     = {mask_filename};
step3mask.help    = {[...
'Select the image mask for your lesion detection analysis: ',...
'the mask can be any image and it is used to limit the lesion detection ',...
'within a the meaningful voxels (e.g. in-brain voxels). By default, ',...
'the mask = whole brain (no assumption about the expected locations).']};


step3mask_thr    = cfg_entry;
step3mask_thr.name    = 'Threshold for the mask';
step3mask_thr.tag     = 'step3mask_thr';
step3mask_thr.strtype = 'r';
step3mask_thr.num     = [1 1];
step3mask_thr.val     = {0};
step3mask_thr.help    = {[...
'Specify the threshold: all voxels of the mask image that have a signal ', ...
'less than the threshold are excluded from the lesion detection.']};


step3binary_thr    = cfg_entry;
step3binary_thr.name    = 'Binary lesion: threshold U';
step3binary_thr.tag     = 'step3binary_thr';
step3binary_thr.strtype = 'r';
step3binary_thr.num     = [1 1];
step3binary_thr.val     = {0.3};
step3binary_thr.help    = {[...
'Lesion is written as a fuzzy set (continuous degree of abnormality). ',...
'Specify a threshold to wrtite a binarised 3D-lesion image: ',...
'all voxels with a degree of abonormality (U) ',...
'bigger than the thereshold will be considered as a lesion. Useful for',...
' the generation of the binary/contour definition of the lesion.']};



step3binary_size    = cfg_entry;
step3binary_size.name    = 'Binary lesion: minimum size [in cm3]';
step3binary_size.tag     = 'step3binary_size';
step3binary_size.strtype = 'r';
step3binary_size.num     = [1 1];
step3binary_size.val     = {0.8};
step3binary_size.help    = {[...
'Specify the minimum size (in cm3): all abnormal clusters with less than the ',...
'threshold size will be excluded (e.g. tiny/small clusters) in the binary ',...
' 3D-lesion image.']};


outliers_detection    = cfg_exbranch;
outliers_detection.tag  = 'outliers_detection';
outliers_detection.name = 'Abnormalities detection';
outliers_detection.val  = {step3images ...
    step3mask step3mask_thr ...
    step3binary_thr step3binary_size};
outliers_detection.help = {[...
    'Outliers detection (lesion = abnormal/outlier voxels) ',...
    'from both GM and WM classes (using the FCP algorithm). ',...
    ' See Seghier et al. (2007) Neuroimage 36:594-605.']};
outliers_detection.prog = @detect_outliers;
        


% %
% % old versoin of ALI
% % -------------------------------------------------------------------------
% % configuation for STEP 4: lesion definition (fuzzy, binary and contour)
% % -------------------------------------------------------------------------
% 
% step4directory.type    = 'files';
% step4directory.tag     = 'step4directory';
% step4directory.name    = 'Select a directory';
% step4directory.help    = {'Select a directory where to save the results'};
% step4directory.filter  = 'dir';
% step4directory.num     = 1;
% 
% 
% step4fcpGM.type    = 'files';
% step4fcpGM.tag     = 'step4fcpGM';
% step4fcpGM.name    = 'Negative FCP_GM images';
% step4fcpGM.filter  = 'image';
% step4fcpGM.ufilter = '.*';
% step4fcpGM.num     = [0 Inf];
% step4fcpGM.help    = {[...
% 'Select the FCP_negative of the gray matter images of your patients: ',... 
% 'these images represent where the GM of a given patient is abnormally ',...
% 'low compared to GM of the controls. These images are those computed ',...
% 'in the previous step.']};
% 
% 
% step4fcpWM.type    = 'files';
% step4fcpWM.tag     = 'step4fcpWM';
% step4fcpWM.name    = 'Negative FCP_WM images';
% step4fcpWM.filter  = 'image';
% step4fcpWM.ufilter = '.*';
% step4fcpWM.num     = [0 Inf];
% step4fcpWM.help    = {[...
% 'Select the FCP_negative of the white matter images of your patients. ',...
% 'SELECTED IN THE SAME ORDER AS THOSE OF THE GM IMAGES...!!!! ',...
% 'These images represent where the WM of a given patient is abnormally ',...
% 'low compared to WM of the controls. These images are those computed ',...
% 'in the previous step.']};
% 
%         
%         
% step4binary_thr.type    = 'entry';
% step4binary_thr.name    = 'Binary lesion: threshold U';
% step4binary_thr.tag     = 'step4binary_thr';
% step4binary_thr.strtype = 'r';
% step4binary_thr.num     = [1 1];
% step4binary_thr.val     = {0.3};
% step4binary_thr.help    = {[...
% 'Specify the threshold: all voxels with a degree of abonormality (U) ',...
% 'bigger than the thereshold will be considered as a lesion. Useful for',...
% ' the generation of the binary/contour definition of the lesion.']};
% 
% 
% 
% step4binary_size.type    = 'entry';
% step4binary_size.name    = 'Binary lesion: minimum size';
% step4binary_size.tag     = 'step4binary_size';
% step4binary_size.strtype = 'r';
% step4binary_size.num     = [1 1];
% step4binary_size.val     = {100};
% step4binary_size.help    = {[...
% 'Specify the minimum size (nb vox): all abnormal clusters with less than the ',...
% 'threshold size will be excluded (e.g. tiny/small clusters) will be ',...
% 'removed for the lesion volume.']};
% 
% 
% lesion_definition.type    = 'branch';
% lesion_definition.tag     = 'lesion_definition';
% lesion_definition.name    = 'Lesion definition (grouping)';
% lesion_definition.val     = {step4directory step4fcpGM step4fcpWM ... 
%     step4binary_thr step4binary_size};
% lesion_definition.help    = {[...
%     'STEP 4: group abnormal (GM and WM) images as a lesion ',...
%     ' (three images generated: fuzzy, binary and contour).']};
% lesion_definition.prog = @define_lesion;
% 


% -------------------------------------------------------------------------
% generate lesion overlap maps (LOM): useful for group analysis
% -------------------------------------------------------------------------

step5directory    = cfg_files;
step5directory.tag     = 'step5directory';
step5directory.name    = 'Select a directory';
step5directory.help    = {'Select a directory where to save the results'};
step5directory.filter  = 'dir';
step5directory.num     = [1 1];


step5LOM    = cfg_files;
step5LOM.tag     = 'step5LOM';
step5LOM.name    = 'Select Binary (lesion) images';
step5LOM.filter  = 'image';
step5LOM.ufilter = '.*';
step5LOM.num     = [0 Inf];
step5LOM.help    = {[...
'Select the binary definition of the lesions of all your patients. ',...
'These binary images are those created in the previous step.']};

step5thr_nb    = cfg_entry;
step5thr_nb.name    = 'LOM threshold';
step5thr_nb.tag     = 'step5thr_nb';
step5thr_nb.strtype = 'e';
step5thr_nb.num     = [1 1];
step5thr_nb.val     = {1};
step5thr_nb.help    = {...
    'Specify the threshold of the LOM: minimum overlap to be displayed. '};




step5 = cfg_branch ;
step5.tag     = 'step5';
step5.name    = 'Generate a LOM';
step5.val     = {step5directory step5LOM step5thr_nb};
step5.help    = {...
    'Generate a new lesion overlap maps (LOM).'};




step6LOM_file    = cfg_files;
step6LOM_file.tag     = 'step6LOM_file';
step6LOM_file.name    = 'LOM file';
step6LOM_file.filter  = 'mat';
step6LOM_file.ufilter = '^LOM/*';
step6LOM_file.num     = [1 1];
step6LOM_file.help    = {[...
'Select the LOM*.mat that contains all the details of the generated ',...
'lesion overalp map (LOM) from the previous step. The LOM images will ',...
'refelct how many patients do have a lesion at a particular location.']};

        
step6thr_nb     = cfg_entry;
step6thr_nb.name    = 'LOM threshold';
step6thr_nb.tag     = 'step6thr_nb';
step6thr_nb.strtype = 'e';
step6thr_nb.num     = [1 1];
step6thr_nb.val     = {1};
step6thr_nb.help    = {...
    'Specify the threshold of the LOM: minimum overlap to be displayed. '};


step6 = cfg_branch ;
step6.tag     = 'step6';
step6.name    = 'Explore a LOM';
step6.val     = {step6LOM_file step6thr_nb};
step6.help    = {...
    'Explore the already generated lesion overlap maps (LOM).'};


lom = cfg_choice ;
lom.name = 'Lesion Overlap Map';
lom.tag  = 'lom';
lom.values = {step5 step6};
lom.help = {'LOM: select what to do.'};



lesion_overlap    = cfg_exbranch;
lesion_overlap.tag     = 'lesion_overlap';
lesion_overlap.name    = 'Lesion overlap mapping';
lesion_overlap.val     = {lom};
lesion_overlap.help    = {...
    'Generate lesion overlap maps (LOM): overlap across patients.'};
lesion_overlap.prog = @generate_LOM;
 



%
% old ALI 
% % -------------------------------------------------------------------------
% % explore the LOM maps: useful for group analysis
% % -------------------------------------------------------------------------
% 
% step6LOM_file.type    = 'files';
% step6LOM_file.tag     = 'step6LOM_file';
% step6LOM_file.name    = 'LOM file';
% step6LOM_file.filter  = 'mat';
% step6LOM_file.ufilter = '.*';
% step6LOM_file.num     = [1 1];
% step6LOM_file.help    = {[...
% 'Select the LOM*.mat that contains all the details of the generated ',...
% 'lesion overalp map (LOM) from the previous step. The LOM images will ',...
% 'refelct how many patients do have a lesion at a particular location.']};
% 
%         
% step6thr_nb.type    = 'entry';
% step6thr_nb.name    = 'LOM threshold';
% step6thr_nb.tag     = 'step6thr_nb';
% step6thr_nb.strtype = 'e';
% step6thr_nb.num     = [1 1];
% step6thr_nb.val     = {1};
% step6thr_nb.help    = {...
%     'Specify the threshold of the LOM: minimum overlap to be displayed. '};
%         
% lesion_overlap_explore.type    = 'branch';
% lesion_overlap_explore.tag     = 'lesion_overlap_explore';
% lesion_overlap_explore.name    = 'Explore the LOM';
% lesion_overlap_explore.val     = {step6LOM_file step6thr_nb};
% lesion_overlap_explore.help    = {...
%     'STEP 6: explore the generated lesion overlap maps (LOM).'};
% lesion_overlap_explore.prog = @explore_LOM;
% 




%--------------------------------------------------------------------------
% Define ALI job
%--------------------------------------------------------------------------

% job.type = 'choice';
job = cfg_choice ;
job.name = 'ALI';
job.tag  = 'ali';
% job.values = {unified_segmentation,spatial_smoothing,outliers_detection,...
%     lesion_definition,lesion_overlap,lesion_overlap_explore};
job.values = { unified_segmentation outliers_detection lesion_overlap };
job.help = {'Automatic Lesion Identification (ALI)'};
% job.prog = @moh_run_ALI;


%------------------------------------------------------------------------
%------------------------------------------------------------------------
function segment_unified(job)
moh_run_ALI(job);

% %------------------------------------------------------------------------
% function smooth_spatial(job)
% moh_run_ALI(job);

%------------------------------------------------------------------------
function detect_outliers(job)
moh_run_ALI(job);

%------------------------------------------------------------------------
% function define_lesion(job)
% moh_run_ALI(job);

%------------------------------------------------------------------------
function generate_LOM(job)
moh_run_ALI(job);

% %------------------------------------------------------------------------
% function explore_LOM(job)
% moh_run_ALI(job);

        
