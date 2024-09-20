function im_prior = moh_cleanup_prior(vC4, thr, clean_size, iti)
% clean up the priors for the iterative segmentation
%   vC4: volume structure of the prior image
%   thr: threshold, minimum probability value for the extra class tissue
%   clean_size: threshold, minimum size for the extra class tissue
%   iti: iteration of the segmentation run
% the new image im_prior will be used as a prior for the next segment run
%
% Mohamed Seghier 05.08.2008
% =======================================
%

connectivity = 18 ; % 18-connected neighborhood in 3D

if ~isstruct(vC4), vC4 = spm_vol(vC4) ; end

clean_size = floor(1000 * clean_size / (abs(vC4.mat(1,1))^3)) ;

[pth,nam,ext,toto] = spm_fileparts(vC4.fname) ;
nam = nam(4:end); % remove the initial "wc4"

imC4 = spm_read_vols(vC4) ;
% write a version of the estimated prior before clean up
vo = struct('fname',   fullfile(pth, ['wc4previous' num2str(iti) nam '.nii']),...
    'dim',     vC4.dim(1:3),...
    'dt',      [16 spm_platform('bigend')],...
    'mat',     vC4.mat,...
    'descrip', '4th class at previous iteration');
spm_write_vol(vo, imC4) ;


if nnz(find(imC4))
    imC4_cleaned = imC4 > thr ; % exclude small and noisy priors
    [imC4_cleaned_labeled,nbles] =spm_bwlabel(1*imC4_cleaned,connectivity);
    for ss=1:nbles
        if nnz(imC4_cleaned_labeled == ss) < clean_size
            imC4_cleaned(imC4_cleaned_labeled == ss) = 0 ;
        end
    end
    imC4 = imC4 .* imC4_cleaned ;
end
vo = struct('fname',   fullfile(pth, ['wc4prior' num2str(iti) nam '.nii']),...
    'dim',     vC4.dim(1:3),...
    'dt',      [16 spm_platform('bigend')],...
    'mat',     vC4.mat,...
    'descrip', '4th class prior for next iteration');
vC4 = spm_write_vol(vo, imC4) ;
[pth,nam,ext,toto] = spm_fileparts(vC4.fname) ;

% smooth the prior (to avoid sharp transitions due to the thresholding)
% with copy/delete intermediate steps for netwrok access
spm_smooth(vC4,fullfile(pth, ['s' nam ext]),4);
delete(fullfile(pth, [nam '.*'])) ;
im_tmp = spm_read_vols(spm_vol(fullfile(pth, ['s' nam ext]))) ;
spm_write_vol(vC4, im_tmp) ;
delete(fullfile(pth, ['s' nam '.*'])) ;

im_prior = vC4.fname ;


return;

