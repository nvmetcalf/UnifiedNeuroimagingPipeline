function [ Hemisphere_SurfaceMap ] = CiftiToGiftiAtlas( CiftiValues, GiftiSurfaceMask )
%Takes the values of CiftiValues and maps them to the defined vertices in
%the Gifti surface mask in order from top to bottom. Current;y used in the
%SurfaceSeedCorr script to go from whole brain cifti to himi sphere gifti.

    
    Hemisphere_SurfaceMap = [];
    
    if(sum(GiftiSurfaceMask) ~= length(CiftiValues))
        disp(sprintf('Num. Cifti Values: %i \n Num. of Defined Gifti Verticies: %i', length(CiftiValues), sum(GiftiSurfaceMask) ));
        error('The binary GiftiSurfaceMask does not encode for the same number of verticies CiftiValues has.');
    end
    
    Hemisphere_SurfaceMap = zeros(length(GiftiSurfaceMask),1);

    CiftiMapIndex = 1;

    for( j = 1:length(GiftiSurfaceMask))
        if(GiftiSurfaceMask(j,1))
            Hemisphere_SurfaceMap(j,1) = CiftiValues(CiftiMapIndex,1);
            CiftiMapIndex = CiftiMapIndex + 1;
        end
    end
end

