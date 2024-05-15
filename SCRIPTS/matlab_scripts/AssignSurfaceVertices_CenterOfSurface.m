function [SurfaceHemisphere] = AssignSurfaceVertices_CenterOfSurface( VertexData, InflatedVertexCoords, SurfaceRadius )
%AssignSurfaceRegions_CenterOfSurface takes computed center of mass for a list
%of regions and assigns vertices to the region. The closest vertex to the
%center of mass of the region is used as the surface region center. All
%vertices wthin SurfaceRadius are assigned to that region. Regions are
%assigned on a first come first serve basis.

    SurfaceHemisphere(1:length(VertexData(:,1)),1) = 0;

    if(length(VertexData(:,1)) ~= length(InflatedVertexCoords(:,1)))
        error('Number of verticies in VertexData differs from InflatedVertexCoords');
    end
    
    for i = 1:length(VertexData(1,:))
        %find all vertices that the region was projected onto
        Vertices = find(VertexData(:,i) > 0); 
        
        RegionID = find(VertexData(:,i) > 0);
        if(length(RegionID) == 0)
            SurfaceHemisphere(i,1) = 0;
        else
            ClosestVertex = [0 0 0 100000000000 -1];
            
            RegionID = VertexData(RegionID(1,1),i);

            %compute the center of mass
            CenterofMass = mean(InflatedVertexCoords(Vertices,:));


            %find the vertex closest to the center of surface area 
            for j = 1:length(InflatedVertexCoords(:,1))

                Distance = sqrt((CenterofMass(1) - InflatedVertexCoords(j,1) )^2 + ...
                            (CenterofMass(2) - InflatedVertexCoords(j,2) )^2 + ...
                            (CenterofMass(3) - InflatedVertexCoords(j,3) )^2);

                if(Distance < ClosestVertex(1,4))
                    ClosestVertex = [ InflatedVertexCoords(j,1) InflatedVertexCoords(j,2) InflatedVertexCoords(j,3) Distance j];
                end
            end

            %should have a vertex, now assign all vertices to the region within
            %a radius.
            for j = 1:length(InflatedVertexCoords(:,1))

                Distance = sqrt((ClosestVertex(1) - InflatedVertexCoords(j,1) )^2 + ...
                            (ClosestVertex(2) - InflatedVertexCoords(j,2) )^2 + ...
                            (ClosestVertex(3) - InflatedVertexCoords(j,3) )^2);

                %assign the vertices to a region based on distance from the
                %center of surface mass.
                if(Distance < SurfaceRadius)
                    SurfaceHemisphere(j,1) = RegionID;
                end
            end
            
        end
    end
end

