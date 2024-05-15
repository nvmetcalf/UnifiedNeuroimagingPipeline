function moh_smooth_job(p, fwhm)
% spatially smooth images with FWHM
%
% Mohamed Seghier 05.08.2007
% =======================================
%
spm('defaults', 'FMRI');
if nargin == 1
    fwhm = [8 8 8] ;
end

jobs{1}.spatial{1}.smooth.fwhm = fwhm ;
jobs{1}.spatial{1}.smooth.dtype = 0 ;

jobs{1}.spatial{1}.smooth.data{1} = p(1,:) ;
jobs{1}.spatial{1}.smooth.data{2} = p(2,:) ;
spm_jobman('run' , jobs) ;

return;
