%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

function process_ase(patid, ASE_Scans, ASE_JSONs, hct, WorkingDirectory)
    dir_image    = WorkingDirectory;
    dir_ase      = sprintf('%s',            dir_image);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    num_echoes_used = length(ASE_Scans);

    maxTau = inf;
    tauThresh1 = 0.015;
    tauThresh2 = 0.03;

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% calcualte ase

    if(~isnumeric(hct) || hct < 0)
        error('hemocrit value is incorrect.');  
    end

    nii = load_untouch_nii(ASE_Scans{1});
    [dimx, dimy, dimz, dimt] = size(nii.img);

    if dimt == 98
        num_frames   =  98;
        num_zshimming = 8;
    elseif dimt == 90
        num_frames    = 90;
        num_zshimming = 0;
    else
        error(sprintf('%s num_frames %d not supported!\n', patid, dimt));
    end

    run_cal_pv_ase(dir_ase, patid, num_echoes_used, num_frames, num_zshimming, maxTau, tauThresh1, tauThresh1, hct)

end
