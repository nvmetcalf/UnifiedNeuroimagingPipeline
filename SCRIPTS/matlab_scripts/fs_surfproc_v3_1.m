function [dt_out_file tmask] = fs_surfproc_v3_1(dtseries_in,tmaskfile,TR,min_frames_remaining, regressors, dt_out_file_trailer)
% 1) load dtsieries & tmask

% 2) scrub and interpolate over scrubbed frames
% 3) bandpass filter
% 4) apply regressors
% 5) save a final dtseries

dt_out_file = [];

tic

%switches
fprintf('\nLoading tmask: %s\n',tmaskfile)
%% LOAD T-MASK 
tmask = importdata(tmaskfile);
%fprintf('Usable Frames %d/%d\n',sum(tmask),length(tmask));

if(sum(tmask) == 0)
    disp('no frames remaining');
    return;
else
    disp(['tmask has ' num2str(sum(tmask)) ' frames flagged as good.']);
end

% changed to percent frames remaining
if (~isempty(min_frames_remaining) && (sum(tmask)/length(tmask))*100 < min_frames_remaining)
    dt_out_file = 0;
    disp('Not enough frames');
    return;
end


%% LOAD TIMECOURSE
if(~exist('dt_out_file_trailer'))
    dt_out_file_trailer = [ '_sr.ctx.dtseries.nii'];
end

%% Load dtseries and check orientation
if(~exist(dtseries_in))
    disp(['could not find ' dtseries_in]);
    return;
end

disp('Loading cifti dtseries to regress...');
raw_cii = ft_read_cifti_mod(dtseries_in);

if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
    cii = raw_cii.data;
else
    cii = raw_cii.data';
end

vox = size(cii,1);

disp('Regressing surface timeseries...');
%% NUISANCE REGRESSION
disp('Loading regressor timeseries...');

regs = importdata(regressors);
regs = detrend(regs);%Detrend all regressors

% MASK 
regs_masked = regs(tmask==1,:); % mask excluded
regs = zscore(regs); % zscore regresors
regs = [regs ones(size(regs,1),1)]; % add column of 1's

% APPLY REGRESSORS
for r = 1:vox
    [B,~,R] = regress(cii(r,tmask==1)',regs_masked);
    cii(r,tmask==1) = R;
    betas(r,:)=B;
end

%% Save output dtseries
%save frame aligned  and filtered cifti
BaseFileName = strip_extension(strip_extension(strip_extension(dtseries_in)));

%save regressed and filtered cifti
if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
    raw_cii.data = cii;
else
    raw_cii.data = cii';
end

ft_write_cifti_mod([BaseFileName dt_out_file_trailer],raw_cii)

toc
end


