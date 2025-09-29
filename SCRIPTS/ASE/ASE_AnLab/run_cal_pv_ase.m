
function run_cal_pv_ase(folder, nnn, numEcho, numFrame, numZshimming, maxDTE, dteThresh1, dteThresh2, hct)

disp('run_cal_pv_ase');

name_mc_dir = sprintf('%s/MC_ASE', folder);
name_orig_dir = sprintf('%s/PVC', folder);
name_out_dir = sprintf('%s/PVC', folder);
name_dir_t1 = sprintf('%s', folder);

if ~exist(name_mc_dir) || ~exist(name_orig_dir) || ~exist(name_dir_t1)
    disp('Run non-PVC pipeline first!');
    return;
end

if ~exist(sprintf('%s',name_out_dir))
    mkdir(sprintf('%s',name_out_dir));
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% load the T1 registered ASE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
name_brain = sprintf('%s/%s_ase_0_brain_T1_111.nii.gz',name_orig_dir,nnn);
name_mask = sprintf('%s/%s_ase_0_brain_mask_T1_111.nii.gz',name_orig_dir,nnn);
infoBrain = load_nifti(name_brain);
infoMask = load_nifti(name_mask);
nx = infoMask.pixdim(2);
ny = infoMask.pixdim(3);
nz = infoMask.pixdim(4);

brainArr = double(infoBrain.vol);
maskArr = double(infoMask.vol);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
name_gm = sprintf('%s/%s_t1_spm_gm_111.nii.gz', name_orig_dir, nnn);
name_wm = sprintf('%s/%s_t1_spm_wm_111.nii.gz', name_orig_dir, nnn);
name_csf = sprintf('%s/%s_t1_spm_csf_111.nii.gz', name_orig_dir, nnn);

name_gm_out = sprintf('%s/%s_ase_prob_gm.nii.gz', name_out_dir, nnn);
name_wm_out = sprintf('%s/%s_ase_prob_wm.nii.gz', name_out_dir, nnn);
name_csf_out = sprintf('%s/%s_ase_prob_csf.nii.gz', name_out_dir, nnn);

gm_image = load_nifti(name_gm);
wm_image = load_nifti(name_wm);
csf_image = load_nifti(name_csf);

gm  = gm_image.vol;
wm  = wm_image.vol;
csf = csf_image.vol;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

total = gm+wm+csf;

gm = gm ./ (total+eps);
wm = wm ./ (total+eps);
csf = csf ./ (total+eps);

brain = gm+wm;
clear total;

%%%%%

gm_image.vol = gm;
wm_image.vol = wm;
csf_image.vol = csf;

save_nifti(gm_image, name_gm_out);
save_nifti(wm_image, name_wm_out);
save_nifti(csf_image, name_csf_out);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Load Data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
name1 = sprintf('%s/%s_ase1_upck_xr3d_dc_atl_111.nii.gz', name_orig_dir, nnn);
name2 = sprintf('%s/%s_ase2_upck_xr3d_dc_atl_111.nii.gz', name_orig_dir, nnn);
name3 = sprintf('%s/%s_ase3_upck_xr3d_dc_atl_111.nii.gz', name_orig_dir, nnn);
name_para = sprintf('%s/%s_ase_para.dat', name_orig_dir, nnn);

if exist(name_para) == 0
    fprintf('cannot open %s  %s\n', name1, name_para);
    return;
end;

Hct = hct*0.85;

[DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0] = load_ase_para(name_para);
fprintf('B0 = %f\n',B0);
DTE = DTE*1e-6;
TE1 = TE1/1000;
TE2 = TE2/1000;
TE3 = TE3/1000;

fprintf('i %d,  name %s, hct %f\n', i, name1, Hct/0.85);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if numEcho >= 1
    ase_image = load_nifti(name1);
    imASE1 = double(ase_image.vol);
    imASE2 = zeros(size(imASE1));
    imASE3 = zeros(size(imASE1));
end 

if numEcho >= 2
    ase_image = load_nifti(name2);
    imASE2 = double(ase_image.vol);
end

if numEcho == 3
    ase_image = load_nifti(name3);
    imASE3 = double(ase_image.vol);
end

[dimx, dimy, dimz, dimt] = size(imASE1);

