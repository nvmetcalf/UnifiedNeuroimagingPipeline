function [ ANDgiiRegion ] = ANDgii( varargin )
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

    % logical AND all the verticies
    ANDgiiRegion = ones(length(Regions(:,1)),1);
    
    for i = 1:length(Regions(:,1))
        for j = 1:length(Regions(1,:))
            if(Regions(i,j) == 0)
                ANDgiiRegion(i,1) = 0;
            end
        end
    end
    
    disp(sprintf('AND vertex count: %i', count(find(ANDgiiRegion > 0))));
end

