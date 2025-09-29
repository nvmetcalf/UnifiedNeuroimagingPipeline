%function temp_cal_ase_pv(index_current, index_total)

index_current=1;
index_total=1;

%addpath('/data/nil-bluearc/vlassenko/Pipeline/Projects/ASE_Test/Participants/ASE_scripts/OEF_Calculation_AnLab/ASE_AnLab/NIFTI_yasheng');

dir_image = '/data/nil-bluearc/vlassenko/Pipeline/Projects/MRI/Participants/108034_WMHMRI_20230601/ASE/Volume';
dir_ase = sprintf('%s', dir_image);

num_echoes_total = 3;
num_echoes_used = 2;

num_frames=98;
num_zshimming = 8;

maxTau = inf;
tauThresh1 = 0.015;
tauThresh2 = 0.03;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% calcualte ase partial volume correction
%%ase resolution 1.7x1.7x3 
%%1.7*4/4=2.26 so 4 4 2 roughly propotional in all three dimensions
%%for pcasl  resolution is 2.5x2.5x4.3
%%1.7*4/2.5=2.72, 1.7*4/4.3=1.58, so 3x3x2 is roughly proportional

nx=4; ny=4; nz=2;

names_all = sprintf('%s/*_ase1_upck_xr3d_dc_atl.nii.gz', dir_ase);
names_all = dir(names_all);
nums_all  = length(names_all);

for i=index_current:index_total:nums_all,
   %nnn = names_tobe_computed{i};
   
   nnn = names_all(i).name;
   nnn = strrep(nnn, '_ase1_upck_xr3d_dc_atl.nii.gz', '');
   
   name_t1 = sprintf('%s/%s_t1_brain.nii.gz', dir_image, nnn);
   disp(name_t1);
   
   if ~exist(name_t1)
      continue;
   end;
   
   name_out_dir = sprintf('%s/PVC', dir_image);
   
   name_oef_combined        = sprintf('%s/%s_OEF_combined.nii.gz',    name_out_dir, nnn);
   name_error_combined      = sprintf('%s/%s_Error_combined.nii.gz',  name_out_dir, nnn);

   name_oef_gm        = sprintf('%s/%s_OEF_gm.nii.gz',    name_out_dir, nnn);
   name_error_gm      = sprintf('%s/%s_Error_gm.nii.gz',  name_out_dir, nnn);

   name_oef_wm        = sprintf('%s/%s_OEF_wm.nii.gz',    name_out_dir, nnn);
   name_error_wm      = sprintf('%s/%s_Error_wm.nii.gz',  name_out_dir, nnn);
   
   if exist(name_oef_combined) & exist(name_oef_gm) & exist(name_oef_wm)
      clear nnn name_t1 name_out_dir;
      clear name_oef_combined name_oef_gm name_oef_wm;
      continue;
   end;

   run_cal_pv_ase(dir_image, nnn, num_echoes_used, num_frames, num_zshimming, maxTau,  tauThresh1, tauThresh2, nx, ny, nz);

   clear nnn name_t1 name_out_dir name_oef_combined name_oef_gm name_oef_wm;
end;