if dimt ~= length(DTE)
    return;
end;

if dimt ~= numFrame
    return;
end;

name_sign = sprintf('%s/%s_motion_sign.dat', name_mc_dir, nnn);
[sign_motion1, sign_motion2, sign_motion3] = load_motion_sign_ase(name_sign, dimt);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% PVC %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if numEcho >= 1
    imASE = imASE1;
    name_out1_gm = sprintf('%s/%s_ase1_gm.nii.gz', name_out_dir, nnn);
    name_out1_wm = sprintf('%s/%s_ase1_wm.nii.gz', name_out_dir, nnn);
    name_out1_csf = sprintf('%s/%s_ase1_csf.nii.gz', name_out_dir, nnn);
end 

if numEcho >= 2
    imASE = cat(4,imASE,imASE2);
    name_out2_gm = sprintf('%s/%s_ase2_gm.nii.gz', name_out_dir, nnn);
    name_out2_wm = sprintf('%s/%s_ase2_wm.nii.gz', name_out_dir, nnn);
    name_out2_csf = sprintf('%s/%s_ase2_csf.nii.gz', name_out_dir, nnn);
end 

if numEcho == 3
    imASE = cat(4,imASE,imASE3);
    name_out3_gm = sprintf('%s/%s_ase3_gm.nii.gz', name_out_dir, nnn);
    name_out3_wm = sprintf('%s/%s_ase3_wm.nii.gz', name_out_dir, nnn);
    name_out3_csf = sprintf('%s/%s_ase3_csf.nii.gz', name_out_dir, nnn);
end 

name_out_mask_pv = sprintf('%s/%s_ase_pv_mask.nii.gz', name_out_dir, nnn); %% Chunwei Add 20210613

[imASE_gm, imASE_wm, imASE_csf, mask_pv] = correct_pv(imASE, maskArr, gm, wm, csf, nx, ny, nz);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

imASE_gm=single(imASE_gm);
imASE_wm=single(imASE_wm);
imASE_csf=single(imASE_csf);
mask_pv=single(mask_pv);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if(numEcho >= 1)
    imASE1_gm = imASE_gm(:,:,:,1:numFrame);
    imASE1_wm = imASE_wm(:,:,:,1:numFrame);
    imASE1_csf = imASE_csf(:,:,:,1:numFrame);
end

if(numEcho >= 2)
    imASE2_gm = imASE_gm(:,:,:,numFrame+1:2*numFrame);
    imASE2_wm = imASE_wm(:,:,:,numFrame+1:2*numFrame);
    imASE2_csf = imASE_csf(:,:,:,numFrame+1:2*numFrame);
else
    imASE2_gm = zeros(size(imASE1_gm));
    imASE2_wm = zeros(size(imASE1_wm));
    imASE2_csf = zeros(size(imASE1_csf));
end

if(numEcho >=3)
    imASE3_gm = imASE_gm(:,:,:,2*numFrame+1:3*numFrame);
    imASE3_wm = imASE_wm(:,:,:,2*numFrame+1:3*numFrame);
    imASE3_csf = imASE_csf(:,:,:,2*numFrame+1:3*numFrame);
else
    imASE3_gm = zeros(size(imASE1_gm));
    imASE3_wm = zeros(size(imASE1_wm));
    imASE3_csf = zeros(size(imASE1_csf));
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Calculate OEF %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dB = zeros(dimx, dimy, dimz);

imOEF_gm = zeros(dimx, dimy, dimz);
imLambda_gm = zeros(dimx, dimy, dimz);
imC_gm = zeros(dimx, dimy, dimz);
imR2_gm = zeros(dimx, dimy, dimz);
imR2P_gm = zeros(dimx, dimy, dimz);
imError_gm = zeros(dimx, dimy, dimz);

imOEF_wm = zeros(dimx, dimy, dimz);
imLambda_wm = zeros(dimx, dimy, dimz);
imC_wm = zeros(dimx, dimy, dimz);
imR2_wm = zeros(dimx, dimy, dimz);
imR2P_wm = zeros(dimx, dimy, dimz);
imError_wm = zeros(dimx, dimy, dimz);

maskArr_gm = zeros(size(maskArr));
maskArr_wm = zeros(size(maskArr));

