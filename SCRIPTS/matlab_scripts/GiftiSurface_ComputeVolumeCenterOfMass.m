function [ HemiSphereRegions ] = GiftiSurface_ComputeVolumeCenterOfMass( HemiSphereVertices, HemiSphereVertexData )
%GiftiSurface_ComputeVolumeCenterOfMass computes the volumetric center of
%mass of a surface region.

    %make a list of all the regions
    HemiSphereRegions = struct('RegionID',{},'VolumeCoordinates',{});

    %go through each hemisphere and identify regions and make a
    %list of all the coordinates in each region
    %search by region
    for i = 1:length(HemiSphereVertexData(1,:))
        for j = 1:length(HemiSphereVertexData(:,1))
            if(HemiSphereVertexData(j,i) > 0)
                %search through the list
                k = 1;
                FoundRegion = false;
                while( k <= length(HemiSphereRegions) && ~FoundRegion)

                    if(HemiSphereRegions(k).RegionID == HemiSphereVertexData(j,i))
                        %it is a known region, add the coordinates
                        HemiSphereRegions(k).VolumeCoordinates = vertcat(HemiSphereRegions(k).VolumeCoordinates, [HemiSphereVertices(j,:) j]);
                        FoundRegion = true;
                    end
                    k = k + 1;
                end

                %the region isn't known, so make a record for it.
                if(~FoundRegion && HemiSphereVertexData(j,i))
                    HemiSphereRegions(length(HemiSphereRegions) + 1).RegionID = HemiSphereVertexData(j,i);
                    HemiSphereRegions(length(HemiSphereRegions)).VolumeCoordinates = [HemiSphereVertices(j,:) j];
                end
            end
        end
    end

    %Calculate the mean coordinate of each ROI
    for i = 1:length(HemiSphereRegions)
        HemiSphereRegions(i).CenterOfMass = mean(HemiSphereRegions(i).VolumeCoordinates(:,1:3));
    end
end

