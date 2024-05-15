lh_parc = gifti('/data/nil-bluearc/vlassenko/Pipeline/Projects/Resilience_MRI/Analysis/Schaefer2018_200Parcels_7Networks_order.L.32k.label.gii');
rh_parc = gifti('/data/nil-bluearc/vlassenko/Pipeline/Projects/Resilience_MRI/Analysis/Schaefer2018_200Parcels_7Networks_order.R.32k.label.gii');
lh_parc_data_orig = lh_parc.cdata;
rh_parc_data_orig = rh_parc.cdata;
lh_shape = gifti('/data/nil-bluearc/ances_prod/Projects/HIV/Participants/MNI152/Anatomical/Surface/MNI152_T1_1mm_32k/MNI152.L.sphere.32k_fs_LR.surf.gii');
rh_shape = gifti('/data/nil-bluearc/ances_prod/Projects/HIV/Participants/MNI152/Anatomical/Surface/MNI152_T1_1mm_32k/MNI152.R.sphere.32k_fs_LR.surf.gii');
lh_shape_faces = lh_shape.faces;
rh_shape_faces = rh_shape.faces;
lh_shape_coords = lh_shape.vertices;
rh_shape_coords = rh_shape.vertices;

% %find vertices that are surrounded by a single other parcellation
% disp('Finding single vertices surrounded by multiple other parcellations, not 0');
% lh_parc_data_fixed = lh_parc_data_orig;
% rh_parc_data_fixed = rh_parc_data_orig;
% 
% for i = 1:length(lh_parc_data_orig)
%     
%     %find all vertices within 3mm
%     neighbors = [];   
% 	for z = 1:length(lh_shape_coords(:,1))
%         if(sqrt((lh_shape_coords(z,1) - lh_shape_coords(i,1))^2 ...
%             + (lh_shape_coords(z,2) - lh_shape_coords(i,2))^2 ...
%             + (lh_shape_coords(z,3) - lh_shape_coords(i,3))^2) < 3)
%             neighbors = vertcat(neighbors, z);
%         end
%     end
%     %grab parcel values, drop 0
%     vertex_vals = lh_parc_data_orig(neighbors);
%     vertex_vals(vertex_vals == 0) = [];
%     
%     if(length(unique(vertex_vals)) > 1)
%         lh_parc_data_fixed(i) = mode(vertex_vals);
%     end
%     
%     neighbors = [];   
% 	for z = 1:length(rh_shape_coords(:,1))
%         if(sqrt((rh_shape_coords(z,1) - rh_shape_coords(i,1))^2 ...
%             + (rh_shape_coords(z,2) - rh_shape_coords(i,2))^2 ...
%             + (rh_shape_coords(z,3) - rh_shape_coords(i,3))^2) <= 3)
%             neighbors = vertcat(neighbors, z);
%         end
% 	end
%     vertex_vals = rh_parc_data_orig(neighbors);
%     vertex_vals(vertex_vals == 0) = [];
%     
%     if(length(unique(vertex_vals)) > 1)
%     	rh_parc_data_fixed(i) = mode(vertex_vals);
%     end   
%     
%     if(mod(i, 1000) == 0)
%         disp(i);
%     end
% end
% 
% lh_parc_data_orig = lh_parc_data_fixed;
% rh_parc_data_orig = rh_parc_data_fixed;
% 
% save_gii('Schaefer2018_200Parcels_7Networks_order_FSLMNI152_1mm_enclosed_mode', 32, lh_parc_data_orig, rh_parc_data_orig);
% 
% % find conclaves - regions surrounded by a single other region
% disp('Detecting Conclaves in Left Hemisphere...');
% 
% %for i = 1:length(lh_parc_data_orig)
% %while(i < = length(lh_parc_data_orig))
% i = 1;
% lh_checked_vertices = [];
% while( i <= length(lh_parc_data_orig))
%     HasBeenChecked = false;
%     
%     for j = 1:length(lh_checked_vertices)
%         if(lh_checked_vertices(j) == i)
%             HasBeenChecked == true;
%             break;
%         end
%     end
%     SourceEdgeVertices = [];
%     if(~HasBeenChecked)
%         [ SourceConnectingVertices SourceEdgeVertices SourceVisitedVertices ] = collect_neighbors( lh_shape_coords, lh_parc_data_orig, i );
%     
%         lh_checked_vertices = vertcat(lh_checked_vertices, SourceVisitedVertices);
%     end
%     %we have all edges of the current parcel that the current region is in
%     if(length(unique(SourceEdgeVertices(:,2))) == 1)
%         lh_parc_data_orig(unique([SourceConnectingVertices;SourceVisitedVertices;])) = mode(double(SourceEdgeVertices(:,2)));
%         disp(['lh Vertex: ' num2str(i) ' is part of a conclave.']);
%     else
%         i = i + 1;
%     end   
%     
%     if(mod(i, 1000) == 0)
%         disp(i);
%     end
% %      elseif(length(unique(SourceEdgeVertices(:,2))) > 1)
% %          %need to evaluate all regions that are edges.
% %          %Any region that only boarders any regions in the edges of the test
% %          %region, are set to the test regions id.
% %          %then retest the region for conclavity
% %          %drop regions that boarder other regions that are not in the edge
% %          %list
% %          RegionsToTest = unique(SourceEdgeVertices(:,2));
% %          RegionsCollected = [];
% %          for l = 1:length(RegionsToTest)
% %              
% %              SeedVertices = SourceEdgeVertices(SourceEdgeVertices(:,2) == RegionsToTest(l),1);
% %              
% %              for n = 1:length(SeedVertices)
% %                  [ SeedConnectingVertices SeedEdgeVertices SeedVisitedVertices ] = collect_neighbors( lh_shape_faces, lh_parc_data_orig, SeedVertices(n));
% %                  RegionSet = [SourceEdgeVertices(:,2); SeedEdgeVertices(:,2)]
% %                  RegionSet(RegionSet == lh_parc_data_orig(i) | lh_parc_data_orig(SeedVertices(n))) = [];
% %                  if(length(RegionSet) == 1)
% %                      lh_parc_data_orig(SeedConnectingVertices) = lh_parc_data_orig(i);
% %                  end
% %              end
% %          end
% %         % i does not increment so we can retest to new current shape
% %     else
% %         %it is a stand alone region
% %         i = i + 1;
% %     end
% end
% 
% disp('Detecting Conclaves in Right Hemisphere...');
% 
% i = 1;
% while( i <= length(rh_parc_data_orig))
%     [ SourceConnectingVertices SourceEdgeVertices SourceVisitedVertices ] = collect_neighbors( rh_shape_coords, rh_parc_data_orig, i );
%     
%     %we have all edges of the current parcel that the current region is in
%     if(length(unique(SourceEdgeVertices(:,2))) == 1)
%         rh_parc_data_orig(unique([SourceConnectingVertices;SourceVisitedVertices;])) = mode(double(SourceEdgeVertices(:,2)));
%         disp(['rh Vertex: ' num2str(i) ' is part of a conclave.']);
%     else
%         i = i + 1;
%     end
%     
%     if(mod(i, 1000) == 0)
%         disp(i);
%     end
% end
% 
% save_gii('Schaefer2018_200Parcels_7Networks_order_FSLMNI152_1mm_enclosed_mode_nc', 32, lh_parc_data_orig, rh_parc_data_orig);

