 function [LL]=MapLag(input_file,tmask, TR, time_range, homotopic, framematch, minframes, corrthreshold, nans, savepng, atlas)
% MAPLAG Generate a voxel-wise map of lag relative to global signal
%
%   [LL]=MapLag(concfile,tmask,outdir) Given a concfile, temporal mask
%   (tmask) and a outdir, MapLag will generate a lag map relative to the 
%   gray matter signal (see Hemodynamic Lag, Siegel et al., 2015) 
%   between -4TR and +4TR, and save the image it to outdir/lagmap.4dfp.img 
%   and output the Lag Lageralality score (LL) indicating side and severity
%   of lag.
%   
%   Some additional options if you wish:
%       lesion: give a lesion image to apply a mask before 
%           determining gray mater signal.
%       framematch: mask sure that every cross-correlation (-4TR:4TR) 
%           uses the same frames. (doesn't make much difference for me)
%       individual_gm: give a segmentation to use individual
%           gray matter.
%
%   Example: LL=MapLag('/data/nil-bluearc/corbetta/Studies/FCStroke/Subjects/FCS_024_A/FCmaps/FCS_024_A_faln_dbnd_xr3d_atl_g7_bpss_resid.conc','/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_024_A/movement/tmask.txt','/scratch/lagtest/FCS_024_A/')
%   Example2: [LL]=MapLag('/data/nil-bluearc/shimony/Jerrel/CONDR/W009/FCmaps/W009_faln_dbnd_xr3d_atl_g7_bpss_resid.conc','/data/nil-bluearc/shimony/Jerrel/CONDR/W009/FCmaps/W009_faln_dbnd_xr3d_atl_g7_bpss_resid.format','/data/nil-bluearc/shimony/Jerrel/CONDR/LagTest/W009/')
% 
%
% User Inputs:
%   concfile: BOLD 4dfp .conc file
%   tmask: temporal mask of ones and zeros
%   lesion: lesion mask (optional)
%   outdir: where to write results
%
% Preprocessing:
% Prior to running this, you should do the followingresults_Wed_Oct__5_16:54:58_CDT_2016.txt preprocessing to your rfMRI data:
% 0) minimal timecourse cleanup (for example (1) compensation for asynchronous slice acquisition using sinc interpolation; (2) elimination of odd/even slice intensity differences resulting from inter- leaved acquisition; (3) whole brain intensity normalization to achieve a mode value of 1000; (4) spatial realignment within and across R-fMRI runs; and (5) resampling to 3mm cubic voxels in atlas space including realignment and atlas transformation in one resampling step.) 
% 1) Atlas registration
% 2) Niusance regression (motion regressors, CSF regressors) - White matter
% and whole brain regressors should not be applied.
% 3) Bandpass filtering. 
% 4) You should generate a mask identifying high motion frames (as in Power 
% et al 2012). 
% 3&4 will lower the 0-cross-correlation peak caused by shared noise making
% it easier to identify hemodynamic lags.
%
%
% © 2015 Washington University in St. Louis.
% Author(s): Joshua Siegel, siegelj@wustl.edu, 240-506-3715
% All Rights Reserved
% No part of this work or any of its contents may be reproduced, copied, modified or adapted, without the prior written consent of the author(s).
% Commercial use and distribution of the works is not allowed without express and prior written consent of Maurizio Corbetta, Joshua Siegel, or Washington University in St. Louis.
%   $ Revision: 1.0 $  $ 14-Nov-2014 $
%   $ Revision: 2.0 $  $ 2-Dec-2015 $

LL = [];

%% Make Sure Switches are set

