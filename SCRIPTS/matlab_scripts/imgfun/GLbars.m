function [nw_weights] = GLbars( vals, colormaptitle,bignet)
%GLVISFC creates an FC plot based on Gordon-Laumann Parcellation seperated
%by RSN labels as defined in Gordon 2015 Cerebral Cortex.
%
% vals - a 328 vector or a vector
% colormaptitle - optional title for the colormap
% if barpot=1, make a bargraph that has abs network totals
%  Josh Siegel 9/9/2015

% load('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered.mat');
% [nw_nl,b] = unique(GL.Community,'stable');
if ~exist('bignet','var');bignet=0;end
b = [1,39,46,83,91,114,153,176,180,185,217,241,281,325];
nw_n = {'VIS','RSPT','SMD','SMV','AUD','CON','VAN','SAL','CP','DAN','FPN','DMN','NON'}';

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
%mycolor=[0 0 153;255 255 204;51 255 255;255 128 0;153 51 255;77 0 153;0 153 153;0 0 0;0 0 255;0 204 0;255 255 0;255 0 0;171 171 171];
%mycolor=mycolor/255;
if bignet %% Only select large networks
for i=1:13
    nw_regions(i) = sum(b(i+1)-b(i));
end
GoodNetworks= find(nw_regions>7);
else
GoodNetworks = 1:length(nw_n);
end

n=length(GoodNetworks);

for i=1:n
    x=zeros(n,1);
    ii=GoodNetworks(i);
    x(i)=nanmean(vals(b(ii):(b(ii+1)-1)))/324;
    bar(x,'FaceColor',ncol_rgb{GoodNetworks(i)}./255);hold on
    nw_weights(i) = x(i);  
end

set(gca,'XTickLabel',nw_n(GoodNetworks))
if exist('colormaptitle','var')
title(colormaptitle)
end
end