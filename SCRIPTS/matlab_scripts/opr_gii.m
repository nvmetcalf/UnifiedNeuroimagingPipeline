function [ giiAnswer ] = opr_gii( Operation, varargin)
%opr_gii performs the operation requested on all the gifti images provided
%and returns the gifti surface vector (Answer)
%   + : sum all gifti surface images
%   - : subrtact gifti2 from gifti1. Do not specify more than 2 gifti
%   surfaces
%   * : multiply all gifti images
%   / : divide gifti1 by gifti2. Do not specify more than 2 gifti surfaces
%   mean : mean of each vertex across provided surfaces
%   sd : standard deviation of each vertex across all surfaces
%   var: variance of each vertex across all surfaces
%
%   you can specify constant values.
%

    giiAnswer = [];
    NumberOfVertices = [];
    %load the first known gifti and it becomes the "template" for testing
    %if the others conform
    
    for i = 1:length(varargin)
        if(strcmp(GetExtension(varargin{i}),'gii'))
            
            t = gifti(varargin{i});
            
            NumberOfVertices = length(t.cdata);
            clear t;
        end
    end
    
    %load the surfaces

    giiSurfaces = [];
    
    for i = 1:length(varargin)
        ReadSurface = [];
        if(strcmp(GetExtension(varargin{i}),'gii'))
            ReadSurface = gifti(varargin{i});
            ReadSurface = ReadSurface.cdata;
        else
            %assume it is a constant
            if(isnumeric(varargin{i}))
                ReadSurface(1:NumberOfVertices,1) = varargin{i};
            else
                ReadSurface(1:NumberOfVertices,1) = str2num(varargin{i});
            end
        end
        
        giiSurfaces = horzcat(giiSurfaces, ReadSurface);
    end
    
    switch(Operation)
        case '+'
            for i = 1:NumberOfVertices
                giiAnswer(i,1) = sum(giiSurfaces(i,:));
            end
        case '-'
            for i = 1:NumberOfVertices
                giiAnswer(i,1) = giiSurfaces(i,1) - giiSurfaces(i,2);
            end
        case '*'
            for i = 1:NumberOfVertices
                giiAnswer(i,1) = prod(giiSurfaces(i,:));
            end
        case '/'
            for i = 1:NumberOfVertices
                giiAnswer(i,1) = giiSurfaces(i,1) / giiSurfaces(i,2);
            end
        case 'mean'
            for i = 1:NumberOfVertices
                giiAnswer(i,1) = mean(giiSurfaces(i,:));
            end
        case 'sd'
            for i = 1:NumberOfVertices
                giiAnswer(i,1) = std(giiSurfaces(i,:));
            end
        case 'var'
            for i = 1:NumberOfVertices
                giiAnswer(i,1) = var(giiSurfaces(i,:));
            end
        otherwise
            error('Unknown operation selected!');
    end
end

