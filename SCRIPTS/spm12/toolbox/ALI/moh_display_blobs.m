%% display one blob
function [] = moh_display_blobs(vb, thr, va)
% display an image on the canonical T1 image
% e.g. overlap functional on anatomical image
% input:
%   vb: functional/overlap volume (color coded)
%   thr: (1) threshold on signal (t-value)
%        (2) threshold on extent (nb voxels)
%   va: optional, anatomical volume (gray coded)
%
% ===============================================
% Mohamed Seghier, 13.11.2005
%

if nargin==2
    pa = fullfile(spm('Dir'),...
        'canonical', 'single_subj_T1.nii') ;
    va = spm_vol_nifti(pa);
end

if ~isstruct(vb), vb = spm_vol(vb) ; end

if length(thr) == 1, thr = [thr 1]; end

if length(vb) == 1
    spm_check_registration(va) ;
    imb = spm_read_vols(vb) ;
    mask = imb >= thr(1) ;
    mask = bwareaopen(mask,thr(2),18) ;
    ind = find(mask) ;
    [X,Y,Z] = ind2sub(vb.dim, ind) ;
    spm_orthviews('AddBlobs',1,[X';Y';Z'],double(imb(ind)),vb.mat) ;
    % spm_figure('Colormap','gray-jet') ;
else
    imb = zeros(vb(1).dim) ;
    for r=1:length(vb)
        
        tmp = spm_read_vols(vb(r)) >= thr(1) ;
        tmp = bwareaopen(tmp,thr(2),18) ;
        imb = imb + (power(2,r-1)*tmp) ;
        
    end
    spm_check_registration(va) ;
    ind = find(imb) ;
    [X,Y,Z] = ind2sub(vb(1).dim, ind) ;
    spm_orthviews('AddBlobs',1,[X';Y';Z'],double(imb(ind)),vb(1).mat) ;
    spm_figure('Colormap','gray-jet') ;
end

return ;
