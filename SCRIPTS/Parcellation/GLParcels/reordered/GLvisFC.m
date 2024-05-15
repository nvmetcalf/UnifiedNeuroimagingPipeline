function GLvisFC( FC, range, colormaptitle)
%GLVISFC creates an FC plot based on Gordon-Laumann Parcellation seperated
%by RSN labels as defined in Gordon 2015 Cerebral Cortex.
%
% FC - a 328 matrix or a vector
% range - the min and max values for the colomap
% colormaptitle - optional title for the colormap
%  Josh Siegel 9/9/2015

% load('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered.mat');
% [nw_nl,b] = unique(GL.Community,'stable');
if size(FC,1)==1 || size(FC,2)==1
    FC=squareform(FC);
end

b = [1,39,46,83,91,114,153,176,180,185,217,241,281];
nw_n = {'VIS','RSPT','SMD','SMV','AUD','CON','VAN','SAL','CP','DAN','FPN','DMN','NON'}';
b(end+1)=size(FC,1)+1;
Pnew=nan(size(FC,1)+length(b)-2);
for r=1:length(nw_n)
    for c=1:length(nw_n)
        Pnew((b(r)+r-1):(b(r+1)+r-2),(b(c)+c-1):(b(c+1)+c-2)) = FC(b(r):(b(r+1)-1),b(c):(b(c+1)-1));
    end
    mid(r) = (b(r)+b(r+1))/2+r-2;
end
% If a range is provided, use it. Otherwise, default
try
    imagesc(Pnew,[range(1) range(2)])
catch
    imagesc(Pnew)  
end
colorbar
set(gca,'XTickLabel', nw_n,'XTick',mid,'YTickLabel', nw_n,'YTick',mid)
if exist('colormaptitle','var')
    title(colormaptitle)
end
set(gcf,'color',[1 1 1])
end

