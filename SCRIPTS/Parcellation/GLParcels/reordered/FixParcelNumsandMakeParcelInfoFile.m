%% Fix the ROIs so that there is 328 numbered 1:328, and create a label document with COG, network, and unique names (specifyingside) for each
addpath(genpath('/data/nil-bluearc/corbetta/Studies/SurfaceStroke/scripts'))
addpath(genpath('/data/nil-bluearc/corbetta/PP_SCRIPTS/SurfacePipeline'))

load('GLPCommunities_reordered_32k.mat')
oldCommunity = Community;clear Community;
%% Load GL Parcels
GLL = gifti('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_whole_10k_reordered.L.10k.func.gii');
GLR = gifti('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_whole_10k_reordered.R.10k.func.gii');
x = [GLL.cdata ;GLR.cdata];
[ROIs]= unique(x);ROIs(ROIs==0)=[];
%% Load coordinates
RightSurface = gifti('/data/nil-bluearc/corbetta/Studies/SurfaceStroke/ROIs/FCS_FSLR10k.R.midthickness.surf.gii');
LeftSurface = gifti('/data/nil-bluearc/corbetta/Studies/SurfaceStroke/ROIs/FCS_FSLR10k.L.midthickness.surf.gii');
coords = [LeftSurface.vertices ; RightSurface.vertices];
D = pdist(coords);
vertdistances = squareform(D);clear D
for s = 1:20484; vertdistances(s,s)=nan; end

for i=1:length(ROIs)
    verts = sum(x == ROIs(i));
    if verts < 10
        bv = find(x == ROIs(i));
        for v = 1:length(bv)
            [a b] = min(vertdistances(bv(v),:));
            x(bv(v)) = x(b);
        end
    end
end
[ROIs]= unique(x);ROIs(ROIs==0)=[];



fileID = fopen('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/ParcelLabels_reordered.txt','r');
dataArray = textscan(fileID, '%s%*s%*s%*s%*s%[^\n\r]', 'Delimiter', ' ', 'MultipleDelimsAsOne', true,  'ReturnOnError', false);


GL.gii = zeros(20484,1);
for i=1:length(ROIs)
    rn = ROIs(i);
    GL.verts(i) = sum(x==rn);
    GL.gii(x == rn) = i;
    GL.ROIcoords(i,:) = nanmean(coords(x == rn,:),1);
    GL.Community(i,1) = oldCommunity(rn);
    if GL.ROIcoords(i,1) < 0
        GL.Name{i,1} = ['L' dataArray{1,1}{rn*2-1}];
    else
        GL.Name{i,1} = ['R' dataArray{1,1}{rn*2-1}];
    end
end
GL.ROIs= unique(GL.target);GL.ROIs(GL.ROIs==0)=[];
save_gii('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered','10k',[],GL.gii(1:10242),GL.gii(10243:end));
save('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered.mat','GL')


[network,b,ROInetwork] = unique(GL.Community,'stable');
ncol_rgb{1} = [0 0 153]; % 
ncol_rgb{2} = [255 255 204]; % 
ncol_rgb{3} = [51 255 255]; % 
ncol_rgb{4} = [255 128 0]; % 
ncol_rgb{5} = [153 51 255]; % 
ncol_rgb{6} = [77 0 153]; % 
ncol_rgb{7} = [0 153 153]; % 
ncol_rgb{8} = [0 0 0]; % 
ncol_rgb{9} = [0 0 255]; % 
ncol_rgb{10} = [0 204 0]; % 
ncol_rgb{11} = [255 255 0]; % 
ncol_rgb{12} = [255 0 0]; % 
ncol_rgb{13} = [171 171 171]; % 
% Make ROI labels based on key
%[network,IA,ROInetwork] = unique(Community);
%labelID=Community;
Community = GL.Community;
labelID = GL.Name;
filenam='ParcelLabels_324_reordered.txt';
fid=fopen(filenam,'w')
for i=1:length(Community)
    nw=strmatch(Community(i),network);
    fprintf(fid,'%s \n%d %g %g %g %d\n',labelID{i},i,ncol_rgb{ROInetwork(i)}(1),ncol_rgb{ROInetwork(i)}(2),ncol_rgb{ROInetwork(i)}(3),255);  
end
fclose(fid)

