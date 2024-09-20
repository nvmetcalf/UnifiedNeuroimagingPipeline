function [dt_out_file tmask] = fs_surfproc_v5(dtseries_in,tmaskfile,TR,bpss_low,bpss_high,min_frames_remaining, regressors,dt_out_file_trailer,bpss_tmask,task_regressors)
% 1) load dtsieries & tmask

% 2) scrub and interpolate over scrubbed frames
% 3) bandpass filter
% 4) apply regressors
% 5) save a final dtseries

dt_out_file = [];
tic

% Set up butterworth filter
filterorder=1;
lopass=bpss_low/(0.5/TR);
hipass=bpss_high/(0.5/TR);
%[butta buttb]=butter(filterorder,[hipass lopass]);
try %see if it is a low pass
    [butta buttb]=butter(filterorder,[lopass hipass]);
catch
    [butta buttb]=butter(filterorder,[hipass lopass]);
end


%% LOAD TIMECOURSE
%if(~exist('dt_out_file_trailer'))
    dt_out_file_trailer = '_sr_bpss.ctx.dtseries.nii';
%end

%% Load dtseries and check orientation

cii = [];
tmask = [];
BPSS_tmask = [];

if(ischar(dtseries_in))    
    dtseries_in = {dtseries_in};
end

if(ischar(tmaskfile))    
    tmaskfile = {tmaskfile};
end

if(ischar(bpss_tmask))    
    bpss_tmask = {bpss_tmask};
end

BaseFileName = strip_extension(strip_extension(strip_extension(dtseries_in{1})));

