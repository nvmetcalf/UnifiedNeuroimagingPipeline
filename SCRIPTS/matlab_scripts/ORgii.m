function [ ORgiiRegion ] = ORgii( varargin )
%ORgii will or the list of gifti regions together. DO NOT mix hemispheres!

% load and test to make sure the regions are of the same length

    Regions = [];
    for i = 1:length(varargin)
        gii = gifti(varargin{i});
        gii = gii.cdata;
        %binarize
        gii(find(gii ~= 0)) = 1;
        
        disp(sprintf('%s: DefinedVert = %i', varargin{i}, count(find(gii > 0))));
        Regions = horzcat(Regions, gii);
    end

    % logical OR all the verticies
    for i = 1:length(Regions(:,1))
       if(max(Regions(i,:)) ~= 0 || min(Regions(i,:)) ~= 0)
           ORgiiRegion(i,1) = 1;
       else
           ORgiiRegion(i,1) = 0;
       end
    end
    
    disp(sprintf('OR vertex count: %i', count(find(ORgiiRegion > 0))));
end

