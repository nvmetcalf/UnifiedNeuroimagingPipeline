%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

function process_ase(patid, ASE_Scans, ASE_JSONs, hct, WorkingDirectory)
    dir_image    = WorkingDirectory;
    dir_ase      = sprintf('%s',            dir_image);
    dir_original = sprintf('%s',       dir_ase);
    dir_mc       = sprintf('%s/MC_ASE',         dir_ase);
    dir_working  = sprintf('%s/MC_ASE_working', dir_ase);
    dir_smoothing= sprintf('%s/smoothing',      dir_mc);
    
    if ~exist(dir_mc)
        mkdir(dir_mc);
        mkdir(dir_working);
        mkdir(dir_smoothing);
    end;


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    num_echoes_total = length(ASE_Scans);
    num_echoes_used = num_echoes_total;

    maxTau = inf;
    tauThresh1 = 0.015;
    tauThresh2 = 0.03;

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% calcualte ase

    if(~isnumeric(hct) || hct < 0)
        error('hemocrit value is incorrect.');
    end
    for i = 1:num_echoes_total
        if(~exist(ASE_Scans{i})) 
            error([ASE_Scans{i} ' does not exist.']);
        end
            
    end
    
   name_para_orig = sprintf('%s/%s_ase_para.dat', dir_original, patid);
   
   
   name_oef = sprintf('%s/%s_OEF.nii.gz', dir_ase, patid);

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
   end;   
   
    if(length(ASE_Scans) == 2)
        [DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0] = getASEParameters_2echoes_json(ASE_Scans{1}, ASE_Scans{2}, ASE_JSONs{1}, ASE_JSONs{2});
    else
        [DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0] = getASEParameters_2echoes_json(ASE_Scans{1}, ASE_Scans{2}, ASE_Scans{3}, ASE_JSONs{1}, ASE_JSONs{2}, ASE_JSONs{3});
    end

    save_ase_para(DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0, name_para_orig);

    hct = hct/100;  %get hemocrit scales by 100 for reasons.
    
   run_process_ase_1_mc(dir_ase, patid, num_echoes_total, num_zshimming);
   run_process_ase_2_prepare0(dir_ase, patid);
   run_process_ase_3_smoothing_ase(dir_ase, patid, num_echoes_total, num_frames);
   run_process_ase_4_cal_ase(dir_ase, patid, num_echoes_used, num_frames, num_zshimming, maxTau, tauThresh1, tauThresh2, hct);

end