I = find(mask_pv>0 & gm>=0.1 & brain>=0.2); %% Chunwei modifided 20210613: Remove "maskArr>0", not needed as already masked out in correct_pv_4oef  
maskArr_gm(I)=1;
clear I;

I = find(mask_pv>0 & wm>=0.1 & brain>=0.2); %% Chunwei modifided 20210613: Remove "maskArr>0", not needed as already masked out in correct_pv_4oef  
maskArr_wm(I)=1;
clear I;

if maxDTE == inf
    disp('NO MAX DTE');
else
    fprintf('MAX DTE = %s ms\n',num2str(maxDTE))
end

if dteThresh1 == 0.015 && dteThresh2 == 0.03
    fprintf('DTE Threshold = %s/%s s (%s/%s ms) (Default)\n',num2str(dteThresh1),num2str(dteThresh2),num2str(dteThresh1*1000),num2str(dteThresh2*1000));
else
    fprintf('DTE Threshold = %s/%s s (%s/%s ms)\n',num2str(dteThresh1),num2str(dteThresh2),num2str(dteThresh1*1000),num2str(dteThresh2*1000));
end

% [imOEF,    imLambda,    imC,    imR2,    imR2P,    imError]    = computeOEF_3e_WithoutDB_mc(imASE1   (:,:,:,1:end-numZshimming), imASE2   (:,:,:,1:end-numZshimming), imASE3   (:,:,:,1:end-numZshimming), mask_pv,    sign_motion1(1:end-numZshimming), sign_motion2(1:end-numZshimming), sign_motion3(1:end-numZshimming), Hct, TE1, TE2, TE3, B0, DTE(1:end-numZshimming), ZMoment1(1:end-numZshimming), numEcho, 2, dB, maxDTE,dteThresh1,dteThresh2);
[imOEF_gm, imLambda_gm, imC_gm, imR2_gm, imR2P_gm, imError_gm] = computeOEF_3e_WithoutDB_mc(imASE1_gm(:,:,:,1:end-numZshimming), imASE2_gm(:,:,:,1:end-numZshimming), imASE3_gm(:,:,:,1:end-numZshimming), maskArr_gm, sign_motion1(1:end-numZshimming), sign_motion2(1:end-numZshimming), sign_motion3(1:end-numZshimming), Hct, TE1, TE2, TE3, B0, DTE(1:end-numZshimming), ZMoment1(1:end-numZshimming), numEcho, 2, dB, maxDTE,dteThresh1,dteThresh2);
[imOEF_wm, imLambda_wm, imC_wm, imR2_wm, imR2P_wm, imError_wm] = computeOEF_3e_WithoutDB_mc(imASE1_wm(:,:,:,1:end-numZshimming), imASE2_wm(:,:,:,1:end-numZshimming), imASE3_wm(:,:,:,1:end-numZshimming), maskArr_wm, sign_motion1(1:end-numZshimming), sign_motion2(1:end-numZshimming), sign_motion3(1:end-numZshimming), Hct, TE1, TE2, TE3, B0, DTE(1:end-numZshimming), ZMoment1(1:end-numZshimming), numEcho, 2, dB, maxDTE,dteThresh1,dteThresh2);

%% Chunwei Add Error Norm ...
indSE = find(DTE==0);
indSE = indSE(1);
% imASE1_SE = squeeze(imASE1(:,:,:,indSE));
imASE1_gm_SE = squeeze(imASE1_gm(:,:,:,indSE));
imASE1_wm_SE = squeeze(imASE1_wm(:,:,:,indSE));
% imErrorNorm = imError ./ imASE1_SE;
imErrorNorm_gm = imError_gm ./ imASE1_gm_SE;
imErrorNorm_wm = imError_wm ./ imASE1_wm_SE;
% imASE1_SE(isnan(imASE1_SE)) = 0;
imErrorNorm_gm(isnan(imErrorNorm_gm)) = 0;
imErrorNorm_wm(isnan(imErrorNorm_wm)) = 0;
%% End Chunwei Add Error Norm ...

