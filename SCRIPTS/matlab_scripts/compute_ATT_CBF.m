
function [MeanCBF] = compute_ATT_CBF( ASL_SearchTerm, PLD, T1b, ASL_FD_SearchTerm, FD_Thresh, LC_CL, FramePLDs)
%     ASL_SearchTerm = '*_asl*_atl.nii.gz'
%     PLD = [1 1.3 1.6 1.9 2.2 2.5]
%     T1b = 1.6

    if(~exist('FD_Thresh'))
        FD_Thresh = 0.5
    end
    
    if(~exist('LC_CL'))
        LC_CL = 1;
    end
    %==========================================================================
    %find all asl sequences

    ASL_files = list_files(ASL_SearchTerm);

    %mask_filename = dir('../../Masks/*_used_voxels_fnirt_333.nii.gz');
    %brainmask = load_nifti(['../../Masks/' mask_filename(1).name]);

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
    
    if(length(rawPcasl_CellArray) ~= length(PLD))
        disp('Raw ASL does not have the same number of files as the PLD list. ');
        disp('Will attempt to use the Frame PLD list.')

        %we have a single file with multiplds. We need to split it and make a
        %new CellArray with the split data
        loaded_data = [];
        loaded_fd = [];
        %concatenate all the data into a 4d array
        for i = 1:length(rawPcasl_CellArray)
           loaded_data = cat(4, loaded_data, rawPcasl_CellArray{i});
           loaded_fd = cat(4, loaded_fd, pcasl_FD{i});
        end
        Mo = loaded_data(:,:,:, FramePLDs == -1);
        Mo_fd = loaded_fd(FramePLDs == -1);
        
        rawPcasl_CellArray = [];
        pcasl_FD = [];
        
        for i = 1:length(PLD)
           rawPcasl_CellArray = vertcat(rawPcasl_CellArray ,{cat(4,Mo,loaded_data(:,:,:, FramePLDs == PLD(i)))});
           pcasl_FD = vertcat(pcasl_FD ,{[Mo_fd;loaded_fd( FramePLDs == PLD(i))]});
        end
    end

    disp('Computing optimal ATT and CBF...');
    asl_out = load_nifti(ASL_files{1});
    asl_out.dim(5) = 1;
    
    %[MeanCBF, WeightedDelay] = gpt_att_cbf_pcasl(rawPcasl_CellArray, PLD, T1b, pcasl_FD, FD_Thresh, LC_CL);
    [MeanCBF, WeightedDelay] = att_cbf_3d_pcasl(rawPcasl_CellArray, PLD, T1b, pcasl_FD, FD_Thresh, LC_CL);
    
    asl_out.vol = reshape(WeightedDelay,asl_out.dim(2),asl_out.dim(3), asl_out.dim(4));
    save_nifti(asl_out,['WeightedDelay.nii.gz']); 
    
    asl_out.vol = reshape(MeanCBF,asl_out.dim(2),asl_out.dim(3), asl_out.dim(4));
    save_nifti(asl_out,['MeanCBF.nii.gz']);
end