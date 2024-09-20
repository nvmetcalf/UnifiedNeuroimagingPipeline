% RegionsToUse = {'/data/nil-bluearc/corbetta/SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered_w_SubCortical.32k.dlabel.nii'}
% %RegionsToUse = {'/data/nil-bluearc/corbetta/SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered.L.32k.label.gii', ...
% %                '/data/nil-bluearc/corbetta/SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered.R.32k.label.gii'}
% 
% OutputFolder = '../../Analysis/Results'
% 
% SubjectID = 'FCS_044_AMC';
% 
% FCMapsFolder = 'FCmaps_uwrp';
% 
% %SurfaceMask_LeftHemisphere = ['Masks/' SubjectID '_lesion_111_fnirt.L.32k.func.gii'];
% %SurfaceMask_RightHemisphere = ['Masks/' SubjectID '_lesion_111_fnirt.R.32k.func.gii'];
% 
% SurfaceMask_LeftHemisphere = [];
% SurfaceMask_RightHemisphere = [];
% 
% 
% AtlasTarget = 'MNI152_T1_1mm_t88';

 function RunResults(OutputFolder, SubjectID, FCMapsFolder, SurfaceMask_LeftHemisphere, SurfaceMask_RightHemisphere, RegionsToUse, AtlasTarget, LowResMesh)
    if(~exist(OutputFolder))
        mkdir(OutputFolder);
    end

    if(~exist([OutputFolder '/' SubjectID]))
        mkdir([OutputFolder '/' SubjectID]);
    end

    if(length(RegionsToUse) == 1)
        RegionsToUse(1,2) = {[]};
    end

    TmaskFile = [FCMapsFolder '/TemporalMask/tmask.txt'];

    tmask = importdata(TmaskFile);

    Midthickness_LeftHemisphere_gii = gifti(['Anatomical/Surface/' AtlasTarget '_' LowResMesh 'k/' SubjectID '.L.midthickness.' LowResMesh 'k_fs_LR.surf.gii']);
    Midthickness_LeftHemisphere.faces = Midthickness_LeftHemisphere_gii.faces;
    Midthickness_LeftHemisphere.vertices = Midthickness_LeftHemisphere_gii.vertices;
    Midthickness_LeftHemisphere.mat = Midthickness_LeftHemisphere_gii.mat;

    Midthickness_RightHemisphere_gii = gifti(['Anatomical/Surface/' AtlasTarget '_' LowResMesh 'k/' SubjectID '.R.midthickness.' LowResMesh 'k_fs_LR.surf.gii']);
    Midthickness_RightHemisphere.faces = Midthickness_RightHemisphere_gii.faces;
    Midthickness_RightHemisphere.vertices = Midthickness_RightHemisphere_gii.vertices;
    Midthickness_RightHemisphere.mat = Midthickness_RightHemisphere_gii.mat;

    CorticalThickness_LeftHemisphere_gii = gifti(['Anatomical/Surface/fsaverage_LR' LowResMesh 'k/' SubjectID '.L.thickness.' LowResMesh 'k_fs_LR.shape.gii']);
    CorticalThickness_LeftHemishpere = CorticalThickness_LeftHemisphere_gii.cdata;

    CorticalThickness_RightHemisphere_gii = gifti(['Anatomical/Surface/fsaverage_LR' LowResMesh 'k/' SubjectID '.R.thickness.' LowResMesh 'k_fs_LR.shape.gii']);
    CorticalThickness_RightHemishpere = CorticalThickness_LeftHemisphere_gii.cdata;

    CiftiTimeSeriesFilename = [FCMapsFolder '/Surface/' SubjectID '_fcmri_sr_bpss.ctx.dtseries.nii'];
    
    BOLD_Timeseries_SR_BPSS = ft_read_cifti_mod(CiftiTimeSeriesFilename);

    [SeedCorrMatrix Seed_TC_Variance SeedVertexCountRemaining SeedVertexCountIgnored SeedVertexCountInitial Seed_Timeseries Seed_Timeseries_Unfiltered] = SurfaceSeedCorrel(CiftiTimeSeriesFilename, RegionsToUse{1}, RegionsToUse{2}, TmaskFile, SurfaceMask_LeftHemisphere, SurfaceMask_RightHemisphere);

    SeedVertexCountRemaining = SeedVertexCountInitial - SeedVertexCountIgnored;

    if(exist([FCMapsFolder '/TemporalMask/' SubjectID '.fd']))
        FrameDisplacementTimeseries = importdata([FCMapsFolder '/TemporalMask/' SubjectID '.fd']);
    end

    if(exist([FCMapsFolder '/TemporalMask/' SubjectID '.dvar']))
        DVARTimeSeries = importdata([FCMapsFolder '/TemporalMask/' SubjectID '.dvar']);
    end

    save([OutputFolder '/' SubjectID '/Results.mat'], 'Midthickness_LeftHemisphere', 'Midthickness_RightHemisphere', 'BOLD_Timeseries_SR_BPSS', 'SeedCorrMatrix', 'Seed_TC_Variance', 'SeedVertexCountInitial', 'SeedVertexCountIgnored', 'SeedVertexCountRemaining', 'Seed_Timeseries', 'Seed_Timeseries_Unfiltered', 'CorticalThickness_LeftHemishpere', 'CorticalThickness_RightHemishpere', 'tmask');
end