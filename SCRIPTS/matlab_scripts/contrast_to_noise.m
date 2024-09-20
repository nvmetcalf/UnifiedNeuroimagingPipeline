%load the white matter region
%load cortical ribbon
%load whole brain mask
%load anatomical image
%erode the white matter region
%dilate the whole brain mask multiple times
%extract mean white matter intensity
%extract mean gray matter intensity
%get the mean upper 90% or SD of noise region
%compute (WM - GM)/Noise 

% InvertWarp = 'atlas/FCS_047_AMC_r33_invwarpfield_111.nii.gz';
% AtlToTarget_T4 = 'atlas/mni_icbm152_tal_nlin_asym_09c_t88_t1_111_to_FCS_047_AMC_r33_mpr1T_t4';
% TargetName = 'atlas/FCS_047_AMC_r33_mpr1T';
% 
% %111 space nifti image
% AnatomicalImageFilename = 'atlas/FCS_047_AMC_r33_mpr1T';
% 
% %333 spaced 4dfp image
% WhiteMatterRegionFilename = 'FCmaps_uwrp/FCS_047_AMC_r33_WM_mask';
% 
% %333 spaced nifti image
% CorticalRibbonFilename = 'HCP_Results/RibbonVolumeToSurfaceMapping/ribbon_only';
% 
% %111 spaced nifti image
% WholeBrainMaskFilename = 'FCmaps_uwrp/FCS_047_AMC_r33_faln_dbnd_xr3d_uwrp_atl_dfndm';


function [NoiseRatio MeanWhiteMatter MeanGrayMatter SDNoise] = contrast_to_noise(WholeBrainMaskFilename, CorticalRibbonFilename, WhiteMatterRegionFilename, AnatomicalImageFilename, TargetName, AtlToTarget_T4, InvertWarp)

    %--------------------------------------------------------------------------

    system(['t4img_4dfp none ' WhiteMatterRegionFilename ' ' WhiteMatterRegionFilename '_111 -O111 -n']);
    system(['niftigz_4dfp -n ' WhiteMatterRegionFilename '_111 ' WhiteMatterRegionFilename '_111']);
    system(['fslmaths ' WhiteMatterRegionFilename '_111 -ero -ero -bin ' WhiteMatterRegionFilename '_111_eroded']);

    system(['applywarp -i ' WhiteMatterRegionFilename '_111_eroded -r ' WhiteMatterRegionFilename '_111_eroded -w ' InvertWarp ' -o ' WhiteMatterRegionFilename '_111_eroded_unwarp --interp=nn'])
    system(['niftigz_4dfp -4 ' WhiteMatterRegionFilename '_111_eroded_unwarp ' WhiteMatterRegionFilename '_111_eroded_unwarp']);
    system(['t4img_4dfp ' AtlToTarget_T4 ' ' WhiteMatterRegionFilename '_111_eroded_unwarp ' WhiteMatterRegionFilename '_111_eroded_unwarp_mpr1T -O' AnatomicalImageFilename ' -n']);
    system(['niftigz_4dfp -n ' WhiteMatterRegionFilename '_111_eroded_unwarp_mpr1T ' WhiteMatterRegionFilename '_111_eroded_unwarp_mpr1T']);

    CorticalRibbon = load_nifti([WhiteMatterRegionFilename '_111_eroded_unwarp_mpr1T.nii.gz'])'

    WhiteMatterRegion = load_nifti([WhiteMatterRegionFilename '_111_eroded_unwarp_mpr1T.nii.gz']);



    system(['niftigz_4dfp -4 ' CorticalRibbonFilename ' ' CorticalRibbonFilename]);
    system(['t4img_4dfp none ' CorticalRibbonFilename ' ' CorticalRibbonFilename '_111 -O111 -n']);
    system(['niftigz_4dfp -n ' CorticalRibbonFilename '_111 ' CorticalRibbonFilename '_111']);
    system(['fslmaths ' CorticalRibbonFilename '_111 -ero -bin ' CorticalRibbonFilename '_111_eroded']);

    system(['applywarp -i ' CorticalRibbonFilename '_111_eroded -r ' CorticalRibbonFilename '_111_eroded -w ' InvertWarp ' -o ' CorticalRibbonFilename '_111_eroded_unwarp --interp=nn'])
    system(['niftigz_4dfp -4 ' CorticalRibbonFilename '_111_eroded_unwarp ' CorticalRibbonFilename '_111_eroded_unwarp']);
    system(['t4img_4dfp ' AtlToTarget_T4 ' ' CorticalRibbonFilename '_111_eroded_unwarp ' CorticalRibbonFilename '_111_eroded_unwarp_mpr1T -O' AnatomicalImageFilename ' -n']);
    system(['niftigz_4dfp -n ' CorticalRibbonFilename '_111_eroded_unwarp_mpr1T ' CorticalRibbonFilename '_111_eroded_unwarp_mpr1T']);

    CorticalRibbon = load_nifti([CorticalRibbonFilename '_111_eroded_unwarp_mpr1T.nii.gz'])'

    system(['t4img_4dfp none ' WholeBrainMaskFilename ' ' WholeBrainMaskFilename '_111 -O111 -n']);
    system(['niftigz_4dfp -n ' WholeBrainMaskFilename '_111 ' WholeBrainMaskFilename '_111']);
    system(['fslmaths ' WholeBrainMaskFilename '_111 -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -dilM -bin ' WholeBrainMaskFilename '_111_dilated']);

    system(['applywarp -i ' WholeBrainMaskFilename '_111_dilated -r ' WholeBrainMaskFilename '_111_dilated -w ' InvertWarp ' -o ' WholeBrainMaskFilename '_111_dilated_unwarped --interp=nn'])
    system(['niftigz_4dfp -4 ' WholeBrainMaskFilename '_111_dilated_unwarped ' WholeBrainMaskFilename '_111_dilated_unwarped']);
    system(['t4img_4dfp ' AtlToTarget_T4 ' ' WholeBrainMaskFilename '_111_dilated_unwarped ' WholeBrainMaskFilename '_111_dilated_unwarp_mpr1T -O' AnatomicalImageFilename ' -n']);
    system(['niftigz_4dfp -n ' WholeBrainMaskFilename '_111_dilated_unwarp_mpr1T ' WholeBrainMaskFilename '_111_dilated_unwarp_mpr1T']);

    WholeBrain = load_nifti([WholeBrainMaskFilename '_111_dilated_unwarp_mpr1T.nii.gz']);

    [sX, sY,sZ] = size(WholeBrain.vol);

    WholeBrain.vol(:,:,1:sZ/2) = 1;

%     save_nifti(WholeBrain, 'test.nii.gz');

    AnatomicalImage = load_nifti([AnatomicalImageFilename '.nii.gz']);

    MeanWhiteMatter = mean(reshape(AnatomicalImage.vol(WhiteMatterRegion.vol > 0),1,[]));
    MeanGrayMatter = mean(reshape(AnatomicalImage.vol(CorticalRibbon.vol > 0),1,[]));

    [sX, sY, sZ] = size(AnatomicalImage.vol);
    %a = reshape(AnatomicalImage.vol(1:round(sX*0.1),1:round(sY*0.1),1:round(sZ*0.1)),1,[]);
    %b = reshape(AnatomicalImage.vol(round(sX*0.9):end,round(sY*0.9):end,round(sZ*0.1):end),1,[]);
    %SDNoise = std([a b]);
    SDNoise = std(reshape(AnatomicalImage.vol(WholeBrain.vol == 0),1,[]));

    NoiseRatio = (MeanWhiteMatter - MeanGrayMatter)/SDNoise;

end