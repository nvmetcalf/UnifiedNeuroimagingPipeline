function [P_lesion,P_NOTlesion] = MapSpectrum(concfile,tmask,outdir,switches)
% MAPSPECTRUM Generate a voxel-wise map of spectrum
%   [LL]=MapSpectrum(concfile,tmask,outdir) Given a concfile, temporal mask
%   (tmask) and a outdir, MapSpectrum will generate spectrums for all
%   voxels inside the brain
%   
%   Example: MapSpectrum('/data/nil-bluearc/corbetta/Studies/FCStroke/Subjects/FCS_024_A/FCmaps/FCS_024_A_faln_dbnd_xr3d_atl_g7_bpss_resid.conc','/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_024_A/movement/tmask.txt','/scratch/lagtest/FCS_024_A/')
%   Example2: MapSpectrum('/data/nil-bluearc/shimony/Jerrel/CONDR/W009/FCmaps/W009_faln_dbnd_xr3d_atl_g7_bpss_resid.conc','/data/nil-bluearc/shimony/Jerrel/CONDR/W009/FCmaps/W009_faln_dbnd_xr3d_atl_g7_bpss_resid.format','/data/nil-bluearc/shimony/Jerrel/CONDR/LagTest/W009/')
% 
%   Joshua Siegel, siegelj@wusm.wustl.edu, 240-506-3715
%   Copyright 2015, Washington University in St. Louis
%   $ Revision: 1.0 $  $ 24-June-2015 $

% User Inputs:
%   concfile: BOLD 4dfp .conc file
%   tmask: temporal mask of ones and zeros
%   lesion: lesion mask (optional)
%   outdir: where to write results


if strmatch(tmask((end-5):end),'format') % if you used a format file
    [y, formkey] = system(['format2lst `cat ' tmask '` -e']);
    clear y
    Scrub=zeros(size(formkey));
    Scrub(formkey=='+')=1;
else
    Scrub=importdata(tmask); % load a temporal mask
end
format = Scrub;
fprintf('Number of usable frames = %d/%d\n',sum(Scrub),length(Scrub))

[concpath,conc] = fileparts(concfile); % Identify conc path and name

if ~exist(outdir,'dir'); mkdir(outdir);end % Make outdir if it doesnt exist.

% Other potentially variable inputs:
if ~exist('switches','var');switches=[];end
if ~isfield(switches,'range'); switches.range=4; end % Max lag (in TRs).
if ~isfield(switches,'corrthreshold'); switches.corrthreshold=0.0; end
if ~isfield(switches,'nans'); switches.nans = 1; end % Do you want to save nan values where lag cant be computed?
if ~isfield(switches,'framematch'); switches.framematch = 0;end
if ~isfield(switches,'TR');switches.TR=2.00;end
if ~isfield(switches,'minrunframes');switches.minrunframes=60;end
if ~isfield(switches,'LS');switches.LS=0;end
if ~isfield(switches,'figs');switches.figs=0;end
if ~isfield(switches,'skipfirst');switches.skipfirst=4;end
switches

% load brain mask, generic gray mask, and right side mask. 
[lagpath B]=fileparts(which('MapSpectrum'));
ventricles='/data/nil-bluearc/corbetta/ATLAS/TRIO_STROKE_NDC/711-2B_lat_vent_333.4dfp.img'; %lateral ventricle mask
brainmask='/data/petsun43/data1/atlas/glm_atlas_mask_333_b100.4dfp.img'; %atlas-based whole brain
bm=read_4dfp_img(brainmask);bm=logical(bm.voxel_data>0.5);
right=read_4dfp_img([lagpath '/supportscripts/right.4dfp.img']); % mask of right (1) vs left (0)
R=logical(right.voxel_data(logical(bm)));
gmmask=read_4dfp_img([lagpath '/supportscripts/N21_aparc+aseg_GMctx_on_711-2V_333_avg.4dfp.img']); % mask of right (1) vs left (0)
gmmask = logical(gmmask.voxel_data);
bm_nolesion=bm;

% Load freesurfer aparc+aseg mask to use indiv. gray matter
if isfield(switches,'individual_gm');
    k=read_4dfp_img(switches.individual_gm);
    gmmask=k.voxel_data>1000;
end

% try
%% Load raw timecourses
% FullData=[];
% X=importdata(concfile);
% runs=str2num(X{1}(end));
% for j=1:runs
%     [datamat] = read_4dfp_img(X{j+1}(7:end));
%     FullData=[FullData datamat.voxel_data];
%     scans(j) = size(datamat.voxel_data,2);
%     clear datamat
% end
% if isempty(FullData); disp('Subject not found.');end
% vox=size(FullData,1);
% TC=FullData(bm,:);
% Reg=ones(size(FullData,2),1);


% Load the lesion and create 2 regions: lesion, NOTlesion (inside brain but
% not lesion)
if isfield(switches,'lesion');
    if isnumeric(switches.lesion)
        lesion=logical(switches.lesion);
    else
        lesion=read_4dfp_img(switches.lesion);    
        lesion=logical(round(lesion.voxel_data));
    end
    if size(lesion,2)>size(lesion,1);lesion=lesion';end
    NOTlesion = bm & ~lesion;
    fprintf('Tumor voxels = %d\n',sum(lesion))
    fprintf('Non-Tumor brain voxels = %d\n',sum(NOTlesion))
    gmmask_NOlesion = gmmask & ~lesion;
end


