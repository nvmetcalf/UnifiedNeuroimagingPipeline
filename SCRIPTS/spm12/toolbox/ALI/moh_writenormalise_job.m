function moh_writenormalise_job(p,vox)
% after segmentation, write a normalised anatomical volume
%
% Mohamed Seghier 05.06.2006 // 13.07.2013
% ========================================
% 

% global defaults ;

[pth,nam,ext,toto] = spm_fileparts(deblank(p)) ; %#ok<NASGU>

jobs{1}.spm.spatial.normalise.write.woptions.bb = NaN(2,3) ;
jobs{1}.spm.spatial.normalise.write.woptions.vox = vox*[1 1 1] ;
jobs{1}.spm.spatial.normalise.write.woptions.interp =  5 ;
% jobs{1}.spm.spatial.normalise.write.subj.def = ...
%     {fullfile(pth,['y_' nam '.nii'])} ;
jobs{1}.spm.spatial.normalise.write.subj.def = ... 
    {spm_select('FPList',pth,['^y_' nam])};
jobs{1}.spm.spatial.normalise.write.subj.resample = ...
    {deblank(p)};
spm_jobman('run' , jobs) ;

return;
