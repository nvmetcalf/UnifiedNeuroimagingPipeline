
function [MeanCBF] = compute_ATT_CBF( ASL_SearchTerm, PLD, T1b, ASL_FD_SearchTerm, FD_thresh)
%     ASL_SearchTerm = '*_asl*_atl.nii.gz'
%     PLD = [1 1.3 1.6 1.9 2.2 2.5]
%     T1b = 1.6


    %==========================================================================
    %find all asl sequences

    ASL_files = list_files(ASL_SearchTerm);

    mask_filename = dir('../../Masks/*_used_voxels_fnirt_333.nii.gz');
    brainmask = load_nifti(['../../Masks/' mask_filename(1).name]);

    FD_files = list_files(['../Movement/' ASL_FD_SearchTerm]);
    
    
    MeanCBF = [];
    rawPcasl_CellArray = {};
    pcasl_FD = {};
    for i = 1:length(ASL_files)
        disp([ ' Loading: ' ASL_files{i}]);
        read_ASL = load_nifti(ASL_files{i});
        FD = importdata(FD_files{i});
        
        rawPcasl_CellArray = vertcat(rawPcasl_CellArray,{read_ASL.vol}); %#ok<AGROW>
        pcasl_FD = vertcat(pcasl_FD,{FD});
    end
    
    disp('Computing optimal ATT and CBF...');
    asl_out = brainmask;
    [MeanCBF, WeightedDelay] = att_cbf_3d_pcasl(rawPcasl_CellArray, brainmask.vol, PLD, T1b, pcasl_FD);
    
    asl_out.vol = reshape(WeightedDelay,asl_out.dim(2),asl_out.dim(3), asl_out.dim(4));
    save_nifti(asl_out,['WeightedDelay.nii.gz']); 
    
    asl_out.vol = reshape(MeanCBF,asl_out.dim(2),asl_out.dim(3), asl_out.dim(4));
    save_nifti(asl_out,['MeanCBF.nii.gz']);
end