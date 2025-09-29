
%% Subroutine for ASE pipeline
%% AnLab 2025/02/10


function run_process_ase_1_mc(name_dir_ase, nnn, numEcho, numZshimming)

    name_dir_mc       = sprintf('%s/MC_ASE',         name_dir_ase);
    name_dir_working  = sprintf('%s/MC_ASE_working', name_dir_ase);
    name_dir_original = sprintf('%s',       name_dir_ase);

    num_encoding_tables = numZshimming;
    num_encoding_tables_minus_1 = num_encoding_tables-1;

    %%%%thre_roation is computed as 2mm motion in 50mm radius head, 2/50=0.04radian
    %%%%mcflirt output is the frame-to-frame rotation
    %%%thre_rotation = 2.2918/180*pi;
    thre_translation = 2;
    thre_rotation = 0.04;

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%     for indEcho = 1:numEcho
%         name_in = sprintf('%s/%s_ase%d_upck_xr3d_dc_atl.nii.gz',  name_dir_original, nnn, indEcho);
%         name_out = sprintf('%s/%s_ase%d_upck_xr3d_dc_atl.nii.gz', name_dir_ase,      nnn, indEcho);
% 
%         reorient = sprintf('fslreorient2std %s %s', name_in, name_out);
%         disp(reorient);
%         system(reorient);
%         
%         clear name_in name_out reorient; 
%     end;
    
    cp = sprintf('cp %s/%s_ase_para.dat %s', name_dir_original, nnn, name_dir_ase);
    disp(cp);
    system(cp);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    for indEcho = 1:numEcho
        name_in = sprintf('%s/%s_ase%d_upck_xr3d_dc_atl.nii.gz', name_dir_ase, nnn, indEcho);

        %%%concatenate
    
        nii = load_untouch_nii(name_in);
        name_ase_in = sprintf('%s/%s_%d_upck_xr3d_dc_atl.nii.gz', name_dir_working, nnn, indEcho);

        if indEcho ==1 %% Echo 1  
            px = nii.hdr.dime.pixdim(2);
            py = nii.hdr.dime.pixdim(3);
            pz = nii.hdr.dime.pixdim(4);
            im1 = nii.img;
            [dimx, dimy, dimz, dimt] = size(im1);
            fprintf('dim %d %d %d %d, p %f %f %f\n', dimx, dimy, dimz, dimt, px, py, pz);
            sign_ase_orig_out = -1*ones(dimt, 3);
        else
            im_now = nii.img;
            im_now_add1 = zeros(dimx, dimy, dimz, dimt+1);
            im_now_add1(:,:,:,1) = im1(:,:,:,1);
            im_now_add1(:,:,:,2:dimt+1) = im_now;
            nii.img = im_now_add1; nii.hdr.dime.dim(5) = nii.hdr.dime.dim(5)+1;
        end
        save_untouch_nii(nii, name_ase_in);

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        name_ase_out = sprintf('%s/%s_mc_%d.nii.gz', name_dir_working, nnn,indEcho);
        mcflirt = sprintf('mcflirt -cost mutualinfo -in %s -refvol 0 -out %s -stages 4 -plots', name_ase_in, name_ase_out);
        disp(mcflirt);
        system(mcflirt); 

        nii = load_untouch_nii(name_ase_out); 
        if indEcho ~=1
            nii.img = nii.img(:,:,:,2:end);  nii.hdr.dime.dim(5) = nii.hdr.dime.dim(5)-1;
        end
        name_out = sprintf('%s/%s_ase_%d.nii.gz', name_dir_mc, nnn, indEcho);
        save_untouch_nii(nii, name_out);

        fsl = sprintf('fslcpgeom %s %s', name_in, name_out);
        system(fsl);

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%preparea par file in the right order
        name_par = sprintf('%s/%s_mc_%d.nii.gz.par', name_dir_working, nnn, indEcho);
        if indEcho == 1
            [rx, ry, rz, tx, ty, tz] = load_par(name_par, dimt);
        else
            [rx_tmp, ry_tmp, rz_tmp, tx_tmp, ty_tmp, tz_tmp] = load_par(name_par, dimt+1);  
            rx=rx_tmp(2:end); ry=ry_tmp(2:end); rz=rz_tmp(2:end);
            tx=tx_tmp(2:end); ty=ty_tmp(2:end); tz=tz_tmp(2:end);
        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        sign_ase = cal_motion_frame_by_thresholds(rx, ry, rz, tx, ty, tz, thre_rotation, thre_translation);
        sign_ase_out(:,indEcho) =  sign_ase;
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    name_motion_frames = sprintf('%s/%s_motion_sign.dat', name_dir_mc, nnn);
    fid = fopen(name_motion_frames, 'wt');
    for ii=1:dimt
        %fprintf(fid, '%d %d %d\n', sign_ase_out(ii,1), sign_ase_out(ii,2), sign_ase_out(ii,3));
        fprintf(fid, '%d %d\n', sign_ase_out(ii,1), sign_ase_out(ii,2));
    end
    fclose(fid);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    rm1 = sprintf('rm %s/%s_*.nii.gz', name_dir_working, nnn);
    system(rm1); clear rm1;

