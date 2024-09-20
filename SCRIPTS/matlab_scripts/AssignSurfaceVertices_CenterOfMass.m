function [ SurfaceHemisphere HemiSphereVertexData ] = AssignSurfaceVertices_CenterOfMass( HemiSphereTriplets, HemiSphereVertexData, HemiSphereRegions, HemiSphereVertices )
%AssignSurfaceRegions_CenterOfMass takes computed center of mass for a list
%of regions and assigns vertices from regions that overlap to a region
%based on the linear distance from the regions volumetric center of mass
%and the vertex in volume.

    SurfaceHemisphere(1:length(HemiSphereVertexData(:,1)),1) = 0;

    %Find region vertices that overlap on each hemisphere
    for i = 1:length(HemiSphereVertexData(:,1))
        if(length(find(HemiSphereVertexData(i,:) > 0)) > 1)
            %find out which region the vertex is closest to and
            %assign the vertex to that region
            ClosestRegion = [0 100000000 0];

            %find all the vertices that are adjacent to the
            %vertex we are interested in. This will keep down
            %the possible regions that will be assigned.
            AdjacentFaces = [find(HemiSphereTriplets(:,1) == i); find(HemiSphereTriplets(:,2) == i); find(HemiSphereTriplets(:,3) == i)];

            AdjacentVertices = [];
            for j = 1:length(AdjacentFaces)
                AdjacentVertices = horzcat(AdjacentVertices, HemiSphereTriplets(AdjacentFaces(j),:));
            end

            %keep only the unique vertices
            AdjacentVertices = unique(AdjacentVertices);

            %make sure we do not keep the vertex we are working
            %with.
            AdjacentVertices(find(AdjacentVertices == i)) = [];

            %find out which regions correspond to those vertices. This is
            %the column index of this vertex. NOT the actual region ID
            %itself. We match that up later.
            AdjacentRegions = [];
            for j = 1:length(AdjacentVertices)
                %Get the columns of all regions of the current
                %vertex
                Vertex = find(HemiSphereVertexData(AdjacentVertices(j),:) > 0);

                %only grab single region vertices as we may come
                %back around to assign the vertex later. We only
                %need the column index, we don't actually really
                %care much about the region id itself yet.
                %if( length(Vertex) == 1)
                    AdjacentRegions = horzcat(AdjacentRegions, Vertex);
                %end
            end

            AdjacentRegions = unique(AdjacentRegions);

            %we now have an initial list of regions that are
            %ajacent to the vertex in question. Now we need to do a
            %sanity check to make sure all the regions are in the
            %hemisphere we are interested in.

            k = 1;
            while(k <= length(AdjacentRegions))
                Found = false;
                for l = 1:length(HemiSphereRegions)
                    if(HemiSphereRegions(l).RegionID == HemiSphereRegions(AdjacentRegions(k)).RegionID)
                        Found = true;
                        break;
                    end
                end

                if(~Found)
                    AdjacentRegions(k) = [];
                else
                    k = k + 1;
                end
            end

            %we have our list of available, adjacent regions. See
            %which is closest to the vertex.
            for j = 1:length(AdjacentRegions)

                RegionIndex = AdjacentRegions(j);

                if(sqrt((HemiSphereRegions(RegionIndex).CenterOfMass(1) - HemiSphereVertices(i,1) )^2 + ...
                        (HemiSphereRegions(RegionIndex).CenterOfMass(2) - HemiSphereVertices(i,2) )^2 + ...
                        (HemiSphereRegions(RegionIndex).CenterOfMass(3) - HemiSphereVertices(i,3) )^2) ...
                        < ClosestRegion(1,2))
                    ClosestRegion = [HemiSphereRegions(RegionIndex).RegionID sqrt( ...
                        (HemiSphereRegions(RegionIndex).CenterOfMass(1) - HemiSphereVertices(i,1) )^2 + ...
                        (HemiSphereRegions(RegionIndex).CenterOfMass(2) - HemiSphereVertices(i,2) )^2 + ...
                        (HemiSphereRegions(RegionIndex).CenterOfMass(3) - HemiSphereVertices(i,3) )^2) RegionIndex];
                end
            end

            disp(['Assigning vertex ' num2str(i) ' to region ' num2str(ClosestRegion(1,1))]);
            SurfaceHemisphere(i,1) = ClosestRegion(1,1);
            HemiSphereVertexData(i,:) = 0;
            HemiSphereVertexData(i,ClosestRegion(1,3)) = ClosestRegion(1,1);
        elseif(length(find(HemiSphereVertexData(i,:) > 0)) == 1)
            SurfaceHemisphere(i,1) = HemiSphereVertexData(i,find(HemiSphereVertexData(i,:) > 0));
        end
    end
end

