function [dt_out_file tmask] = fs_surfproc_v3(dtseries_in,tmaskfile,TR,bpss_low,bpss_high,min_frames_remaining, regressors,bpss_tmask, dt_out_file_trailer)
% 1) load dtsieries & tmask

% 2) scrub and interpolate over scrubbed frames
% 3) bandpass filter
% 4) apply regressors
% 5) save a final dtseries

dt_out_file = [];

corrtype = 'pearson';
tic

% Set up butterworth filter
filterorder=1;
lopass=bpss_low/(0.5/TR);
hipass=bpss_high/(0.5/TR);
%[butta buttb]=butter(filterorder,[hipass lopass]);
try%see if it is a low pass
    [butta buttb]=butter(filterorder,[lopass hipass]);
catch
    [butta buttb]=butter(filterorder,[hipass lopass]);
end

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

%% CHECK TO SEE IF THERE IS A SEPERATE BANDPASS TEMPORAL MASK
if(exist('bpss_tmask'))
    BPSS_tmask = importdata(bpss_tmask);
else
    BPSS_tmask = tmask;
end

%% LOAD TIMECOURSE
if(~exist('dt_out_file_trailer'))
    dt_out_file_trailer = [ '_sr_bpss.ctx.dtseries.nii'];
end

%% Load dtseries and check orientation
if(~exist(dtseries_in))
    disp(['could not find ' dtseries_in]);
    return;
end

raw_cii = ft_read_cifti_mod(dtseries_in);

if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
    cii = raw_cii.data;
else
    cii = raw_cii.data';
end

vox = size(cii,1);
tp = size(cii,2);

%% Demean, detrend
cii = detrend(cii')';

prefilt_raw = cii'; %transpose to be the same dimensions as what will go into bandpassing

%% NUISANCE REGRESSION
regs = importdata(regressors,' ');
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


%% INTERPOLATE & BANDPASS
% INTERPOLATE MISSING FRAMES

cuts=find(BPSS_tmask==0);
k=1;
C{k}=cuts(k);
for j=2:length(cuts)
    td = cuts(j)-cuts(j-1);
    if td==1
        C{k} = [C{k} cuts(j)];
    else
        k = k + 1;
        C{k} = cuts(j);
    end
end
for m=1:length(C)
    k=C{m}(end)-C{m}(1)+1;
    fill=nan(vox,k);
    if m==1
        before = zeros(vox,1);
    else
        before = cii(:,C{m}(1)-1);
    end
    if C{m}(end)==tp
        after = zeros(vox,1);
    else
        after = cii(:,C{m}(end)+1);
    end
    for j=1:k
        fill(:,j)=before+(after-before)*(j/(k+1));%% CHECK ME!!!
    end
    cii(:,C{m}(1):C{m}(end))=fill;
end

% NOW BANDPASS
prefilt = cii';

pad = ceil(1/bpss_high);
prefilt = [zeros(pad,vox) ; prefilt ; zeros(pad,vox)];
prefilt_raw = [zeros(pad,vox) ; prefilt_raw ; zeros(pad,vox)];

postfilt = filtfilt(butta,buttb,prefilt);   %regressed data
postfilt_raw = filtfilt(butta,buttb,prefilt_raw);   %detrended only data

prefilt = prefilt((pad+1):(end-pad),:);
prefilt_raw = prefilt_raw((pad+1):(end-pad),:);

postfilt = postfilt((pad+1):(end-pad),:);
postfilt_raw = prefilt_raw((pad+1):(end-pad),:);

cii = postfilt';

%% Save output dtseries
%save frame aligned  and filtered cifti
BaseFileName = strip_extension(strip_extension(strip_extension(dtseries_in)));

if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
    raw_cii.data = postfilt_raw;
else
    raw_cii.data = postfilt_raw';
end

ft_write_cifti_mod([BaseFileName '_bpss.ctx.dtseries.nii'],raw_cii)

%save regressed and filtered cifti
if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
    raw_cii.data = cii;
else
    raw_cii.data = cii';
end

ft_write_cifti_mod([BaseFileName dt_out_file_trailer],raw_cii)

%save regressed cifti (no filtering)
if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
    raw_cii.data = prefilt;
else
    raw_cii.data = prefilt';
end

ft_write_cifti_mod([BaseFileName '_sr.ctx.dtseries.nii'],raw_cii)

toc
end


