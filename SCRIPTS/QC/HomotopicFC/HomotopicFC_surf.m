function [ hfc ] = HomotopicFC_surf( dtseries ,outfile, tmask,L_mask,R_mask)
%HomotopicFC_surf Creates a map of homotopic FC for every vertex and saves
%the image to output.
%   Example: HomotopicFC_surf('/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_024_A/FCmaps_uwrp/FCS_024_A_faln_dbnd_xr3d_uwrp_atl_uout_resid_bpss.ctx.dtseries.nii' ,'/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_024_A/FCmaps_uwrp/FCS_024_A_homotopicFC.ctx.dtseries.nii','/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_024_A/FCmaps_uwrp/DVAR_33.5_DDAT_0.5/tmask.txt', '/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/FCS_024_A/Masks/FCS_024_A_lesion_ifhfix.L.10k.func.gii')
% Goals:
% 1) Load preprocessed data
% 2) Mask all voxels not in gray matter
% 3) Measure homotopic FC in every voxel
[outdir, dtfname, ext] = fileparts(dtseries);
[outdir, fname, ext] = fileparts(outfile);
if ~exist(outdir,'dir'); mkdir(outdir);end % Make outdir if it doesnt exist.

%% Load Temporal Mask
if strmatch(tmask((end-5):end),'format') % if you used a format file
    [~,formkey] = system(['format2lst `cat ' tmask '` -e']);
    formkey = regexprep(formkey,'\s','');
    Scrub=zeros(size(formkey));
    Scrub(formkey=='+')=1;
elseif strmatch(tmask((end-5):end),'panded') % if you used a format file
    [~,formkey] = system(['cat ' tmask ]);
    formkey = regexprep(formkey,'\s','');
    Scrub=zeros(size(formkey));
    Scrub(formkey=='+')=1;
else
    Scrub=importdata(tmask); % load a temporal mask
    Scrub(isnan(Scrub))=[];
end

AuxMask = [];

fprintf('Number of usable frames = %d/%d\n',sum(Scrub),length(Scrub))

if(sum(Scrub) == 0)
   disp('not enough data to compute homotopic FC');
   return;
end
%% Mask Lesion

v = []
if(exist('L_mask') || exist('R_mask'))
    %see if there is a left mask and mask by the hemispehere mask
    if(~isempty(L_mask))
        disp(['Reading: ' L_mask]);
        temp = gifti(L_mask);
        
        if(isempty(v)) %set the vertex space based on the masks
            v = length(temp.cdata) * 2;
            disp(['Vertex space: ' num2str(v/2)]);
        end
        
        AuxMask(1:v/2) = temp.cdata;
        %clear L_maskVertices;        
    end
    
    %see if there is a right mask and mask by the hemispehere mask
    if(~isempty(R_mask))        
        disp(['Reading: ' R_mask]);
        temp = gifti(R_mask);
        
        if(isempty(v))
            v = length(temp.cdata) * 2;
            disp(['Vertex space: ' num2str(v/2)]);
        end
        
        AuxMask((v/2+1):v) = temp.cdata;
        %clear R_maskVertices;        
    end
else
    disp('No surface mask has been found.');
end
    
%% Load raw timecourses
if(~exist(dtseries))
    disp('no data');
    return;
end

data=ft_read_cifti_mod(dtseries);
v = length(data.brainstructure) - length(find(data.brainstructure > 2));    %number of surface verts
lverts = sum(data.brainstructure==1);
rverts = sum(data.brainstructure==2);
TC = nan(v,size(data.data,2));
TC(data.brainstructure == 1,:) = data.data(1:lverts,:);
TC(data.brainstructure == 2,:) = data.data((lverts+1):(lverts+rverts),:);

%% Now Mask TC by lesion mask and by temporal mask
disp('Mask dtseries by temporal mask and lesion mask');
if(isempty(AuxMask))
    AuxMask = zeros(v,1);
end

TC(logical(AuxMask),:) = nan;
TC(:,Scrub==0) = [];

LTC=TC(1:v/2,:);
RTC=TC((v/2+1):v,:);

%% compute homotopic FC
% Display some basic QC metrics
a = figure('Position',[0,0,1440,720]);
subplot(2,1,1);
imagesc(Scrub);
colormap('bone');
freezeColors;
set(gca,'YTick',[]);
set(gca,'XTick',[0:100:length(Scrub)]);
xlabel('Frame');
title('Temporal Mask')

disp('Computing homotopic FC');
hfc = nan(v/2,1);
for i=1:v/2
hfc(i) = atanh(corr(LTC(i,:)',RTC(i,:)','rows','pairwise'));
end
subplot(2,1,2)
hist(hfc,40)
colormap('jet');
freezeColors;
ylabel('Number of Vertices');
xlabel('Homotopic Correlation (fZ)');
set(gca,'XLim',[-1 1]);
set(gca,'XTick',[-1:0.1:1]);

title('Distribution of Homotopic FC');
saveas(a,['distribution_of_homotopic_fc.png'], 'png');

data.data(1:lverts) = hfc(data.brainstructure == 1);
data.data((lverts+1):lverts+rverts) = hfc(find(data.brainstructure == 2)-v/2);

data.data(:,2:end) = [];    %clear out the other timepoints

data.time = 1:size(data.data,2);
ft_write_cifti_mod(outfile,data);


