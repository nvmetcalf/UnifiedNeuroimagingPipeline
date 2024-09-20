 function NetworkMean = GL_avg_ntwk( Matrix_In, range, colormaptitle)
%GLVISFC creates an FC plot based on Gordon-Laumann Parcellation seperated
%by RSN labels as defined in Gordon 2015 Cerebral Cortex.
%
% FC - a 328 matrix or a vector
% range - the min and max values for the colomap
% colormaptitle - optional title for the colormap
%  Josh Siegel 9/9/2015

% load('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered.mat');
% [nw_nl,b] = unique(GL.Community,'stable');


set(gcf,'Color',[1 1 1])

NetworkBoundaries = [1,39,46,83,91,114,153,176,180,185,217,241,281];
NetworkNames = {'VIS','RSPT','SMD','SMV','AUD','CON','VAN','SAL','CP','DAN','FPN','DMN','NON'}';

%initialize a matrix to the size of our network names
NetworkMean = nan(length(NetworkBoundaries),length(NetworkBoundaries))

Matrix_In(Matrix_In == 1) = NaN;

%fisherZ transform the input matrix so we can average
FC_fZ = fisherz(Matrix_In);

%loop through the matrix making the network "cell" means

for i = 1:length(NetworkBoundaries)
    Start1 = NetworkBoundaries(i);
    if(i+1>length(NetworkBoundaries))
        End1 = length(FC_fZ(i,:));
    else
        End1 = NetworkBoundaries(i+1);
    end
        
    for j = 1:length(NetworkBoundaries)
        Start2 = NetworkBoundaries(j);
        if(j+1>length(NetworkBoundaries))
            End2 = length(FC_fZ(j,:));
        else
            End2 = NetworkBoundaries(j+1);
        end
        
        NetworkCellMatrix = FC_fZ(Start1:End1,Start2:End2);
        NetworkCellVector = reshape(NetworkCellMatrix,1,[]);
        %NetworkCellVector(NetworkCellVector == inf) = NaN;
        NetworkMean(i,j) = nanmean(NetworkCellVector);
        
    end
end

try
    imagesc(NetworkMean,[range(1) range(2)])
catch
    imagesc(NetworkMean)  
end
colorbar
set(gca,'XTickLabel', NetworkNames,'XTick',1:length(NetworkNames),'YTickLabel', NetworkNames,'YTick',1:length(NetworkNames))
if exist('colormaptitle','var')
    title(colormaptitle)
end