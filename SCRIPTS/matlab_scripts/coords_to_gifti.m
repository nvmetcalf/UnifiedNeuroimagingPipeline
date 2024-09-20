disk_radius = 6;
max_search_distance = 6;

region_coord_file = '/data/nil-bluearc/ances_prod/Pipelines/UNPv2/SCRIPTS/Parcellation/AncesBigBrain298/BigBrain298_MNI_coords.txt';
%exclude_regions = [9,72,102,107,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245,246,247,248,249,250,251,272,273,274,275,276,277,278,279,280,281,282,283,284,285,286,287,288,289,290,291,292,293,294,295,296,297,298];
exclude_regions = [];

left_hemi_midthick = '/data/nil-bluearc/ances_prod/Projects/HIV/Participants/MNI152/Anatomical/Surface/MNI152_T1_1mm_32k/MNI152.L.midthickness.32k_fs_LR.surf.gii';
left_hemi_sphere = '/data/nil-bluearc/ances_prod/Projects/HIV/Participants/MNI152/Anatomical/Surface/MNI152_T1_1mm_32k/MNI152.L.sphere.32k_fs_LR.surf.gii';

right_hemi_midthick = '/data/nil-bluearc/ances_prod/Projects/HIV/Participants/MNI152/Anatomical/Surface/MNI152_T1_1mm_32k/MNI152.R.midthickness.32k_fs_LR.surf.gii';
right_hemi_sphere = '/data/nil-bluearc/ances_prod/Projects/HIV/Participants/MNI152/Anatomical/Surface/MNI152_T1_1mm_32k/MNI152.R.sphere.32k_fs_LR.surf.gii';

%==========================================================================

region_coords = importdata(region_coord_file);

left_hemi_midthick = gifti(left_hemi_midthick);
left_hemi_midthick = left_hemi_midthick.vertices;

left_hemi_sphere = gifti(left_hemi_sphere);
left_hemi_sphere = left_hemi_sphere.vertices;

right_hemi_midthick = gifti(right_hemi_midthick);
right_hemi_midthick = right_hemi_midthick.vertices;

right_hemi_sphere = gifti(right_hemi_sphere);
right_hemi_sphere = right_hemi_sphere.vertices;

%==========================================================================

left_hemi_rois = zeros(length(left_hemi_midthick(:,1)),1);
right_hemi_rois = zeros(length(right_hemi_midthick(:,1)),1);

region_coords(exclude_regions,:) = nan;

closest_vertex_info = [];

for i = 1:length(region_coords(:,1))
    disp(i);
    closest_vertex_dist = 9999999;
    closest_vertex = -1;
    side = -1;  % 1 = left, 2 = right
    %check the current ROI coord against all the left hemi
    for j = 1:length(left_hemi_midthick)
        if(sqrt((left_hemi_midthick(j,1) - region_coords(i,1))^2 ...
              + (left_hemi_midthick(j,2) - region_coords(i,2))^2 ...
              + (left_hemi_midthick(j,3) - region_coords(i,3))^2)  < closest_vertex_dist ...
         && sqrt((left_hemi_midthick(j,1) - region_coords(i,1))^2 ...
              + (left_hemi_midthick(j,2) - region_coords(i,2))^2 ...
              + (left_hemi_midthick(j,3) - region_coords(i,3))^2) <= max_search_distance)
          
            closest_vertex_dist = sqrt((left_hemi_midthick(j,1) - region_coords(i,1))^2 ...
              + (left_hemi_midthick(j,2) - region_coords(i,2))^2 ...
              + (left_hemi_midthick(j,3) - region_coords(i,3))^2);
            closest_vertex = j;
            side = 1;
        end
    end
    
    %check against the right hemi
    for j = 1:length(right_hemi_midthick)
        if(sqrt((right_hemi_midthick(j,1) - region_coords(i,1))^2 ...
              + (right_hemi_midthick(j,2) - region_coords(i,2))^2 ...
              + (right_hemi_midthick(j,3) - region_coords(i,3))^2)  < closest_vertex_dist ...
          && sqrt((right_hemi_midthick(j,1) - region_coords(i,1))^2 ...
              + (right_hemi_midthick(j,2) - region_coords(i,2))^2 ...
              + (right_hemi_midthick(j,3) - region_coords(i,3))^2) <= max_search_distance)
          
            closest_vertex_dist = sqrt((right_hemi_midthick(j,1) - region_coords(i,1))^2 ...
              + (right_hemi_midthick(j,2) - region_coords(i,2))^2 ...
              + (right_hemi_midthick(j,3) - region_coords(i,3))^2);
            closest_vertex = j;
            side = 2;
        end
    end
    
   
    %size the disk
    if(side == 1) %left
        left_hemi_rois(closest_vertex) = i;
        closest_vertex_coords = left_hemi_sphere(closest_vertex,:);
        
        for j = 1:length(left_hemi_sphere(:,1))
            if(sqrt((left_hemi_sphere(j,1) - closest_vertex_coords(1))^2 ...
              + (left_hemi_sphere(j,2) - closest_vertex_coords(2))^2 ...
              + (left_hemi_sphere(j,3) - closest_vertex_coords(3))^2) <= disk_radius)
                left_hemi_rois(j) = i;
            end
        end
        
    elseif(side == 2) %right
        right_hemi_rois(closest_vertex) = i;
        closest_vertex_coords = right_hemi_sphere(closest_vertex,:);
        
        for j = 1:length(right_hemi_sphere(:,1))
            if(sqrt((right_hemi_sphere(j,1) - closest_vertex_coords(1))^2 ...
              + (right_hemi_sphere(j,2) - closest_vertex_coords(2))^2 ...
              + (right_hemi_sphere(j,3) - closest_vertex_coords(3))^2) <= disk_radius)
                right_hemi_rois(j) = i;
            end
        end
    else
        disp('no valid side!');
        continue;
    end
    
    closest_vertex_info = vertcat(closest_vertex_info, [i side closest_vertex closest_vertex_dist]);
    disp([i side closest_vertex closest_vertex_dist]);
    
end

save_gii('BigAnces298', 32, left_hemi_rois, right_hemi_rois);