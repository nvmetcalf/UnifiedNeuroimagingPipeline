
%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

function run_process_ase_2_prepare0(name_dir_ase, nnn);

    name_in = sprintf('%s/%s_ase1_upck_xr3d_dc_atl.nii.gz', name_dir_ase, nnn);
    name_splitted = sprintf('%s/%s_ase_1_splitted', name_dir_ase, nnn);

    name_out_0 = sprintf('%s/%s_ase_0.nii.gz', name_dir_ase, nnn);
    name_splitted_0 = sprintf('%s/%s_ase_1_splitted0000.nii.gz', name_dir_ase, nnn);

    if exist(name_in)== 0
        clear nnn name_in name_splitted name_out_0 name_splitted_0;
        return;
    end;

    fsl = sprintf('fslsplit %s %s', name_in, name_splitted);
    disp(fsl);
    system(fsl);

    mv = sprintf('mv %s %s', name_splitted_0, name_out_0);
    disp(mv);
    system(mv);

    rm = sprintf('rm %s/%s_ase_1_splitted*.nii.gz', name_dir_ase, nnn);
    system(rm);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%bet
    name_in = sprintf('%s/%s_ase_0.nii.gz', name_dir_ase, nnn);

    name_brain = sprintf('%s/%s_ase_0_brain.nii.gz', name_dir_ase, nnn);
    bet = sprintf('bet %s %s -m -f 0.25', name_in, name_brain);
    system(bet);

    clear bet name_in name_splitted name_out_0 name_splitted_0;

