% function MapLag(sublist,mask,dvar_threshold,varargin)
% EXAMPLE: FCCorrelations('Control_List.txt','0.3symmetric',4.6, 0.5)
clear
subject='FCS_124_A';
patids{1}=subject;
% sublist='/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Analysis/lag/testlist.txt';
% sublist='/data/nil-bluearc/corbetta/Studies/FCStroke/Analysis/siegelj/lag/FCS_A_List.txt';
% fid=fopen(sublist);patids=textscan(fid,'%s\n');patids=patids{1};
TR=2;
% Pick inclusion thresholds
meanabs_cut=[.12 .226];
frames_cut=120;
FDave_cut=1.2;
DVARcut=4.6;
DDATcut=0.5;
corrthreshold=-0.1;


datdir='/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/';
giipath = '/data/nil-bluearc/corbetta/Hacker/Process/Surface_Processing/CIFTI_62713';
wb_command_path='/data/nil-bluearc/corbetta/Hacker/Process/HCP/PIPE//global/binaries/caret7/bin_rh_linux64/wb_command'
addpath(genpath(giipath))
%p=ciftiopen('/data/nilsdfsdf-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_009_AMC/FCS_009_AMC_faln_dbnd_xr3d_uwrp_atl_uout_resid_filt.dconn.nii',wb_command_path);

LROI='/data/nil-bluearc/corbetta/Studies/SurfaceStroke/ROIs/L.169ROIs.6mm.10k_fs_LR.func.gii';
ROI_L=gifti(LROI);ROI_L=ROI_L.cdata;
RROI='/data/nil-bluearc/corbetta/Studies/SurfaceStroke/ROIs/R.169ROIs.6mm.10k_fs_LR.func.gii';
ROI_R=gifti(RROI);ROI_R=ROI_R.cdata;
Latlasroi='/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_036_AMC/atlas/fsaverage_LR10k/FCS_036_AMC.L.atlasroi.10k_fs_LR.shape.gii';
maskL=gifti(Latlasroi);maskL=maskL.cdata;
Ratlasroi='/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_036_AMC/atlas/fsaverage_LR10k/FCS_036_AMC.R.atlasroi.10k_fs_LR.shape.gii';
maskR=gifti(Ratlasroi);maskR=maskR.cdata;
% Index the hemisphere ROIs into the common atlas
ROIcii=[ROI_L(find(maskL));ROI_R(find(maskR))];
NumROIs=size(unique(ROIcii))-1
ROIs=169;

% Get subject ages
% Ages=demographic(patids,'demographic','Age');

corrmats=nan(length(patids),ROIs,ROIs);
good=zeros(size(patids));