%[LL]=MapLag(
    if( ~exist('tmask') ...
    || ~exist('TR'))
        error('Not enough parameters!')
        return
    end
    
    if(~exist('corrthreshold'))
        corrthreshold = 0 % This is the minimum correlation that will be allowed between voxel & reference. Anything below this is set to 0 or nan.
    end
    
    if(~exist('nans'))
        nans = 1 % 1:keep nan values where lag cant be computed, 0: set values to 0 where lag cant be computed.
    end
    
    if(~exist('framematch'))
        framematch = false % set the lag cross-correlation to always compare equal numbers of frames. Not necessary.
    end
    
    if(~exist('nifti'))
        if(SearchString(input_file,'.conc'))
            nifti = false
        else
            nifti = true
        end
    end
    if(~exist('savepng'))
        savepng = false
    end
    
    if(~exist('atlas'))
        atlas='talairach'
    end
    
    if(~exist('time_range'))
        time_range = floor(12/TR) % This is the range of TRs used in the cross-correlation (e.g. if you have a TR=2.5s and range=4 you can identify lags up to 5s forward and backward
    end
   
    if(~exist('minframes'))
        minframes = 0 %Exclude subjects with frames<minframes
    end
    
    if(~exist('homotopic'))
        homotopic = false %Homotopic reference or global signal reference? For Stroke, I suggest homotopic. Better SNR
    end


%% Other Files that you will need
img_right='/supportscripts/right.4dfp.img'; % mask of right (1) vs left (0)
switch atlas
    case 'talairach'
        img_graymatter='/supportscripts/N21_aparc+aseg_GMctx_on_711-2V_333_avg.4dfp.img'; % group average gray matter mask
        img_brainmask='/supportscripts/talairach_brain_mask_333_b100.4dfp.img'; % this is a atlas brain mask, with 1's inside the brain,
    case 'MNI'
        img_graymatter='/supportscripts/N21_aparc+aseg_GMctx_on_MNI152_333_avg.4dfp.img'; % group average gray matter mask
        img_brainmask='/supportscripts/MNI152_brain_mask_333_b100.4dfp.img'; % this is a atlas brain mask, with 1's inside the brain,
end

[lagpath B]=fileparts(which('MapLag'));
addpath(genpath(lagpath))


%% Load the tmask (included frames=0, excluded frames=1)
if strmatch(tmask((end-5):end),'format') % if you used a format file
    [~,formkey] = system(['format2lst `cat ' tmask '` -e']);
    Scrub=zeros(size(formkey));
    Scrub(formkey=='+')=1;
else
    Scrub=importdata(tmask); % load a temporal mask
end

fprintf('Number of usable frames = %d/%d\n',sum(Scrub),length(Scrub))

if(sum(Scrub) == 0)
    disp('No data to operate on.');
    return;
end


%% load brain mask, generic gray mask, and right side mask. 
brainmask=[lagpath img_brainmask]; %atlas-based whole brain
bm=read_4dfp_img(brainmask);bm=logical(bm.voxel_data>0.5);
right=read_4dfp_img([lagpath img_right]); % mask of right (1) vs left (0)
R=logical(right.voxel_data(logical(bm)));
gmmask=read_4dfp_img([lagpath img_graymatter]);
gmmask=gmmask.voxel_data(logical(bm));
bm_nolesion=bm;

% Load freesurfer aparc+aseg mask to use indiv. gray matter
% if isfield(switches,'individual_gm');
%     k=read_4dfp_img(individual_gm);
%     gmmask=k.voxel_data>1000;
%     gmmask=gmmask(logical(bm));
% end
% 
% if isfield(switches,'lesion');
%     if isnumeric(lesion)
%         if size(lesion,1)==1; lesion=lesion';end
%         lll = lesion;           
%     else
%         if nifti
%         	lll=load_nifti(lesion);
%             X=lll.vol;
%             X=flipdim(X,1);X=flipdim(X,2);% FLIP NII X&Y
%             lll=X(:);           
%         else
%             lll=read_4dfp_img(lesion);
%             lll=lll.voxel_data;
%         end
%     end
%     lesion=round(lll(logical(bm)));
%     gmmask=gmmask-(gmmask.*lesion);
%     bm_nolesion(logical(lesion))=0;
%     % Reg(:,end+1)=mean(FullData(logical(lesion),:)); % lesion regressor
% else
    lll = zeros(147456,1);
% end

%% Display some basic QC metrics
a = figure('Position',[0,0,1440,720]);
subplot(4,1,1);
imagesc(Scrub);

%% Load raw timecourses
FullData=[];
flipFullData=[];
X=importdata(input_file);
runs=1;
for j=1:runs    
    if 1
        Nifti_TC = load_nifti(input_file);
        tc=flipdim(Nifti_TC.vol,1);
        tc=flipdim(tc,2);% FLIP NII X&Y
        [datamat] = reshape(tc,size(tc,1)*size(tc,2)*size(tc,3),size(tc,4));    
    else        
        tc = read_4dfp_img(X{j+1}(7:end),'3D');
        tc=tc.voxel_data;
        [datamat] = reshape(tc,size(tc,1)*size(tc,2)*size(tc,3),size(tc,4));
    end
    FullData=[FullData datamat];
    %% Flip timecourse
    if homotopic
        tc = flipdim(tc,1); % Flip data around the X-axis
        flipdatamat = reshape(tc,size(tc,1)*size(tc,2)*size(tc,3),size(tc,4));
        flipFullData=[flipFullData flipdatamat];
        fTC=flipFullData(bm,:);
    end
    
    clear datamat tc
end
if isempty(FullData); disp('Subject not found.');end
TC=FullData(bm,:);
 
%do regression and bandpass filtering on the input if the variables aren't
%empty

% if(~isempty(regressors))
% 
%     %% NUISANCE REGRESSION
%     regs = importdata(regressors,' ');
%     regs = detrend(regs);%Detrend all regressors
% 
%     % MASK 
%     regs_masked = regs(Scrub==1,:); % mask excluded
%     regs = zscore(regs); % zscore regresors
%     regs = [regs ones(size(regs,1),1)]; % add column of 1's
% 
%     % APPLY REGRESSORS
%     for r = 1:length(TC(1,:))
%         [B,~,R] = regress(TC(r,Scrub==1)',regs_masked);
%         TC(r,Scrub==1) = R;
%         betas(r,:)=B;
%     end
% 
% end
% 
% if(~isempty(bandpass_low) || ~isempty(bandpass_high))
%     % Set up butterworth filter
%     filterorder=1;
%     lopass=bandpass_low/(0.5/TR);
%     hipass=bandpass_high/(0.5/TR);
%     %[butta buttb]=butter(filterorder,[hipass lopass]);
%     try%see if it is a low pass
%         [butta buttb]=butter(filterorder,[lopass hipass]);
%     catch
%         [butta buttb]=butter(filterorder,[hipass lopass]);
%     end
% 
%     %% INTERPOLATE & BANDPASS
%     % INTERPOLATE MISSING FRAMES
% 
%     vox = length(TC(:,1))
%     tp = length(TC(1,:))
%     
%     cuts=find(Scrub==0);
%     k=1;
%     C{k}=cuts(k);
%     for j=2:length(cuts)
%         td = cuts(j)-cuts(j-1);
%         if td==1
%             C{k} = [C{k} cuts(j)];
%         else
%             k = k + 1;
%             C{k} = cuts(j);
%         end
%     end
%     for m=1:length(C)
%         k=C{m}(end)-C{m}(1)+1;
%         fill=nan(vox,k);
%         if m==1
%             before = zeros(vox,1);
%         else
%             before = TC(:,C{m}(1)-1);
%         end
%         if C{m}(end)==tp
%             after = zeros(vox,1);
%         else
%             after = TC(:,C{m}(end)+1);
%         end
%         for j=1:k
%             fill(:,j)=before+(after-before)*(j/(k+1));%% CHECK ME!!!
%         end
%         TC(:,C{m}(1):C{m}(end))=fill;
%     end
% 
%     % NOW BANDPASS
%     prefilt = TC';
% 
%     pad = ceil(1/bandpass_high);
%     prefilt = [zeros(pad,vox) ; prefilt ; zeros(pad,vox)];
% 
%     TC = filtfilt(butta,buttb,prefilt);   %regressed data
% 
% end

Fr=time_range;
M=(Fr-1)*2;
p=-Fr:Fr;
num=length(p);
VLtau=zeros(sum(bm),1);
VLcorr=zeros(sum(bm),1);
gr=length(Scrub);
%% NOW CREATE ALTERNATIVE PATH FOR HOMOTOPIC LAG
if homotopic
    
    
    for i=1:size(fTC,1)
%        [~,~,pp]=regress(fTC(i,:)',Reg);
%        fTC(i,:)=pp;
        HFC(i)=corr(TC(i,:)',fTC(i,:)');
    end
    
    subplot(4,1,2);
    hist(HFC,[-1:0.1:1])
    title(sprintf('Corr (R) with Homotopic Reference (0s shift)'));
    colormap('jet');
    freezeColors;
    ylabel('Number of Voxels');
    xlabel('Homotopic Correlation (R)');
    set(gca,'XLim',[-1 1]);
    set(gca,'XTick',[-1:0.1:1]);
    
    % Counterbalance frames if u want
    scrub=ones(length(Scrub)+2*Fr,1);
    bf=find(Scrub==0);
    for s=0:(num-1)
        scrub(bf+s)=0;
    end
    scrub=scrub((1+Fr):(end-Fr));
    
    P=Scrub+scrub';
    subplot(4,1,1);
    imagesc(P);
    colormap('bone');
    freezeColors;
    set(gca,'YTick',[]);
    set(gca,'XTick',[0:100:length(Scrub)]);
    xlabel('Frame');
    title(sprintf('Temporal Masking'))
    goodvoxels=ones(size(TC,1),1);
    for v=1:size(TC,1)
        VOX=TC(v,:);
        fVOX=fTC(v,:);
        
        for f=1:num
            q=p(f);
            absq=abs(q);
            
            if ~framematch
                shift_Scrub((1+absq):gr)=Scrub(1:(gr-absq));
                scrub=logical(shift_Scrub.*Scrub);
            end
            
            if q>0
                shift_TC=VOX((1+absq):gr)';
                shift_ref=fVOX(1:(gr-absq))';
                shift_scrub=logical(scrub(1:(gr-absq)));
            elseif q<0
                shift_ref=fVOX((1+absq):end)';
                shift_TC=VOX(1:(gr-absq))';
                shift_scrub=logical(scrub((1+absq):end));
            else
                shift_TC=VOX';
                shift_ref=fVOX';
                shift_scrub=logical(scrub);
            end
            lagcorrall(v,f)=corr(shift_ref(shift_scrub),shift_TC(shift_scrub,:));
            frames_shift(f)=sum(~isnan(shift_ref(shift_scrub).*shift_TC(shift_scrub,1)));
        end
        
        [peak_lag,peak_cov]= parabolic_interp_pos(lagcorrall(v,:),p,TR);
        VLcorr(v)=peak_cov;
        
        if max(lagcorrall(v,:))>corrthreshold
            VLtau(v)=peak_lag; % lag value vertex to homologue vertex            
        else
            goodvoxels(v)=0;
        end
    end
       
    
else % Global Signal Lag
    %% find gray matter signal
    GS=nanmean(FullData(logical(gmmask),:))';
    subplot(4,1,2);
    GScorr=corr(GS(logical(Scrub)),TC(:,logical(Scrub))');
    GScorr=GScorr';
    hist(GScorr,[-1:0.1:1]);
    title(sprintf('Corr with Gray Matter Reference'));
    colormap('jet');
    freezeColors;

    %% Lag - find shift correlation of each voxel with global signal

    if framematch % Counterbalance frames
        scrub=ones(length(Scrub)+2*Fr,1);
        bf=find(Scrub==0);
        for s=0:(num-1)
            scrub(bf+s)=0;
        end
        scrub=scrub((1+Fr):(end-Fr));
        scrub((end+1-Fr):end)=0;
        P=Scrub+scrub;
        subplot(4,1,1);imagesc(P');
    end
    for f=1:num
        q=p(f);
        absq=abs(q);
        if ~framematch
            shift_Scrub((1+absq):gr)=Scrub(1:(gr-absq));
            scrub=logical(shift_Scrub.*Scrub);
        end
        if q>0
            shift_TC=TC(:,(1+absq):gr)';
            shift_ref=GS(1:(gr-absq));
            shift_scrub=logical(scrub(1:(gr-absq)));
        elseif q<0
            shift_ref=GS((1+absq):end);
            shift_TC=TC(:,1:(gr-absq))';
            shift_scrub=logical(scrub((1+absq):end));
        else
            shift_TC=TC';
            shift_ref=GS;
            shift_scrub=logical(scrub);
        end
        lagcorrall(:,f)=corr(shift_ref(shift_scrub),shift_TC(shift_scrub,:));
        frames_shift(f)=sum(~isnan(shift_ref(shift_scrub).*shift_TC(shift_scrub,1)));
    end

    fprintf('Lagged frames = %s\n',num2str(frames_shift))
    if frames_shift(1)<minframes
        error('Not enough frames. Abort!')
    end
    fprintf('Calculating and saving lag map.\n')
    goodvoxels=ones(size(TC,1),1);
    for v=1:size(TC,1)
        % Run Anish's parabolic interpolation script to
        % find the peak in lag correlation.
        [peak_lag,peak_cov]= parabolic_interp_pos(lagcorrall(v,:),p,TR);
        VLcorr(v)=peak_cov;
        if max(lagcorrall(v,:))>corrthreshold
            VLtau(v)=peak_lag;
        else
            goodvoxels(v)=0;
        end
    end

end %% Combine paths for homotopic/GS lag


subplot(4,1,3);
colormap('jet');
hist(VLcorr,[-1:0.1:1]);
ylabel('Number of Voxels');
xlabel('Homotopic Correlation (R)');
set(gca,'XLim',[-1 1]);
set(gca,'XTick',[-1:0.1:1]);
title(sprintf('Maximum Corr with Reference after shifting'));

subplot(4,1,4);
hist(VLtau,40);
ylabel('Number of Voxels');
xlabel('Shift in Seconds of Maximum Correlation');
set(gca,'XLim',[-8 8]);
set(gca,'XTick',[-8:1:8]);
title(sprintf('Lag Distribution'));
saveas(gcf,'lagattributes.jpg')


% save lag image and other stuff if you want
lagmap=VLtau;

%% Now calculate Laterality
VLtau(~gmmask)=nan;
VLtau(~goodvoxels)=nan;
LL=nanmean(VLtau(R))-nanmean(VLtau(~R));
fprintf('Lag Laterality = %f\n',LL);
GScorrL=nanmean(VLcorr(~R))-nanmean(VLcorr(R));
fprintf('Ref Corr Laterality = %f\n',GScorrL);

if homotopic    
    base = ['homo_lagmap_r' num2str(time_range)];
    corroutimage=[ 'homo_peakcovmap.4dfp.img'];
else
    base = ['GS_lagmap_r' num2str(time_range)];
    corroutimage=[ 'covmap.4dfp.img'];
end

% write_back(VLcorr,corroutimage,bm,0.5,'nans')
%     
% if nans
%     lagmap(~goodvoxels)=NaN;
%     base=[base '_t' num2str(corrthreshold)];
%     outimage=[ base '.4dfp.img'];
%     write_back(lagmap,outimage,bm,0.5,'nans')    
% else
%     lagmap(isnan(lagmap))=0;
%     outimage=[ base '.4dfp.img'];
%     write_back(lagmap,outimage,bm,0.5)    
% end
%     

%    system(sprintf('nifti_4dfp -n %s.4dfp.img %s.nii &',base,base));

lagimg=nan(length(bm),1);
maskmat=find(bm>=0.5);
for i=1:length(maskmat)
    lagimg(maskmat(i),:)=lagmap(i,:);
end
lagimg = reshape(lagimg,48,64,48);

%% Smooth the image
lagimg = smooth3(lagimg,'gaussian');
bm=reshape(bm,48,64,48);

lagimg(bm<0.5)=nan;
try
    templatenii=load_nifti('sampledata/FCS_024_A/FCS_024_A_lesion_333.nii');
    templatenii.vol = lagimg;
%     templatenii.vol =flipdim(lagimg,1);
%     templatenii.vol=flipdim(templatenii.vol,3);% FLIP NII X&Y
    save_nifti(templatenii,[ base '.nii'])
end

close(a);    %close the homotopic distribution figure

%% Make a lag figure just for fun
if savepng
    figure1 = figure('Position',[0,0,1440,720]);
    %set(figure1,'Position',[1 100 1000 500])
    p = panel();
    p.pack(2,6);
    
    if exist('lll','var')
        lll=reshape(lll,48,64,48);
        x = bm - lll;
    else
        x = bm;
    end
    
    posmask = x>0.5;
    posmask(isnan(lagimg))=0;  
    s=1;
    title('Volume Homotopic Lag Map','interpreter','none');
    axis off
    for i = 1:2
        for j = 1:6
            p(i,j).select();
            c = flipdim(squeeze(lagimg(:,:,s*3+9))',1);c = flipdim(c,2);
            m = flipdim(squeeze(posmask(:,:,s*3+9))',1);m = flipdim(m,2);
            imagesc(c,'AlphaData',m);
            caxis([-time_range*TR time_range*TR])
            colormap('jet');
            axis off
            axis([0 48 0 64])
            s=s+1;
        end
    end
    p.de.margin = 5;
    colormap('jet');
    colorbar('YTick', [-time_range*TR:1:time_range*TR]); 
    caxis([-time_range*TR time_range*TR])
    set(figure1,'PaperPositionMode','auto')
    saveas(figure1,'volume_homotopic_lagmap.png');
    close(figure1);
end

%% Make a lag figure just for fun
if 0
    figure2 = figure('Position',[0,0,1440,720]);
    %set(figure2,'Position',[1 100 1000 500])
    p = panel();
    p.pack(2,6);
    x = bm;
    posmask = x>0.5;
    s=1;
    title(base,'interpreter','none');axis off
    anatave=reshape(nanmean(FullData(:,logical(Scrub)),2),48,64,48);
    for i = 1:2
        for j = 1:6
            p(i,j).select();
            c = flipdim(squeeze(anatave(:,:,s*3+9))',1);c = flipdim(c,2);
            imagesc(c);
            colormap('gray');
            axis off
            axis([0 48 0 64])
            s=s+1;
        end
    end
    p.de.margin = 5;
    saveas(figure2,'lag_figure.png');
    close(figure2);
end

end
