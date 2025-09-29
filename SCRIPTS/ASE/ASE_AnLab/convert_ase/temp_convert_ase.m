
subjNow = 'nick';
name_dir1 = '/data/nil-bluearc/ances_prod/Scans/HIV_PRISMA/sub-500552A/ses-032125/DICOMS/30/DICOM';
name_dir2 = '/data/nil-bluearc/ances_prod/Scans/HIV_PRISMA/sub-500552A/ses-032125/DICOMS/32/DICOM';

name_dir_ase = '/data/nil-bluearc/vlassenko/Pipeline/Projects/ASE_Test/Participants/sub-500552A_ses-032125/ASE/Original';

run_convert_ase_dicoms_2echoes(subjNow, name_dir1, name_dir2, name_dir_ase);
