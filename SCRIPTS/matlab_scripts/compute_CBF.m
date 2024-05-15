
function [MeanCBF SdCBF NumPairs Pairwise_FD] = compute_CBF( ASL_SearchTerm, ASL_FD_SearchTerm, Trailer, PLD, T1b, pCASL, TI1, TR, BrainMask)
%     ASL_SearchTerm = '*_asl*_atl.nii.gz'
%     PLD = [1 1.3 1.6 1.9 2.2 2.5]
%     T1b = 1.6
%       TI1 = the labeling period in seconds
%       TR = the TR of the pasl sequence in seconds

    if(~exist('pCASL'))
        pCASL = true;
    end
    %==========================================================================
    %find all asl sequences

    ASL_files = list_files(ASL_SearchTerm);
    FD_files = list_files(['../Movement/' ASL_FD_SearchTerm]);

    brainmask = load_nifti(BrainMask);
    
    if(exist('../../HCP_Results/RibbonVolumeToSurfaceMapping/ribbon_only.nii.gz'))
        ribbon = load_nifti('../../HCP_Results/RibbonVolumeToSurfaceMapping/ribbon_only.nii.gz');
        run_mean = true;
    else
        run_mean = false;
    end
    
    MeanCBF = [];
    SdCBF = [];
    for i = 1:length(ASL_files)
        if(length(PLD) == 1)
            PostLabelingDelay = PLD;
        else
            PostLabelingDelay = PLD(i);
        end

        ASL = load_nifti(ASL_files{i});
        asl_out = ASL;
        asl_out.dim(5) = 1;
        asl_sd_out = asl_out;
        FD = importdata(FD_files{i});
        
        if(pCASL == 1) %pCASL GRASE
            [asl_out.vol asl_sd_out.vol NumPairs Pairwise_FD Mo] = cbf_3d_pcasl(ASL.vol, brainmask.vol, PostLabelingDelay, T1b, FD);
        elseif(pCASL == 2) %pCASL 2D
            [asl_out.vol asl_sd_out.vol NumPairs Pairwise_FD Mo] = cbf_pcasl(ASL.vol, brainmask.vol, PostLabelingDelay, T1b, FD);
        else
            [asl_out.vol asl_sd_out.vol NumPairs Pairwise_FD Mo] = cbf_pasl(ASL.vol, brainmask.vol, PostLabelingDelay, TI1, T1b, TR, FD);
        end
        
        save_nifti(asl_out,[strip_extension(strip_extension(ASL_files{i})) '_' Trailer '_cbf.nii.gz']);
        
        asl_out.vol = Mo;
        save_nifti(asl_out,[strip_extension(strip_extension(ASL_files{i})) '_' Trailer '_M0.nii.gz']);
        
        if(run_mean)
            MeanCBF = horzcat(MeanCBF, nanmean(reshape(asl_out.vol(ribbon.vol > 0),1,[])));

            [xSize,ySize,zSize,tSize] = size(asl_sd_out.vol);
            asl_sd_out.dim(5) = tSize;

            SD = reshape(nanstd(asl_sd_out.vol,0,4),1,[]);
            SdCBF = horzcat(SdCBF, nanmean(SD(ribbon.vol > 0)));
        end
        save_nifti(asl_sd_out,[strip_extension(strip_extension(ASL_files{i})) '_' Trailer '_cbf_pairs.nii.gz']);
    end
    
    MeanCBF = horzcat(MeanCBF, nanmean(MeanCBF));
    SdCBF = horzcat(SdCBF, nanmean(SdCBF));