%% Interpolate over removed frames
firstframe=1;
TC4 = [];
front=zeros(length(bm),switches.skipfirst);
FullData=[];
X=importdata(concfile);
runs=str2num(X{1}(end));
P_runs=nan(runs,length(gmmask),81);
for i=1:runs
    [datamat] = read_4dfp_img(X{i+1}(7:end));
    FullData=[FullData datamat.voxel_data];
    scans(i) = size(datamat.voxel_data,2);
    vox=size(datamat.voxel_data,1);
    rframes=scans(i)-switches.skipfirst;
    firstframe=firstframe+switches.skipfirst;
    lastframe=firstframe+rframes-1;
    tmask=(format(firstframe:lastframe))';
    
    if sum(tmask)  > switches.minrunframes
        
        %% Plot mask
        figure
        subplot(3,1,1);imagesc(tmask');
        title(sprintf('\n%s run %d/%d: Mask',conc,i,runs),'interpreter','none')
        
        cuts=find(tmask==0);
        TH=(switches.TR:switches.TR:length(tmask)*switches.TR)';
        TC=datamat.voxel_data(:,(switches.skipfirst+1):end)';
        
        fprintf('\n Interpolating %d of %d frames, run %d of %d\n',length(cuts),length(tmask),i,runs)
        GM_LS=TC;
        if length(cuts)>0
            
            if switches.LS % run Anish's Lomb-Scargle Interpolation Script (if needed)
                [H,f,s,c,tau,w] = getTransform_v2(tmask,TC,TH,4,1);
                
                GM_LS(cuts,:)=H(cuts,:);
                GM_LS(isnan(GM_LS))=1e-37;
            else % Run linear spline interpolation
                %seq=diff(cuts)==1;
                
%                 k=1;
%                 C{k}=cuts(k);
%                 for j=2:length(cuts)
%                     t = cuts(j)-cuts(j-1);
%                     if t==1
%                         C{k} = [C{k} cuts(j)];
%                     else
%                         i = i + 1;
%                         C{k} = cuts(j);
%                     end
%                 end
%                 for m=1:length(C)
%                     k=C{m}(end)-C{m}(1)+1;
%                     fill=nan(k,vox);
%                     before = TC(C{m}(1)-1,:);
%                     after = TC(C{m}(end)+1,:);
%                     for j=1:k
%                         %fill(j,:)=(j*after+k*before)/(j+k);
%                         fill(:,j)=(after-before)*(j/(k+1));
%                     end
%                     GM_LS(C{m}(1):C{m}(end),:)=fill;
%                 end
                TC=TC';
                cuts=find(tmask==0);
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
                        before = TC(:,C{m}(1)-1);
                    end
                    if C{m}(end)==length(TH)
                        after = zeros(vox,1);
                    else
                        after = TC(:,C{m}(end)+1);
                    end
                    for j=1:k
                        fill(:,j)=before+(after-before)*(j/(k+1));
                    end
                    TC(:,C{m}(1):C{m}(end))=fill;
                end
                TC=TC';               
            end
            
        end
        
        % Plot lesion and non-lesion timecourses
        minv = min(min(GM_LS));
        maxv = max(max(GM_LS));
        subplot(3,1,2)
        imagesc(GM_LS(:,NOTlesion)');
        caxis([minv maxv]);colormap(gray)
        title('Non-lesion timecourse')
        subplot(3,1,3)
        imagesc(GM_LS(:,lesion)');
        caxis([minv maxv]);colormap(gray)
        title('Lesion timecourse')
        
        
        %% NOW DO SPECTRAL ANALYSIS FOR RUN i

        % do analysis seperately for every voxel
        progressbar(['SPECTRAL ANALYSIS, RUN ' num2str(i) '/' num2str(runs)])
        for v = 1:size(GM_LS,2)
            progressbar(v/size(GM_LS,2))
            %[S,F,T,P]=spectrogram(run(:,i),124,62,124*TR,0.5);
            [P,F]=pwelch(GM_LS(:,v),50,[],160,1/switches.TR); % VICTOR - LOOK THIS UP AND MAKE SURE YOU ARE USING THIS FUNCTION CORRECTLY
            P_runs(i,v,:)=P; % P_runs is the spectral power for every voxel for every R-fMRI run. (run,voxel,power)
        end
    end
    
    
    firstframe=firstframe+rframes;
    clear datamat GM_LS TC
end
%% Now average across runs
P_session = squeeze(nanmean(P_runs,1));

%% Now average spectrums over whatever regions or masks you like (tumor, gray matter, whole brain, etc)
P_lesion=nanmean(P_session(lesion,:),1);
P_NOTlesion=nanmean(P_session(NOTlesion,:),1);
P_GrayMatter_NOTlesion=nanmean(P_session(gmmask_NOlesion,:),1);    
   
OutMap = [outdir '/' conc '_SpectrumMap.mat'];
OutImage = [outdir '/' conc '_Spectrums.png'];
%% Now plot average power spectrum inside and outside tumor
if switches.figs
    figure;
    plot(F,P_NOTlesion,'k','LineWidth',1);hold on
    plot(F,P_GrayMatter_NOTlesion,'b','LineWidth',1);hold on
    plot(F,P_lesion,'r','LineWidth',1);hold on
    xlim([0.009 0.08]);
    title(conc)
    legend('Whole Brain (No Tumor)','Gray Matter (No Tumor)','Tumor')
    xlabel('Frequency');ylabel('Power')
    saveas(gcf,OutImage,'png');
end

%% Save Results

save(OutMap,'P_session','F');

end