for i = 1:length(dtseries_in)
    if(~exist(dtseries_in{i}))
        disp(['could not find ' dtseries_in(i)]);
        return;
    else
        disp(['Loading dtseries: ' dtseries_in{i}]);
    end

    raw_cii = ft_read_cifti_mod(dtseries_in{i});

    BaseFileName = strip_extension(strip_extension(strip_extension(dtseries_in{i})));

    if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
        cii = horzcat(cii, single(raw_cii.data));
    else
        cii = vertcat(single(raw_cii.data'));
    end

    %switches
    fprintf('\nLoading tmask: %s\n',tmaskfile{i});
    %% LOAD T-MASK 
    loaded_tmask = importdata(tmaskfile{i});
    %fprintf('Usable Frames %d/%d\n',sum(tmask),length(tmask));

    if(sum(loaded_tmask) == 0)
        disp('no frames remaining');
        return;
    else
        disp(['tmask has ' num2str(sum(loaded_tmask)) ' frames flagged as good.']);
    end

    % changed to percent frames remaining
    if (~isempty(min_frames_remaining) && (sum(loaded_tmask)/length(loaded_tmask))*100 < min_frames_remaining)
        dt_out_file = 0;
        disp('Not enough frames');
        return;
    end

    tmask = horzcat(tmask, loaded_tmask);
    
    %% CHECK TO SEE IF THERE IS A SEPERATE BANDPASS TEMPORAL MASK
    if(~isempty(bpss_tmask))
        BPSS_tmask = horzcat(BPSS_tmask, importdata(bpss_tmask{i}));
    else
        BPSS_tmask = horzcat(BPSS_tmask, loaded_tmask);
    end

end

raw_cii.data = [];

vox = size(cii,1);
tp = size(cii,2);

%% Demean, detrend
cii = detrend(cii')';

%% NUISANCE REGRESSION


if(strcmp(class(regressors),'char'))    
    regressors = {regressors};
end

regs = [];
task_regs = [];
for i = 1:length(regressors)
    disp(['Loading Nuisance Regressors: ' regressors{i}]);
    loaded_regs = importdata(regressors{i},' ');

    for i = 1:length(loaded_regs(1,:))
        loaded_regs(:,i) = detrend(loaded_regs(:,i)); %Detrend all regressors
        loaded_regs(:,i) = zscore(loaded_regs(loaded_regs(:,i) ~= 0, i)); % zscore regresors
    end

    if(isempty(regs))
        regs = loaded_regs;
    else
        start_row = length(regs(:,1)) + 1;
        start_col = length(regs(1,:)) + 1;
        temp_regs = zeros(start_row-1+length(loaded_regs(:,1)), start_col-1+length(loaded_regs(1,:)));
        temp_regs(1:start_row-1,1:start_col-1) = regs;
        temp_regs(start_row:start_row+length(loaded_regs(:,1))-1, start_col:start_col+length(loaded_regs(1,:))-1) = loaded_regs;
        regs = temp_regs;
        clear temp_regs;
        
    end
end

if(exist('task_regressors'))
    disp('Loading task regressors.');
    for i = 1:length(task_regressors)
        task_regs = vertcat(task_regs, importdata(task_regressors{i}, ' '));
    end
end

regs = horzcat(regs, task_regs);
    
ConstantRegressors = [];
%determines which regressors are constants
for i = 1:length(regs(1,:))
    if(max(regs(:,i)) == min(regs(regs(:,i) ~= 0,i)))   
        ConstantRegressors = horzcat(ConstantRegressors, i );
    end
end

constant = ones(size(regs,1),1);

for i = 1:length(ConstantRegressors)
    constant(regs(:,ConstantRegressors(i)) ~= 0) = 0;    % set the runs with constants already to 0 so the resting state runs are done correctly
end


% APPLY REGRESSORS
disp('Performing regression.');
for r = 1:vox
    voxel = cii(r,:)';
    [B,~,R] = regress(voxel,regs);
    cii(r,:) = R;
    betas(r,:)=B;
end

%save the betas to a dtseries.
beta_cii = raw_cii;
beta_cii.data = betas;
ft_write_cifti_mod([BaseFileName '_sr_betas.ctx.dtseries.nii'],beta_cii)


%% INTERPOLATE & BANDPASS
% INTERPOLATE MISSING FRAMES
%cii=cii(:,tmask==1);    %clear out the censored frames so that we can do the padding.

disp('Bandpass Step.');

run_boundaries = find(BPSS_tmask == 1);

pad = single(zeros(ceil(1/bpss_high),vox)');

for j = 1:length(run_boundaries)
    
    disp(['Run: ' num2str(j)]);
    
    run_start = run_boundaries(j);
    
    if(j == length(run_boundaries))
        run_end = length(tmask);
    else
        run_end = run_boundaries(j+1)-1;
    end
    
    %move through the frames of the run
    disp('Interpolating over censored frames')
    for i=run_start:run_end
        if(tmask(i) && ~tmask(i-1))
            %move backwards to find the range we will be interpolating over
            n = i-1;
            while(n > 2 && ~tmask(n))
                n = n - 1;
            end
            
            %fill in the gap with 1D linear interpolation
            step = (cii(:,i)-cii(:,n-1))/(i-(n-1)); % how much to increase or decrease by
            
            a = cii(:,n-1:i);
            
            %this fills in the values to linearly get from the start of
            %the "bad" spot, to the end of the bad spot.
            % the ends should equal the the original values at the end
            % of interpolation;
            for(l = 2:length(a(1,:)))
                a(:,l) = a(:,l-1) + step;
            end
            
            cii(:,n-1:i) = a;
        end
    end
    disp(['Bandpassing run: ' num2str(j)]);
    filtered_data = single(filtfilt(butta,buttb, [pad cii(:,run_start:run_end) pad]'));
    cii(:,run_start:run_end) = filtered_data(length(pad(1,:))+1 : length(filtered_data(:,1))-length(pad(1,:)),:)';
end

%% Save output dtseries
%save frame aligned  and detrended cifti
disp('Saving results.');
%save regressed and filtered cifti
if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
    raw_cii.data = cii;
else
    raw_cii.data = cii';
end

ft_write_cifti_mod([BaseFileName dt_out_file_trailer],raw_cii)
toc
end


