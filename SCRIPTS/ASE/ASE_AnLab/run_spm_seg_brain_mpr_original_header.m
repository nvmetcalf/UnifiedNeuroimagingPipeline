%% Subroutine for spm T1 segmentation
%% AnLab 2025/04/14

function run_spm_seg_brain_mpr_original_header(name_mpr)

%please update this with where spm12b is installed on your machine
spm_path_hard = '/data/nil-bluearc/vlassenko/Pipeline/SCRIPTS/spm12';

spm('defaults', 'FMRI');

gunzip(name_mpr);
name_mpr_unzipped = strrep(name_mpr, '.nii.gz', '.nii');

%% 2. spm segmentation
nameT1 = sprintf('%s,1',name_mpr_unzipped);
t1SegBatch{1}.spm.spatial.preproc.channel.vols{1} = nameT1;
t1SegBatch{1}.spm.spatial.preproc.channel.biasreg = 0.001;
t1SegBatch{1}.spm.spatial.preproc.channel.biasfwhm = 60;
t1SegBatch{1}.spm.spatial.preproc.channel.write = [0 1];
t1SegBatch{1}.spm.spatial.preproc.tissue(1).tpm = {sprintf('%s/tpm/TPM.nii,1', spm_path_hard)};
t1SegBatch{1}.spm.spatial.preproc.tissue(1).ngaus = 1;
t1SegBatch{1}.spm.spatial.preproc.tissue(1).native = [1 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(1).warped = [0 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(2).tpm = {sprintf('%s/tpm/TPM.nii,2', spm_path_hard)};
t1SegBatch{1}.spm.spatial.preproc.tissue(2).ngaus = 1;
t1SegBatch{1}.spm.spatial.preproc.tissue(2).native = [1 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(2).warped = [0 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(3).tpm = {sprintf('%s/tpm/TPM.nii,3', spm_path_hard)};
t1SegBatch{1}.spm.spatial.preproc.tissue(3).ngaus = 2;
t1SegBatch{1}.spm.spatial.preproc.tissue(3).native = [1 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(3).warped = [0 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(4).tpm = {sprintf('%s/tpm/TPM.nii,4', spm_path_hard)};
t1SegBatch{1}.spm.spatial.preproc.tissue(4).ngaus = 3;
t1SegBatch{1}.spm.spatial.preproc.tissue(4).native = [1 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(4).warped = [0 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(5).tpm = {sprintf('%s/tpm/TPM.nii,5', spm_path_hard)};
t1SegBatch{1}.spm.spatial.preproc.tissue(5).ngaus = 4;
t1SegBatch{1}.spm.spatial.preproc.tissue(5).native = [1 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(5).warped = [0 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(6).tpm = {sprintf('%s/tpm/TPM.nii,6', spm_path_hard)};
t1SegBatch{1}.spm.spatial.preproc.tissue(6).ngaus = 2;
t1SegBatch{1}.spm.spatial.preproc.tissue(6).native = [0 0];
t1SegBatch{1}.spm.spatial.preproc.tissue(6).warped = [0 0];
t1SegBatch{1}.spm.spatial.preproc.warp.mrf = 1;
t1SegBatch{1}.spm.spatial.preproc.warp.cleanup = 1;
t1SegBatch{1}.spm.spatial.preproc.warp.reg = [0 0.001 0.5 0.05 0.2];
t1SegBatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
t1SegBatch{1}.spm.spatial.preproc.warp.fwhm = 0;
t1SegBatch{1}.spm.spatial.preproc.warp.samp = 3;
t1SegBatch{1}.spm.spatial.preproc.warp.write = [0 0];
spm_jobman('run', t1SegBatch);
%% 3. zip seg results
%if error here, run with full file path
[mpr_dir, mpr_name] = get_file_dir_name(name_mpr_unzipped);

nameC1 = sprintf('%s/c1%s', mpr_dir, mpr_name);
nameC2 = sprintf('%s/c2%s', mpr_dir, mpr_name);
nameC3 = sprintf('%s/c3%s', mpr_dir, mpr_name);
nameC4 = sprintf('%s/c4%s', mpr_dir, mpr_name);
nameC5 = sprintf('%s/c5%s', mpr_dir, mpr_name);
nameM  = sprintf('%s/m%s', mpr_dir, mpr_name);
nameT1 = sprintf('%s',     name_mpr_unzipped);

gzip(nameC1);gzip(nameC2);gzip(nameC3);
gzip(nameC4);gzip(nameC5);gzip(nameM);
delete(nameC1);delete(nameC2);delete(nameC3);
delete(nameC4);delete(nameC5);delete(nameM);delete(nameT1);

% %% 4. Take care of header
nameC1Gz = strrep(nameC1, '.nii', '.nii.gz');
nameC2Gz = strrep(nameC2, '.nii', '.nii.gz');
nameC3Gz = strrep(nameC3, '.nii', '.nii.gz');
nameC4Gz = strrep(nameC4, '.nii', '.nii.gz');
nameC5Gz = strrep(nameC5, '.nii', '.nii.gz');
nameMGz  = strrep(nameM,  '.nii', '.nii.gz');

% The header and image is not consistent, use load_untouch_nii

resave_file_using_header(nameC1Gz, nameC1Gz, name_mpr);
resave_file_using_header(nameC2Gz, nameC2Gz, name_mpr);
resave_file_using_header(nameC3Gz, nameC3Gz, name_mpr);
resave_file_using_header(nameC4Gz, nameC4Gz, name_mpr);
resave_file_using_header(nameC5Gz, nameC5Gz, name_mpr);
resave_file_using_header(nameC1Gz, nameC1Gz, name_mpr);
resave_file_using_header(nameMGz,  nameMGz,  name_mpr);

% %% 5. generate hard segment maps...
threshold = 0.9;

nameBrain = strrep(name_mpr, '.nii.gz', '_brain.nii.gz');
nameMask  = strrep(name_mpr, '.nii.gz', '_brain_mask.nii.gz');
nameSeg   = strrep(name_mpr, '.nii.gz', '_spm_seg.nii.gz');

nameCSF = strrep(name_mpr, '.nii.gz', '_spm_csf.nii.gz');
nameGM  = strrep(name_mpr, '.nii.gz', '_spm_gm.nii.gz');
nameWM  = strrep(name_mpr, '.nii.gz', '_spm_wm.nii.gz');

% if exist(nameBrain) ~= 0
% 	return;
% end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
niiT1 = load_untouch_nii(name_mpr);
px = niiT1.hdr.dime.pixdim(2);
py = niiT1.hdr.dime.pixdim(3);
pz = niiT1.hdr.dime.pixdim(4);

niiM = load_untouch_nii(nameMGz);
niiC1 = load_untouch_nii(nameC1Gz);
niiC2 = load_untouch_nii(nameC2Gz);
niiC3 = load_untouch_nii(nameC3Gz);

c1 = double(niiC1.img); minC1 = min(c1(:)); maxC1=max(c1(:));
c2 = double(niiC2.img); minC2 = min(c2(:)); maxC2=max(c2(:));
c3 = double(niiC3.img); minC3 = min(c3(:)); maxC3=max(c3(:));

%%%using this is the same as using the scale/inter in the header to rescale the image
c1 = (c1-minC1)/(maxC1-minC1+eps);
c2 = (c2-minC2)/(maxC2-minC2+eps);
c3 = (c3-minC3)/(maxC3-minC3+eps);

seg = zeros(size(c1));
c1n = c1 ./(c1+c2+c3+eps);
c2n = c2 ./(c1+c2+c3+eps);
c3n = c3 ./(c1+c2+c3+eps);

mk=c1+c2+c3;
I1 = find(mk>=threshold);
I0 = find(mk<threshold);
mk(I1) = 1;
mk(I0) = 0;
clear I1 I0;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%fill some holes in 3D

mk = imfill(mk, 'holes');

[dimx, dimy, dimz]=size(mk);

for i=1:dimx,
   mk(i,:,:) = imfill(squeeze(mk(i,:,:)),'holes');
end;

for i=1:dimy,
   mk(:,i,:) = imfill(squeeze(mk(:,i,:)),'holes');
end;

for i=1:dimz,
   mk(:,:,i) = imfill(squeeze(mk(:,:,i)),'holes');
end;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

I0 = find(mk==0);
niiM.img(I0) = 0;

I_gm = find(c1n >= c2n & c1n>=c3n & mk>0);
I_wm = find(c2n >= c1n & c2n>=c3n & mk>0);
I_csf = find(c3n >= c1n & c3n>=c2n & mk>0);

seg(I_gm)=2;
seg(I_wm)=3;
seg(I_csf)=1;

save_untouch_nii(niiM, nameBrain);

sign_keepscale = 0;

nii_out = generate_nifti_with_updated_image(niiT1, seg, px, py, pz, 4, 16, sign_keepscale);
save_untouch_nii(nii_out, nameSeg);

nii_out = generate_nifti_with_updated_image(niiT1, mk, px, py, pz, 4, 16, sign_keepscale);
save_untouch_nii(nii_out, nameMask);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
c1n(I0) = 0;
c2n(I0) = 0;
c3n(I0) = 0;

nii_out = generate_nifti_with_updated_image(niiT1, c1n, px, py, pz, 16, 32, sign_keepscale);
save_untouch_nii(nii_out, nameGM);

nii_out = generate_nifti_with_updated_image(niiT1, c2n, px, py, pz, 16, 32, sign_keepscale);
save_untouch_nii(nii_out, nameWM);

nii_out = generate_nifti_with_updated_image(niiT1, c3n, px, py, pz, 16, 32, sign_keepscale);
save_untouch_nii(nii_out, nameCSF);