%% Chunwei Modify
% imOEF_combined    = (imOEF_gm    .* gm + imOEF_wm    .* wm)./(gm+wm+eps);
% imLambda_combined = (imLambda_gm .* gm + imLambda_wm .* wm)./(gm+wm+eps);
% imC_combined      = (imC_gm      .* gm + imC_wm      .* wm)./(gm+wm+eps);
% imR2_combined     = (imR2_gm     .* gm + imR2_wm     .* wm)./(gm+wm+eps);
% imR2P_combined    = (imR2P_gm    .* gm + imR2P_wm    .* wm)./(gm+wm+eps);
% imError_combined  = (imError_gm  .* gm + imError_wm  .* wm)./(gm+wm+eps);

gm_tmp = gm;
wm_tmp = wm;

%%%don't use the error to exclude the calculation.
%%gm_tmp(imError_gm>30|maskArr_gm==0) = 0;
%%wm_tmp(imError_wm>30|maskArr_wm==0) = 0;

gm_tmp(maskArr_gm==0) = 0;
wm_tmp(maskArr_wm==0) = 0;

imOEF_combined        = (imOEF_gm        .* gm_tmp + imOEF_wm        .* wm_tmp)./(gm_tmp+wm_tmp+eps);
imLambda_combined     = (imLambda_gm     .* gm_tmp + imLambda_wm     .* wm_tmp)./(gm_tmp+wm_tmp+eps);
imC_combined          = (imC_gm          .* gm_tmp + imC_wm          .* wm_tmp)./(gm_tmp+wm_tmp+eps);
imR2_combined         = (imR2_gm         .* gm_tmp + imR2_wm         .* wm_tmp)./(gm_tmp+wm_tmp+eps);
imR2P_combined        = (imR2P_gm        .* gm_tmp + imR2P_wm        .* wm_tmp)./(gm_tmp+wm_tmp+eps);
imError_combined      = (imError_gm      .* gm_tmp + imError_wm      .* wm_tmp)./(gm_tmp+wm_tmp+eps);
imErrorNorm_combined  = (imErrorNorm_gm  .* gm_tmp + imErrorNorm_wm  .* wm_tmp)./(gm_tmp+wm_tmp+eps);
%% End Chunwei Modify

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
name_mask_gm = sprintf('%s/%s_ase_mask_gm.nii.gz', name_out_dir, nnn);
name_mask_wm = sprintf('%s/%s_ase_mask_wm.nii.gz', name_out_dir, nnn);

% name_oef        = sprintf('%s/%s_OEF.nii.gz',    name_out_dir, nnn);
% name_lambda     = sprintf('%s/%s_LAMBDA.nii.gz', name_out_dir, nnn);
% name_r2         = sprintf('%s/%s_R2.nii.gz',     name_out_dir, nnn);
% name_r2p        = sprintf('%s/%s_R2P.nii.gz',    name_out_dir, nnn);
% name_c          = sprintf('%s/%s_C.nii.gz',      name_out_dir, nnn);
% name_error      = sprintf('%s/%s_Error.nii.gz',  name_out_dir, nnn);
% name_errorNorm  = sprintf('%s/%s_Error_Norm.nii.gz',  name_out_dir, nnn);

name_oef_combined        = sprintf('%s/%s_OEF_combined.nii.gz',    name_out_dir, nnn);
name_lambda_combined     = sprintf('%s/%s_LAMBDA_combined.nii.gz', name_out_dir, nnn);
name_r2_combined         = sprintf('%s/%s_R2_combined.nii.gz',     name_out_dir, nnn);
name_r2p_combined        = sprintf('%s/%s_R2P_combined.nii.gz',    name_out_dir, nnn);
name_c_combined          = sprintf('%s/%s_C_combined.nii.gz',      name_out_dir, nnn);
name_error_combined      = sprintf('%s/%s_Error_combined.nii.gz',  name_out_dir, nnn);
name_errorNorm_combined  = sprintf('%s/%s_Error_Norm_combined.nii.gz',  name_out_dir, nnn);

