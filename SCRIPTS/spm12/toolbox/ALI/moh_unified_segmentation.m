function moh_unified_segmentation(V, c4prior, voxsize, mask, write_tissue)
% based on spm segmentation routines
%   V: volume structure to be segmented
%   c4prior: image that defines the spatial priors for the extra class
%   mask image (optional; default = empty)
%
% Mohamed Seghier 02.07.2013
% =======================================
%

% global defaults ;
%if ~isstruct(V), V = spm_vol(V) ; end

%[pth,nam,ext,toto] = spm_fileparts(V.fname) ;

% Prepare the job for spm_preproc_run and spm_preproc8
% -------------------------------------------------------------------------
for n=1:size(V,1)
    job.channel(n).vols{1} = V ;
    job.channel(n).biasreg = 0.01 ;
    job.channel(n).biasfwhm = 70 ;
    if write_tissue
        job.channel(n).write = [0 1] ;
    else
        job.channel(n).write = [0 0] ;
    end
end
% gray matter
job.tissue(1).tpm{1} = fullfile(spm('Dir'), 'tpm', 'TPM.nii,1') ;
job.tissue(1).ngaus = 2 ; % old value = 2
if write_tissue
    job.tissue(1).native = [0 1] ; % [0 1] if needed for DARTEL
    job.tissue(1).warped = [1 0] ;
else
    job.tissue(1).native = [0 0] ; % [0 1] if needed for DARTEL
    job.tissue(1).warped = [0 0] ;
end
% white matter
job.tissue(2).tpm{1} = fullfile(spm('Dir'), 'tpm', 'TPM.nii,2') ;
job.tissue(2).ngaus = 2 ;
if write_tissue
    job.tissue(2).native = [0 1] ; % [0 1] if needed for DARTEL
    job.tissue(2).warped = [1 0] ;
else
    job.tissue(2).native = [0 0] ; % [0 1] if needed for DARTEL
    job.tissue(2).warped = [0 0] ;
end
% CSF
job.tissue(3).tpm{1} = fullfile(spm('Dir'), 'tpm', 'TPM.nii,3') ;
job.tissue(3).ngaus = 2 ;
if write_tissue
    job.tissue(3).native = [0 1] ; % [0 1] if needed for DARTEL
    job.tissue(3).warped = [1 0] ;
else
    job.tissue(3).native = [0 0] ; % [0 1] if needed for DARTEL
    job.tissue(3).warped = [0 0] ;
end
% Extra (lesion) class
job.tissue(4).tpm{1} = c4prior ;
job.tissue(4).ngaus = 2 ;
job.tissue(4).native = [0 1] ; % [0 1] when needed for DARTEL
job.tissue(4).warped = [1 0] ;
% skull matter
job.tissue(5).tpm{1} = fullfile(spm('Dir'), 'tpm', 'TPM.nii,4') ;
job.tissue(5).ngaus = 3 ;
job.tissue(5).native = [0 0] ;
job.tissue(5).warped = [0 0] ;
% scalp matter
job.tissue(6).tpm{1} = fullfile(spm('Dir'), 'tpm', 'TPM.nii,5') ;
job.tissue(6).ngaus = 4 ;
job.tissue(6).native = [0 0] ;
job.tissue(6).warped = [0 0] ;
% other
job.tissue(7).tpm{1} = fullfile(spm('Dir'), 'tpm', 'TPM.nii,6') ;
job.tissue(7).ngaus = 3 ; % old value = 3
job.tissue(7).native = [0 0] ;
job.tissue(7).warped = [0 0] ;

% warping options
job.warp.affreg = 'mni' ;
%job.warp.reg = [0 0.03 0.6 0.07 0.3] ;
job.warp.reg = [0 0.001 0.5 0.05 0.2] ;
job.warp.samp = 3 ;
job.warp.bb = NaN(2,3) ;
job.warp.vox = voxsize ;
job.warp.mrf = 2 ;
job.msk = mask ;
if write_tissue
    job.warp.cleanup = 1 ;
    job.warp.write = [1 1] ;
    job.savemat = 1 ;
else
    job.warp.cleanup = 0 ;
    job.warp.write = [0 0] ;
    job.savemat = 0 ;
end
% unified segmentation steps
% --------------------------
% --------------------------

% run the combined segmentation-normalisation procedure
% -----------------------------------------------------
% check data, tissue and nb-gaussians
spm_preproc_run(job,'CHECK') ;

% if OK, run the segmentation
spm_preproc_run(job,'RUN') ;
%Res = spm_preproc8(obj)
disp('###### New unified Segmentation-Normalisation.................DONE!!');


return;


%=======================================================================
%=======================================================================
