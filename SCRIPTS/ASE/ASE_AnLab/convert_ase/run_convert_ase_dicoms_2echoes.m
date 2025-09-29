
function run_convert_ase_dicoms_2echoes(subjNow, name_dir1, name_dir2, name_dir_ase)

%subjNow = 'nick';
%name_dir1 = '/data/anlab/Yasheng/WWISH_whole/OEF_Calculation_AnLab/images_tmp/30/DICOM';
%name_dir2 = '/data/anlab/Yasheng/WWISH_whole/OEF_Calculation_AnLab/images_tmp/32/DICOM';
%name_dir_ase = '/data/anlab/Yasheng/WWISH_whole/OEF_Calculation_AnLab/images_tmp/ASE/Original';

dcm2niix1 = sprintf('dcm2niix -9 -b n -z y -v 0 -f %s_ase_1 -o %s %s', subjNow, name_dir_ase, name_dir1);
system(dcm2niix1);
dcm2niix2 = sprintf('dcm2niix -9 -b n -z y -v 0 -f %s_ase_2 -o %s %s', subjNow, name_dir_ase, name_dir2);
system(dcm2niix2);

name_ase_2_e2 = sprintf('%s/%s_ase_2_e2.nii.gz', name_dir_ase, subjNow);

name_ase_1 = sprintf('%s/%s_ase_1.nii.gz', name_dir_ase, subjNow);
name_ase_2 = sprintf('%s/%s_ase_2.nii.gz', name_dir_ase, subjNow);
name_ase_3 = sprintf('%s/%s_ase_3.nii.gz', name_dir_ase, subjNow);

mv = sprintf('mv %s %s', name_ase_2_e2, name_ase_2);
system(mv);

cp = sprintf('cp %s %s', name_ase_2, name_ase_3);
system(cp);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
name_para = sprintf('%s/%s_ase_para.dat', name_dir_ase, subjNow);
[num_dicoms, DTE, TE1, TE2, ZMoment1, ZMoment2, B0] = getASEParameters_2echoes(name_dir1, name_dir2);

save_ase_para(DTE, TE1, TE2, TE2, ZMoment1, ZMoment2, ZMoment2, B0, name_para);

