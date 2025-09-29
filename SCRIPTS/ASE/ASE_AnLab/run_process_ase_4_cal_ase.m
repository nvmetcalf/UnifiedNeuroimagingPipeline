
%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

function run_process_ase_4_cal_ase(name_dir_ase, nnn, numEcho, numFrame, numZshimming, maxTau, tauThresh1, tauThresh2, f)

name_mc_dir        = sprintf('%s/MC_ASE',           name_dir_ase);
name_smoothing_dir = sprintf('%s/MC_ASE/smoothing', name_dir_ase);

num_encoding_steps = numZshimming;

nnn_root = nnn;
nnn_date = nnn;
nnn_time = nnn;

%f = get_hematocrit(nnn_root, name_dir_ase);
if f<0.00000001
    disp(nnn_root)
    clear nnn nnn_date nnn_time nnn_root;
    return;
end;
Hct = f*0.85;

name_para = sprintf('%s/%s_ase_para.dat', name_dir_ase, nnn);

[DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0] = load_ase_para(name_para);

fprintf('B0 = %f\n',B0);
DTE = DTE*1e-6;
TE1 = TE1/1000;
TE2 = TE2/1000;
TE3 = TE3/1000;

fprintf('name %s, hct %f\n', nnn, Hct/0.85);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
name_mask = sprintf('%s/%s_ase_0_brain_mask.nii.gz', name_dir_ase, nnn);
nii_mk = load_untouch_nii(name_mask);
px = nii_mk.hdr.dime.pixdim(2);
py = nii_mk.hdr.dime.pixdim(3);
pz = nii_mk.hdr.dime.pixdim(4);
maskArr = double(nii_mk.img);
I = find(maskArr>0);
maskArr(I) = 1;

name1 = sprintf('%s/%s_ase_1.nii.gz', name_smoothing_dir, nnn);
name2 = sprintf('%s/%s_ase_2.nii.gz', name_smoothing_dir, nnn);
name3 = sprintf('%s/%s_ase_3.nii.gz', name_smoothing_dir, nnn);

if numEcho >= 1
    nii1 = load_untouch_nii(name1);
    imASE1 = double(nii1.img);
    imASE2 = zeros(size(imASE1));
    imASE3 = zeros(size(imASE1));
end 

if numEcho >= 2
    nii2 = load_untouch_nii(name2);
    imASE2 = double(nii2.img);
end

if numEcho == 3
    nii3 = load_untouch_nii(name3);
    imASE3 = double(nii3.img);
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

%if mc_yes_no == 0
%   sign_motion1 = sign_motion1 .* 0;
%   sign_motion2 = sign_motion2 .* 0;
%   sign_motion3 = sign_motion3 .* 0;
%end;

%%%%%%%%%%%%calculate DB

dB = zeros(dimx, dimy, dimz);
imOEF = zeros(dimx, dimy, dimz);
imLambda = zeros(dimx, dimy, dimz);
imC = zeros(dimx, dimy, dimz);
imR2 = zeros(dimx, dimy, dimz);
imR2P = zeros(dimx, dimy, dimz);
imError = zeros(dimx, dimy, dimz);

if maxTau == inf
    disp('NO MAX Tau');
else
    fprintf('MAX Tau = %s ms\n',num2str(maxTau))
end

if tauThresh1 == 0.015 && tauThresh2 == 0.03
    fprintf('Tau Threshold = %s/%s ms (Default)\n',num2str(tauThresh1),num2str(tauThresh2));
else
    fprintf('Tau Threshold = %s/%s ms\n',num2str(tauThresh1),num2str(tauThresh2));
end

[imOEF, imLambda, imC imR2 imR2P imError] = computeOEF_3e_WithoutDB_mc(imASE1(:,:,:,1:end-numZshimming), imASE2(:,:,:,1:end-numZshimming), imASE3(:,:,:,1:end-numZshimming), maskArr, ...
                                                                       sign_motion1(1:end-numZshimming), sign_motion2(1:end-numZshimming), sign_motion3(1:end-numZshimming), ...
                                                                       Hct, TE1, TE2, TE3, B0, DTE(1:end-numZshimming), ZMoment1(1:end-numZshimming), numEcho, 2, dB, maxTau,tauThresh1,tauThresh2);

%% Calculate Error normalized by (first) SE intensity
indSE = find(DTE==0);
indSE = indSE(1);
imASE1_SE = squeeze(imASE1(:,:,:,indSE));
imErrorNorm = imError ./ (imASE1_SE+eps);
imErrorNorm(isnan(imErrorNorm)) = 0;

if numEcho == 1
    numMotion = sum(sign_motion1);
elseif numEcho == 2
    numMotion = sum(sign_motion1) + sum(sign_motion2);
elseif numEcho == 3
    numMotion = sum(sign_motion1) + sum(sign_motion2) + sum(sign_motion3);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   
name_oef        = sprintf('%s/%s_OEF.nii.gz', name_dir_ase, nnn);
name_lambda     = sprintf('%s/%s_LAMBDA.nii.gz', name_dir_ase, nnn);
name_r2         = sprintf('%s/%s_R2.nii.gz', name_dir_ase, nnn);
name_r2p        = sprintf('%s/%s_R2P.nii.gz', name_dir_ase, nnn);
name_c          = sprintf('%s/%s_C.nii.gz', name_dir_ase, nnn);
name_error      = sprintf('%s/%s_Error.nii.gz', name_dir_ase, nnn);
name_error_norm = sprintf('%s/%s_Error_Norm.nii.gz', name_dir_ase, nnn);

save_nii_yasheng(imOEF,       px, py, pz, 64, name_oef);
save_nii_yasheng(imLambda,    px, py, pz, 64, name_lambda);
save_nii_yasheng(imR2,        px, py, pz, 64, name_r2);
save_nii_yasheng(imR2P,       px, py, pz, 64, name_r2p);
save_nii_yasheng(imC,         px, py, pz, 64, name_c);
save_nii_yasheng(imError,     px, py, pz, 64, name_error);
save_nii_yasheng(imErrorNorm, px, py, pz, 64, name_error_norm);

fsl=sprintf('fslcpgeom %s %s', name_mask, name_oef);        system(fsl);
fsl=sprintf('fslcpgeom %s %s', name_mask, name_lambda);     system(fsl);
fsl=sprintf('fslcpgeom %s %s', name_mask, name_r2);         system(fsl);
fsl=sprintf('fslcpgeom %s %s', name_mask, name_r2p);        system(fsl);
fsl=sprintf('fslcpgeom %s %s', name_mask, name_c);          system(fsl);
fsl=sprintf('fslcpgeom %s %s', name_mask, name_error);      system(fsl);
fsl=sprintf('fslcpgeom %s %s', name_mask, name_error_norm); system(fsl);

