%% To run this code optimally, you should have your data proprocessed and 
% talairach atlas aligned. However, you should not include any global
% signal or white matter regressors. 
%
% Things you will need:
% A 'conc' file - this is a file that lists all BOLD resting scans
% a 'format' file - this specifies high motion or DVAR frames that should
% be excluded from the analysis (this is fairly important 
%

clear
switches.homotopic = 1; % 0 to use gray matter reference, 1 to use homotopic ROI reference
switches.range = 4; % This is the range of TRs used in the cross-correlation 
% (e.g. if you have a TR=2.5s and range=4 you can identify lags up to 5s forward and backward). 
% Generally, you want twice as large with graymatter ref as homotopic ref.
switches.nans = 0; % This will ...
switches.corrthreshold = 0; % This is the minimum correlation that will be allowed between voxel & reference. Anything below this is set to 0 or nan.
switches.minframes = 100;
switches.nifti=1;
switches.atlas='talairach'; %'MNI' or 'talairach'
switches.TR=2;
switches.savepng=1;
switches.QC = 1; % Make an image of the BOLD ave to make sure everything is registering properly.

sublist='sampledata/SampleSubjectList.txt';
fid=fopen(sublist);
patids=textscan(fid,'%s\n');
patid=patids{1}{1};
switches.lesion = 'sampledata/FCS_024_A/FCS_024_A_lesion_333.nii';
concfile = 'sampledata/FCS_024_A/FCS_024_A_faln_dbnd_xr3d_atl_g7_bpss_resid_nii.conc';
tmask = 'sampledata/FCS_024_A/tmask.txt';
outdir = 'sampledata/FCS_024_A_results';

[LL]=MapLag(concfile,tmask,outdir,switches)