% zero out vertices that boarder more than 1 region.
disp('Creating borders.');
for i = 1:length(lh_parc_data_orig)
    
    neighbors_faces = find(lh_shape_faces(:,1) == i | lh_shape_faces(:,2) == i | lh_shape_faces(:,3) == i);
    neighbor_vertices = unique(lh_shape_faces(neighbors_faces));
    vertex_vals = unique(lh_parc_data_orig(neighbor_vertices));
    vertex_vals(vertex_vals == 0) = [];
    
    if(length(vertex_vals) > 1)
        lh_parc_data_fixed(i) = 0;
    else
        lh_parc_data_fixed(i) = lh_parc_data_orig(i);
    end
    
    neighbors_faces = find(rh_shape_faces(:,1) == i | rh_shape_faces(:,2) == i | rh_shape_faces(:,3) == i);
    neighbor_vertices = unique(rh_shape_faces(neighbors_faces));
    vertex_vals = unique(rh_parc_data_orig(neighbor_vertices));
    vertex_vals(vertex_vals == 0) = [];
    
    if(length(vertex_vals) > 1)
    	rh_parc_data_fixed(i) = 0;
    else
        rh_parc_data_fixed(i) = rh_parc_data_orig(i);
    end
end

save_gii('Schaefer2018_200Parcels_7Networks_order_borders', 32, lh_parc_data_fixed, rh_parc_data_fixed);