for pid=1:length(patids);
    patid=patids{pid};
    patnum=str2num(patid(5:7));
    
    %    try
    %     Age=Ages(pid);
    fprintf('\n%s\n',patid)
    corrdir=['/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/' patid '/'];
    Output=sprintf('/scratch/SurfaceStroke/Subjects/%s/%s_faln_dbnd_xr3d_uwrp_atl_uout_resid_filt_corrmat.mat',patid,patid);
    %% scrubbing - load format file
    command=['format2lst `cat ' datdir patid '/atlas/' patid '_func_vols.format` -e'];
    [~,formkey] = system(command);
    format=zeros(size(formkey));
    format(formkey=='+')=1;
    frames=sum(format);
    frames_raw=size(format);
    fprintf('Number of usable frames = %d/%d\n',sum(format),length(format))
    %% FD
    %     if exist(strcat( '/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/',patid,'/movement/',patid,'.dvals'));
    %         FD=importdata(strcat( '/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/',patid,'/movement/',patid,'.dvals'));
    %     elseif exist(strcat( '/data/nil-bluearc/corbetta/Studies/FCStroke/Subjects/',patid,'/movement/',patid,'.dvals'))
    %         FD =importdata(strcat( '/data/nil-bluearc/corbetta/Studies/FCStroke/Subjects/',patid,'/movement/',patid,'.dvals'));
    %     elseif exist(strcat( '/data/nil-bluearc/corbetta/Studies/DysFC/Subjects/',patid,'/movement/',patid,'.dvals'))
    %         FD=importdata(strcat( '/data/nil-bluearc/corbetta/Studies/DysFC/Subjects/',patid,'/movement/',patid,'.dvals'));
    %     end
    %     if ~isequal(length(format),length(FD))
    %         FD=zeros(size(format));
    %         fprintf('Warning: FD to format mismatch. \n')
    %     end
    %     format(FD>1.2)=0;
    %     frames=sum(format);
    %     %format=1-format;
    %     fprintf('Number of usable frames = %d/%d\n',sum(format),length(format))
    %     FDave=sqrt(mean(FD(logical(format)).^2));
    %     fprintf('FDave = %f\n',FDave)
    %     first4=ones(frames_raw);
    %     runs=floor(frames_raw(2)/128);
    %     for j=1:runs
    %         f=(j-1)*128+1;
    %         first4(f:(f+3))=0;
    %     end
    %     Scrub=format';
    try
        DVAR=importdata(sprintf('/data/nil-bluearc/corbetta/Studies/FCStroke/Subjects/%s/FCmaps/DVAR_4.6/%s_faln_dbnd_xr3d_atl_g7_bpss_resid.vals',patid,patid));
        FD=importdata(sprintf('/data/nil-bluearc/corbetta/Studies/FCStroke/Subjects/%s/movement/%s.dvals',patid,patid));
    catch
        DVAR=importdata(sprintf('/data/nil-bluearc/corbetta/Studies/FCStroke/Analysis/ramseyl/FCS_controls/%s/FCmaps/DVAR_4.6/%s_faln_dbnd_xr3d_atl_g7_bpss_resid.vals',patid,patid));
        %DVAR=importdata(sprintf('/data/nil-bluearc/corbetta/Studies/FCStroke/Controls/%s/FCmaps_no_wb/DVAR_4.6/%s_faln_dbnd_xr3d_atl_g7_bpss_resid.vals',patid,patid));
        FD=importdata(sprintf('/data/nil-bluearc/corbetta/Studies/FCStroke/Controls/%s/movement/%s.dvals',patid,patid));
    end
    %figure;
    group='Controls';
    Scrub=(logical(FD<DDATcut) .* logical(DVAR<DVARcut));
    
    
    % Load Cifti
    ciifname=sprintf('%s/%s/FCmaps_uwrp/%s_faln_dbnd_xr3d_uwrp_atl_uout_resid_bpss.ctx.dtseries.nii',datdir,patid,patid);
    %     try
    
    %fprintf('\nCreating Correlation matrix.\n')
    cii=ciftiopen(ciifname,wb_command_path);
    GM_TC=cii.cdata';
    
    %         % Mask Lesion
    %         patidnum=[patid(1:7)];
    %         if strcmp(patid(9:end),'AMC') || strcmp(patid(9:end),'AMC2')
    %             group='Controls';
    %         else
    %             Llesion=['/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/' patidnum '_A/Segmented_Lesions/' patidnum '_A_lesion.L.10k_fs_LR.func.gii'];
    %             Rlesion=['/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/' patidnum '_A/Segmented_Lesions/' patidnum '_A_lesion.R.10k_fs_LR.func.gii'];
    %             lesionmask=HemtoBrain(Llesion,Rlesion);
    %             GM_TC(:,logical(lesionmask>0.5))=nan;
    %         end
    
    % Seperate hemispheres
    stat=single(GM_TC');
    Latlasroi=sprintf('/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_001_AMC/atlas/fsaverage_LR10k/FCS_001_AMC.L.atlasroi.10k_fs_LR.shape.gii');
    maskL=gifti(Latlasroi);
    Ratlasroi=sprintf('/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_001_AMC/atlas/fsaverage_LR10k/FCS_001_AMC.R.atlasroi.10k_fs_LR.shape.gii');
    maskR=gifti(Ratlasroi);
    nmaskL=nnz(maskL.cdata);
    nmaskR=nnz(maskR.cdata);
    VL=zeros(size(maskL.cdata,1),size(stat,2));
    VR=zeros(size(maskR.cdata,1),size(stat,2));
    VL(find(maskL.cdata),:)=stat(1:nmaskL,:);
    VR(find(maskR.cdata),:)=stat((nmaskL+1):(nmaskL+nmaskR),:);
    % calculate lag back and forward 6 frames
    VLtau=nan(size(VL,1),1);
    
    %% Variables needed for Lag computation
    % Limits of lag (s):
    M=8;
    
    %Binary vector of usable frames from the temporal format
    %Scrub = [];
    
    
    %% Lag - find shift correlation of each voxel with homo
    
    Fr=M/2+1;
    
    p=-Fr:Fr;
    num=length(p);
    
    
    % Do it once for all frames
    gr=length(Scrub);
    % Counterbalance frames
    scrub=ones(length(Scrub)+2*Fr,1);
    bf=find(Scrub==0);
    for s=0:(num-1)
        scrub(bf+s)=0;
    end
    scrub=scrub((1+Fr):(end-Fr));
    
    P=Scrub+scrub;
    subplot(4,1,1);imagesc(P');
    for v=1:size(VL,1)
        TC=VR(v,:);
        GS=VL(v,:);
        
        for f=1:num
            q=p(f);
            absq=abs(q);
            %                         shift_Scrub((1+absq):gr)=Scrub(1:(gr-absq));
            %                         scrub=logical(shift_Scrub'.*Scrub);
            %                         scrub=scrub(1:(gr-absq));
            
            if q>0
                shift_TC=TC((1+absq):gr)';
                shift_ref=GS(1:(gr-absq))';
                shift_scrub=logical(scrub(1:(gr-absq)));
            elseif q<0
                shift_ref=GS((1+absq):end)';
                shift_TC=TC(1:(gr-absq))';
                shift_scrub=logical(scrub((1+absq):end));
            else
                shift_TC=TC';
                shift_ref=GS';
            end
            lagcorrall(v,f)=corr(shift_ref(shift_scrub),shift_TC(shift_scrub,:));
            frames_shift(f)=sum(~isnan(shift_ref(shift_scrub).*shift_TC(shift_scrub,1)));
        end
        
        %[peak_lag,peak_cov]= parabolic_interp_pos(lagcorrall(v,:),p,TR);
        [peak_lag,peak_cov]= parabolic_interp_nick(lagcorrall(v,:),p,TR);
        runVLcorr(v)=peak_cov;
        if max(lagcorrall(v,:))>corrthreshold
            VLtau(v)=peak_lag; % lag value vertex to homologue vertex
            
        else
            goodvoxels(v)=0;
        end
    end
    subplot(4,1,2);hist(runVLcorr);
    subplot(4,1,3);hist(VLtau);
    if 0
        figure
        for i=1:length(VLtau)
            if VLtau(i)<-4
                plot(p*2,lagcorrall(i,:),'k','LineWidth',3);
                xlabel('Shift (TR)');ylabel('Correlation')
                title(num2str(VLtau(i)))
                ylim([-0.3 0.3])
                grid on
                pause
            end
        end
    end
    lagmap=sprintf('/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/%s/FCmaps_uwrp/lagmap',patid);
    save_gifti10k('162_lagmap',-VLtau',VLtau')
%     system(sprintf('wb_command -metric-smoothing /data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/%s/atlas/fsaverage_LR10k/%s.L.midthickness.10k_fs_LR.surf.gii %s.L.func.gii 10 %s_10.L.func.gii',patid,patid,lagmap,lagmap))
%     system(sprintf('wb_command -metric-smoothing /data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/%s/atlas/fsaverage_LR10k/%s.R.midthickness.10k_fs_LR.surf.gii %s.R.func.gii 10 %s_10.R.func.gii',patid,patid,lagmap,lagmap))
%     
    L=nanmean(VLtau)
    Laterality(patnum)=L;
    clear VLtau lagcorrall
    %    try
    %     catch
    %         fprintf('\n%s: Subject final ctx.dtseries.nii not found.\n',patid)
    %     end
end
% save(['/scratch/lag/Laterality/' patid(9:end) '_surfhomo_nosmooth_Laterality.mat'],'Laterality');