name_oef_gm        = sprintf('%s/%s_OEF_gm.nii.gz',    name_out_dir, nnn);
name_lambda_gm     = sprintf('%s/%s_LAMBDA_gm.nii.gz', name_out_dir, nnn);
name_r2_gm         = sprintf('%s/%s_R2_gm.nii.gz',     name_out_dir, nnn);
name_r2p_gm        = sprintf('%s/%s_R2P_gm.nii.gz',    name_out_dir, nnn);
name_c_gm          = sprintf('%s/%s_C_gm.nii.gz',      name_out_dir, nnn);
name_error_gm      = sprintf('%s/%s_Error_gm.nii.gz',  name_out_dir, nnn);
name_errorNorm_gm  = sprintf('%s/%s_Error_Norm_gm.nii.gz',  name_out_dir, nnn);

name_oef_wm        = sprintf('%s/%s_OEF_wm.nii.gz',    name_out_dir, nnn);
name_lambda_wm     = sprintf('%s/%s_LAMBDA_wm.nii.gz', name_out_dir, nnn);
name_r2_wm         = sprintf('%s/%s_R2_wm.nii.gz',     name_out_dir, nnn);
name_r2p_wm        = sprintf('%s/%s_R2P_wm.nii.gz',    name_out_dir, nnn);
name_c_wm          = sprintf('%s/%s_C_wm.nii.gz',      name_out_dir, nnn);
name_error_wm      = sprintf('%s/%s_Error_wm.nii.gz',  name_out_dir, nnn);
name_errorNorm_wm  = sprintf('%s/%s_Error_Norm_wm.nii.gz',  name_out_dir, nnn);

gm_image.vol = maskArr_gm;
save_nifti(gm_image, name_mask_gm);

wm_image.vol = maskArr_wm;
save_nifti(wm_image, name_mask_wm);

gm_image.vol = imOEF_gm;
save_nifti(gm_image, name_oef_gm);

gm_image.vol = imLambda_gm;
save_nifti(gm_image, name_lambda_gm);

gm_image.vol = imC_gm;
save_nifti(gm_image, name_c_gm);

gm_image.vol = imR2_gm;
save_nifti(gm_image, name_r2_gm);

gm_image.vol = imR2P_gm;
save_nifti(gm_image, name_r2p_gm);

gm_image.vol = imError_gm;
save_nifti(gm_image, name_error_gm);

gm_image.vol = imErrorNorm_gm;
save_nifti(gm_image, name_errorNorm_gm);

wm_image.vol = imOEF_wm;
save_nifti(wm_image, name_oef_wm);

wm_image.vol = imLambda_wm;
save_nifti(wm_image, name_lambda_wm);

wm_image.vol = imC_wm;
save_nifti(wm_image, name_c_wm);

wm_image.vol = imR2_wm;
save_nifti(wm_image, name_r2_wm);

wm_image.vol = imR2P_wm;
save_nifti(wm_image, name_r2p_wm);

wm_image.vol = imError_wm;
save_nifti(wm_image, name_error_wm);

wm_image.vol = imErrorNorm_wm;
save_nifti(wm_image, name_errorNorm_wm);

wm_image.vol = imOEF_combined;
save_nifti(wm_image, name_oef_combined);

wm_image.vol = imLambda_combined;
save_nifti(wm_image, name_lambda_combined);

wm_image.vol = imC_combined;
save_nifti(wm_image, name_c_combined);

wm_image.vol = imR2_combined;
save_nifti(wm_image, name_r2_combined);

wm_image.vol = imR2P_combined;
save_nifti(wm_image, name_r2p_combined);

wm_image.vol = imError_combined;
save_nifti(wm_image, name_error_combined);

wm_image.vol = imErrorNorm_combined;
save_nifti(wm_image, name_errorNorm_combined);

% fsl=sprintf('fslcpgeom %s %s', name_brain, name_oef_gm);        system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_lambda_gm);     system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_c_gm);          system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_r2_gm);         system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_r2p_gm);        system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_error_gm);      system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_errorNorm_gm);  system(fsl);
% 
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_oef_wm);        system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_lambda_wm);     system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_c_wm);          system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_r2_wm);         system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_r2p_wm);        system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_error_wm);      system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_errorNorm_wm);  system(fsl);
% 
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_oef_combined);        system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_lambda_combined);     system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_c_combined);          system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_r2_combined);         system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_r2p_combined);        system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_error_combined);      system(fsl);
% fsl=sprintf('fslcpgeom %s %s', name_brain, name_errorNorm_combined);  system(fsl);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
