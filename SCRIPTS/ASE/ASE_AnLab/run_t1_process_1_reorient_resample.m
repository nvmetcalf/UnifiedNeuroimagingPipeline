%% Subroutine for T1 reorientation and resampling to 1x1x1
%% AnLab 2025/04/14

function run_t1_process_1_reorient_resample(dir_t1, nnn)

name_dir_in = sprintf('%s', dir_t1);
name_dir_out = dir_t1;

name_in = sprintf('%s/%s_t1.nii.gz', name_dir_in, nnn);
name_out = sprintf('%s/%s_t1.nii.gz', name_dir_out, nnn);

fsl = sprintf('fslreorient2std %s %s', name_in, name_out);
disp(fsl);
system(fsl);

resampleLinear = sprintf('flirt -in %s -ref %s -applyisoxfm 1 -o %s', name_out, name_out, name_out);
disp(resampleLinear);
system(resampleLinear);

clear fsl name_in name_out;

