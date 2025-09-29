addpath('/data/nil-bluearc/vlassenko/Pipeline/Projects/ASE_Test/Participants/ASE_scripts/OEF_Calculation_AnLab/ASE_AnLab/NIFTI_yasheng');

%%update this line with the directory of your spm12b
addpath('/data/nil-bluearc/vlassenko/Pipeline/SCRIPTS/spm12');  

dir_t1 = '/data/nil-bluearc/vlassenko/Pipeline/Projects/ASE_Test/Participants/ASE_scripts/OEF_Calculation_AnLab/T1';

names_t1 = sprintf('%s/Original/*_t1.nii.gz', dir_t1);

names_t1 = dir(names_t1);
nums_t1 = length(names_t1);

for i=1:nums_t1,

   nnn = names_t1(i).name;
   nnn = strrep(nnn, '_t1.nii.gz', '');
   
   name_tmp = sprintf('%s/%s', dir_t1, names_t1(i).name);
   name_tmp = strrep(name_tmp, '.nii.gz', '_brain.nii.gz');
   
   if exist(name_tmp)
      clear nnn name_tmp;
      continue;
   end;

   fprintf('%s\n', nnn);
   
   run_t1_process_1_reorient_resample(dir_t1, nnn)
   run_t1_process_2_spm_seg(dir_t1, nnn)

   clear nnn name_tmp;

end;



