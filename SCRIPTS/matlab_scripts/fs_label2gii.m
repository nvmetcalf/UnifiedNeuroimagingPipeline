
%SubjectID = 'FCS_109_A';
%StudyPath = '/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects';
%KeepIntermediateFiles = false;
%ClusterSurfaceRegions = 4;
 
%list of labels that are to be sampled into 10k surface registered space
%RegionFileList = {'rh.V1dorsal_c1.label';'rh.V1dorsal_c2.label';'rh.V1dorsal_c3.label';'rh.V1-ventral_c1.label';'rh.V1-ventral_c2.label';'rh.V1-ventral_c3.label';...
%                        'lh.V1dorsal_c1.label';'lh.V1dorsal_c2.label';'lh.V1dorsal_c3.label';'lh.V1-ventral_c1.label';'lh.V1-ventral_c2.label';'lh.V1-ventral_c3.label';};

%RegionFileList = {'Yeo2011_7Networks_MNI152_FreeSurferConformed1mm_LiberalMask_333_t88.nii'};
                    
function [success] = region2gii(SubjectID, StudyPath, RegionFileList, KeepIntermediateFiles, ClusterSurfaceRegions)
    % transform a freesurfer label, 4dfp region, and nifti region file to
    % the subjects non-linear warped surface
    %   The filenames MUST start with a l or a r to denote left or right
    %   hemisphere.
    %
    %   4dfp images may be multi region images. If they are, the individual
    %   regions will be extracted from the 4dfp image.
    %
    % ClusterSurfaceRegions has a few ways of handling overlapping vertices:
    %   1. Discard all overlapping vertices
    %   2. First come first serve
    %   3. Last come last serve
    %   4. Center of mass
    %
    
    success = false;
    LeftVertexData = [];
    RightVertexData = [];
    
    %Directory of the surface in atlas space
    NativeDir = [StudyPath '/' SubjectID '/atlas/Native'];    
    
    %read the freesurfcer subject directory variable so we know where to
    %look for the surface anatomy.
    FreeSurfer_SubjectDir = getenv('SUBJECTS_DIR');
        
    i = 0;
    while(i < length(RegionFileList))
        
        i = i + 1;
        Label = RegionFileList{i};
        
        switch(GetExtension(Label))
            case 'img'  %is a 4dfp img region/region file
                
                Image = read_4dfp_img(Label);
                
                DefinedVoxel = cast(Image.voxel_data(Image.voxel_data >= 1), 'uint16');
                
                if(min(DefinedVoxel) ~= max(DefinedVoxel))
                    
                    disp([Label ' is a multi-region 4dfp volume. Extracting into its sub regions.']);
                    %this is a 4dfp region file, need to extract each
                    %region individually and insert them into the region
                    %list in place
                    temp = Image;
                    
                    ExtractedRegionFilenames = {};
                    %work from max to min
                    for j = sort(min(DefinedVoxel):max(DefinedVoxel),'descend')
                                                
                        temp.voxel_data = zeros(length(Image.voxel_data(:,1)),1);
                        
                        %assign all voxels of the current region
                        for k = 1:length(Image.voxel_data(:,1))
                            if(Image.voxel_data(k,1) == j)
                                temp.voxel_data(k,1) = j;
                            end
                        end
                        
                        %write the 4dfp image
                        write_4dfp_img(temp, [string_extension(strip_extension(Label)) '_r' num2str(j) '.4dfp.img']);
                        
                        ExtractedRegionFilenames = vertcat( ExtractedRegionFilenames, [string_extension(strip_extension(Label)) '_r' num2str(j) '.4dfp.img']);
                    end
                    
                    %insert the new filenames into the region list
                    if(length(RegionFileList) == 1)
                        RegionFileList = {ExtractedRegionFilenames};
                    elseif(i > 1)
                        RegionFileList = {RegionFileList{1:i-1,1}; ExtractedRegionFilenames{:,1}; RegionFileList{i+1:length(RegionFileList),1};};
                    elseif(i == length(RegionFileList))
                        RegionFileList = {RegionFileList{1:i-1,1}; ExtractedRegionFilenames{:,1};};
                    else
                        RegionFileList = {ExtractedRegionFilenames{:,1}; RegionFileList{i+1:length(RegionFileList),1};};
                    end
                        
                    i = i - 1;  %we want to revisit this record as it is now a single region 4dfp roi
                    continue;
                else
                    %We have a single region, binarize it and convert to
                    %nifti
                    
                    disp([Label ' is a singe-region 4dfp volume. Converting to nifti.']);
                    Image.voxel_data = Image.voxel_data ./ Image.voxel_data;
                    
                    NiftiFilename = strip_extension(strip_extension(Label));
                    nifti_4dfp_command = [ 'nifti_4dfp -n ' NiftiFilename NiftiFilename '_mpr.nii' ];
                    assert(~system(nifti_4dfp_command,'-echo'));
                end
                
            case 'label'    %freesurfer label file
                %embed the surface defined labels into a nifti volume with the same
                %dimensions as the orig.mgz that the surface is based on

                NiftiFilename = [strip_extension(Label) '.nii'];
                label2vol_command = ['mri_label2vol --label ' Label ...
                                     ' --temp ' FreeSurfer_SubjectDir '/' SubjectID '/mri/orig.mgz' ...
                                     ' --regheader ' FreeSurfer_SubjectDir '/' SubjectID '/mri/orig.mgz' ...
                                     ' --fillthresh 1'...
                                     ' --o ' NiftiFilename];

                assert(~system(label2vol_command,'-echo'));

                %change the nifti image to a 4dfp image so we can transform it from
                %orig -> atlas
                nifti_4dfp_command = ['nifti_4dfp -4 ' NiftiFilename ' ' strip_extension(NiftiFilename)];

                assert(~system(nifti_4dfp_command,'-echo'));

                clear nifti_4dfp_command;

                %do the transform from orig - > atlas
                OrigtoMPRTransform = [StudyPath '/' SubjectID '/atlas/' SubjectID '_orig_to_' SubjectID '_mpr1_t4'];
                t4img_4dfp_command = ['t4img_4dfp ' OrigtoMPRTransform ' ' strip_extension(NiftiFilename) ' ' strip_extension(NiftiFilename) '_mpr -O/data/nil-bluearc/corbetta/Studies/SurfaceStroke/Subjects/' SubjectID '/atlas/' SubjectID '_mpr1 -n'];
                assert(~system(t4img_4dfp_command,'-echo'));

                %convert the atlas transformed 4dfp back to nifti
                nifti_4dfp_command = [ 'nifti_4dfp -n ' strip_extension(NiftiFilename) '_mpr ' strip_extension(NiftiFilename) '_mpr.nii' ];
                assert(~system(nifti_4dfp_command,'-echo'));
    
            case 'nii'  %nifti region
                nifti_image = niftiRead(Label);
                nifti_data = reshape(nifti_image.data,[],1);
                nifti_regions = nifti_data(nifti_data >= 1);
                
                %see if we are working with a single region nifti
                if(min(nifti_regions) ~= max(nifti_regions))
                    disp([Label ' is a multi-region nifti volume. Extracting into its sub regions.']);
                    %this is a 4dfp region file, need to extract each
                    %region individually and insert them into the region
                    %list in place
                    temp = nifti_data;
                    
                    ExtractedRegionFilenames = {};
                    %work from max to min
                    for j = min(nifti_regions):max(nifti_regions)
                                                
                        temp = zeros(length(nifti_data),1);
                        
                        %assign all voxels of the current region
                        for k = 1:length(nifti_data)
                            if(nifti_data(k) == j)
                                temp(k,1) = j;
                            end
                        end
                        
                        nifti_temp = nifti_image;
                        nifti_temp.data = reshape(temp,length(nifti_image.data(:,1,1)),length(nifti_image.data(1,:,1)),length(nifti_image.data(1,1,:)));
                        
                        %write the 4dfp image
                        fname = [strip_extension(Label) '_r' num2str(j) '.nii'];
                        save_nii(niftiVista2ni(nifti_temp), fname);
                        
                        ExtractedRegionFilenames = vertcat( ExtractedRegionFilenames, [strip_extension(Label) '_r' num2str(j) '.nii']);
                    end
                    
                    %insert the new filenames into the region list
                    temp_RegionFileList = {};
                    
                    for j = 1:length(RegionFileList)
                        if(j == i)
                            for k = 1:length(ExtractedRegionFilenames)
                                temp_RegionFileList = vertcat(temp_RegionFileList, ExtractedRegionFilenames{k,1});
                            end
                        else
                            temp_RegionFileList = vertcat(temp_RegionFileList, RegionFileList{j,1});
                        end
                    end
                    
                    RegionFileList = temp_RegionFileList;
%                     if(length(RegionFileList) == 1)
%                         RegionFileList = {ExtractedRegionFilenames};
%                     elseif(i > 1)
%                         RegionFileList = {RegionFileList{1:i-1,1}; ExtractedRegionFilenames{:,1}; RegionFileList{i+1:length(RegionFileList),1};};
%                     elseif(i == length(RegionFileList))
%                         RegionFileList = {RegionFileList{1:i-1,1}; ExtractedRegionFilenames{:,1};};
%                     else
%                         RegionFileList = {ExtractedRegionFilenames{:,1}; RegionFileList{i+1:length(RegionFileList),1};};
%                     end
                        
                    i = i - 1;  %we want to revisit this record as it is now a single region 4dfp roi
                    continue;
                else
                    %We have a single region, binarize it and convert to
                    %nifti
                    
                    disp([Label ' is a singe-region nifti volume. Appending with _mpr.nii.']);
                    NiftiFilename = [strip_extension(Label) '.nii'];
                    movefile(Label, [strip_extension(NiftiFilename) '_mpr.nii']);
                    
                end
        end
        
        
        %extract the hemisphere information
        HemiSphere = upper(Label(1));

        disp([ 'Hemisphere is ' HemiSphere]);
        
        %project the region onto th 10k surface
        wb_command = ['wb_command -volume-to-surface-mapping ' strip_extension(NiftiFilename) '_mpr.nii ' NativeDir '/' SubjectID '.' HemiSphere '.midthickness.native.surf.gii ' strip_extension(NiftiFilename) '_mpr.surf.gii' ...
                      ' -ribbon-constrained ' NativeDir '/' SubjectID '.' HemiSphere '.white.native.surf.gii ' NativeDir '/' SubjectID '.' HemiSphere '.pial.native.surf.gii'];
        
        %converting
        assert(~system(wb_command,'-echo'));
        
        wb_command = ['wb_command -metric-resample ' strip_extension(NiftiFilename) '_mpr.surf.gii ' NativeDir '/' SubjectID '.' HemiSphere '.sphere.reg.reg_LR.native.surf.gii ' NativeDir '/../fsaverage_LR10k/' SubjectID '.' HemiSphere '.sphere.10k_fs_LR.surf.gii ' ...
                      'ADAP_BARY_AREA ' strip_extension(NiftiFilename) '_mpr_surf.' HemiSphere '.10k_fs_LR.func.gii -area-surfs ' NativeDir '/' SubjectID '.' HemiSphere '.midthickness.native.surf.gii ' NativeDir '/../fsaverage_LR10k/' SubjectID '.' HemiSphere '.midthickness.10k_fs_LR.surf.gii -current-roi ' NativeDir '/' SubjectID '.' HemiSphere '.roi.native.shape.gii'];
		
        assert(~system(wb_command,'-echo'));
        
        %Assign the surface region vertices to a region number. The number
        %will be based upon the index of the region label in the region
        %list.
        gifti_region = gifti([strip_extension(NiftiFilename) '_mpr_surf.' HemiSphere '.10k_fs_LR.func.gii']);
       
        
        for j = 1:length(gifti_region.cdata)
            if(gifti_region.cdata(j,1) > 0)
                gifti_region.cdata(j,1) = i;
            end
        end
        
        %Cluster each individual region into a single gifti region file
        if(ClusterSurfaceRegions > 0)
            
            if(HemiSphere == 'L')
                LeftVertexData = horzcat(LeftVertexData, gifti_region.cdata); %left
            else
                RightVertexData = horzcat(RightVertexData, gifti_region.cdata); %right
            end
        else
            %or save each individual region
            save_gifti(gifti_region, [strip_extension(NiftiFilename) '_mpr_surf_region.' HemiSphere '.10k_fs_LR.func.gii']);
        end
        
        if(~KeepIntermediateFiles)
            disp('Removing intermediate files');
            delete(NiftiFilename, ...
                   [ strip_extension(NiftiFilename) '.4dfp.*'], ...
                   [ strip_extension(NiftiFilename) '_r*.4dfp.*'], ...
                   [ strip_extension(NiftiFilename) '_mpr.4dfp.*'], ...
                   [ strip_extension(NiftiFilename) '_mpr.nii']);
        end
    end
    
    %cluster the regions together by hemisphere. This will also mask all
    %the regions by each other so only unique vertices will remain. 
    switch(ClusterSurfaceRegions)
        case 1
            disp('Clustering regions and excluding all overlapping vertices.');
            LeftHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
            RightHemiSphere(1:length(RightVertexData(:,1)),1) = 0;

            IncludedVertices = 0;
            OverlappingVertices = 0;
            RegionVertices = 0;
            disp('Clustering Left HemiSphere...');
            for i = 1:length(LeftHemiSphere)
                if(length(find(LeftVertexData(i,:) > 0)) == 1)
                    LeftHemiSphere(i,1) = max(LeftVertexData(i,:));
                    IncludedVertices = IncludedVertices + 1;
                    RegionVertices = RegionVertices + 1;
                elseif(length(find(LeftVertexData(i,:) > 0)) > 1)
                    OverlappingVertices = OverlappingVertices +1;
                else
                    IncludedVertices = IncludedVertices + 1;
                end
            end

            disp(['Vertices Included: ' num2str(IncludedVertices) ' out of ' num2str(length(LeftVertexData)) '. Difference: ' num2str(length(LeftVertexData) - IncludedVertices)]);
            disp(['Number of Region Vertices that overlap: ' num2str(OverlappingVertices)]);
            disp(['Total Number of vertices in a ROI: ' num2str(RegionVertices)]);

            IncludedVertices = 0;
            OverlappingVertices = 0;
            RegionVertices = 0;
            disp('Clustering Right HemiSphere...');
            for i = 1:length(LeftHemiSphere)
                if(length(find(RightVertexData(i,:) > 0)) == 1)
                    RightHemiSphere(i,1) = max(RightVertexData(i,:));
                    IncludedVertices = IncludedVertices + 1;
                    RegionVertices = RegionVertices + 1;
                elseif(length(find(RightVertexData(i,:) > 0)) > 0)
                    OverlappingVertices = OverlappingVertices +1; 
                else
                    IncludedVertices = IncludedVertices + 1;
                end
            end

            disp(['Vertices Included: ' num2str(IncludedVertices) ' out of ' num2str(length(RightVertexData)) '. Difference: ' num2str(length(RightVertexData) - IncludedVertices)]);
            disp(['Number of Region Vertices that overlap: ' num2str(OverlappingVertices)]);
            disp(['Total Number of vertices in a ROI: ' num2str(RegionVertices)]);
            
            save_gifti10k([SubjectID '_mpr_surf_cluster_exld'], LeftHemiSphere, RightHemiSphere);
            
        %%=================================================================
        case 2
            disp('Clustering using first come first serve...');
            LeftHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
            RightHemiSphere(1:length(RightVertexData(:,1)),1) = 0;

            IncludedVertices = 0;
            OverlappingVertices = 0;
            RegionVertices = 0;
            disp('Clustering Left HemiSphere...');
            for i = 1:length(LeftHemiSphere)
                if(length(find(LeftVertexData(i,:) > 0)) > 0)
                    LeftHemiSphere(i,1) = LeftVertexData(i,find(LeftVertexData(i,:) > 0, 1, 'first'));
                    IncludedVertices = IncludedVertices + 1;
                    RegionVertices = RegionVertices + 1;
                else
                    IncludedVertices = IncludedVertices + 1;
                end
            end

            disp(['Vertices Included: ' num2str(IncludedVertices) ' out of ' num2str(length(LeftVertexData)) '. Difference: ' num2str(length(LeftVertexData) - IncludedVertices)]);
            disp(['Total Number of vertices in a ROI: ' num2str(RegionVertices)]);

            IncludedVertices = 0;
            RegionVertices = 0;
            disp('Clustering Right HemiSphere...');
            for i = 1:length(LeftHemiSphere)
                if(length(find(RightVertexData(i,:) > 0)) > 0)
                    RightHemiSphere(i,1) = RightVertexData(i,find(RightVertexData(i,:) > 0, 1, 'first'));
                    IncludedVertices = IncludedVertices + 1;
                    RegionVertices = RegionVertices + 1;
                else
                    IncludedVertices = IncludedVertices + 1;
                end
            end

            disp(['Vertices Included: ' num2str(IncludedVertices) ' out of ' num2str(length(RightVertexData)) '. Difference: ' num2str(length(RightVertexData) - IncludedVertices)]);
            disp(['Total Number of vertices in a ROI: ' num2str(RegionVertices)]);
            
            save_gifti10k([SubjectID '_mpr_surf_cluster_fcfs'], LeftHemiSphere, RightHemiSphere);
            %%=================================================================
        case 3
            disp('Clustering using last come first serve...');
            LeftHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
            RightHemiSphere(1:length(RightVertexData(:,1)),1) = 0;

            IncludedVertices = 0;
            OverlappingVertices = 0;
            RegionVertices = 0;
            disp('Clustering Left HemiSphere...');
            for i = 1:length(LeftHemiSphere)
                if(length(find(LeftVertexData(i,:) > 0)) > 0)
                    LeftHemiSphere(i,1) = LeftVertexData(i,find(LeftVertexData(i,:) > 0, 1, 'last'));
                    IncludedVertices = IncludedVertices + 1;
                    RegionVertices = RegionVertices + 1;
                else
                    IncludedVertices = IncludedVertices + 1;
                end
            end

            disp(['Vertices Included: ' num2str(IncludedVertices) ' out of ' num2str(length(LeftVertexData)) '. Difference: ' num2str(length(LeftVertexData) - IncludedVertices)]);
            disp(['Total Number of vertices in a ROI: ' num2str(RegionVertices)]);

            IncludedVertices = 0;
            RegionVertices = 0;
            disp('Clustering Right HemiSphere...');
            for i = 1:length(LeftHemiSphere)
                if(length(find(RightVertexData(i,:) > 0)) > 0)
                    RightHemiSphere(i,1) = RightVertexData(i,find(RightVertexData(i,:) > 0, 1, 'last'));
                    IncludedVertices = IncludedVertices + 1;
                    RegionVertices = RegionVertices + 1;
                else
                    IncludedVertices = IncludedVertices + 1;
                end
            end

            disp(['Vertices Included: ' num2str(IncludedVertices) ' out of ' num2str(length(RightVertexData)) '. Difference: ' num2str(length(RightVertexData) - IncludedVertices)]);
            disp(['Total Number of vertices in a ROI: ' num2str(RegionVertices)]);
            
            save_gifti10k([SubjectID '_mpr_surf_cluster_lcfs'], LeftHemiSphere, RightHemiSphere);
            %%=================================================================
        case 4
            disp('Clustering regions using center of mass');
            
            LeftHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
            RightHemiSphere(1:length(RightVertexData(:,1)),1) = 0;
            
            %load the vertex to volume mappings
            LeftHemiSphereVertices = gifti([StudyPath '/' SubjectID '/atlas/fsaverage_LR10k/' SubjectID '.L.midthickness.10k_fs_LR_on_TRIO_STROKE_NDC.surf.gii']);
            LeftHemiSphereVertices = LeftHemiSphereVertices.vertices;
            
            RightHemiSphereVertices = gifti([StudyPath '/' SubjectID '/atlas/fsaverage_LR10k/' SubjectID '.R.midthickness.10k_fs_LR_on_TRIO_STROKE_NDC.surf.gii']);
            RightHemiSphereVertices = RightHemiSphereVertices.vertices;
            
            %make a list of all the regions
            LeftHemiSphereRegions = struct('RegionID',{},'VolumeCoordinates',{});
            RightHemiSphereRegions = struct('RegionID',{},'VolumeCoordinates',{});
            
            %go through each hemisphere and identify regions and make a
            %list of all the coordinates in each region
            %search by region
            for i = 1:length(LeftVertexData(1,:))
                for j = 1:length(LeftVertexData(:,1))
                    if(LeftVertexData(j,i) > 0)
                        %search through the list
                        k = 1;
                        FoundRegion = false;
                        while( k <= length(LeftHemiSphereRegions) && ~FoundRegion)

                            if(LeftHemiSphereRegions(k).RegionID == LeftVertexData(j,i))
                                %it is a known region, add the coordinates
                                LeftHemiSphereRegions(k).VolumeCoordinates = vertcat(LeftHemiSphereRegions(k).VolumeCoordinates, [LeftHemiSphereVertices(j,:) j]);
                                FoundRegion = true;
                            end
                            k = k + 1;
                        end

                        %the region isn't known, so make a record for it.
                        if(~FoundRegion && LeftVertexData(j,i))
                            LeftHemiSphereRegions(length(LeftHemiSphereRegions) + 1).RegionID = LeftVertexData(j,i);
                            LeftHemiSphereRegions(length(LeftHemiSphereRegions)).VolumeCoordinates = [LeftHemiSphereVertices(j,:) j];
                        end
                    end
                end
            end
            
            %go through each hemisphere and identify regions and make a
            %list of all the coordinates in each region
            for i = 1:length(RightVertexData(1,:))
                for j = 1:length(RightVertexData(:,1))
                    if(RightVertexData(j,i) > 0)
                        %search through the list
                        k = 1;
                        FoundRegion = false;
                        while( k <= length(RightHemiSphereRegions) && ~FoundRegion)

                            if(RightHemiSphereRegions(k).RegionID == RightVertexData(j,i))
                                %it is a known region, add the coordinates
                                RightHemiSphereRegions(k).VolumeCoordinates = vertcat(RightHemiSphereRegions(k).VolumeCoordinates, [RightHemiSphereVertices(j,:) j]);
                                FoundRegion = true;
                            end
                            k = k + 1;
                        end

                        %the region isn't known, so make a record for it.
                        if(~FoundRegion)
                            RightHemiSphereRegions(length(RightHemiSphereRegions) + 1).RegionID = RightVertexData(j,i);
                            RightHemiSphereRegions(length(RightHemiSphereRegions)).VolumeCoordinates = [RightHemiSphereVertices(j,:) j];
                        end
                    end
                end
            end
            
            %Calculate the mean coordinate of each ROI
            for i = 1:length(LeftHemiSphereRegions)
                LeftHemiSphereRegions(i).CenterOfMass = mean(LeftHemiSphereRegions(i).VolumeCoordinates(:,1:3));
            end

            for i = 1:length(RightHemiSphereRegions)
                  RightHemiSphereRegions(i).CenterOfMass = mean(RightHemiSphereRegions(i).VolumeCoordinates(:,1:3));
            end
                        
            %Find region vertices that overlap on each hemisphere
            for i = 1:length(LeftVertexData(:,1))
                if(length(find(LeftVertexData(i,:) > 0)) > 1)
                    %find out which region the vertex is closest to and
                    %assign the vertex to that region
                    ClosestRegion = [0 100000000];
                    for j = 1:length(LeftHemiSphereRegions)
                        if(sqrt((LeftHemiSphereRegions(j).CenterOfMass(1) - LeftHemiSphereVertices(i,1) )^2 + ...
                                (LeftHemiSphereRegions(j).CenterOfMass(2) - LeftHemiSphereVertices(i,2) )^2 + ...
                                (LeftHemiSphereRegions(j).CenterOfMass(3) - LeftHemiSphereVertices(i,3) )^2) ...
                                < ClosestRegion(1,2) && (LeftVertexData(i-1,j) ~= 0 && LeftVertexData(i+1,j) ~= 0))
                                ClosestRegion = [LeftHemiSphereRegions(j).RegionID sqrt( ...
                                                (LeftHemiSphereRegions(j).CenterOfMass(1) - LeftHemiSphereVertices(i,1) )^2 + ...
                                                (LeftHemiSphereRegions(j).CenterOfMass(2) - LeftHemiSphereVertices(i,2) )^2 + ...
                                                (LeftHemiSphereRegions(j).CenterOfMass(3) - LeftHemiSphereVertices(i,3) )^2)];
                        end
                    end
                                           
                    disp(['Assigning vertex ' num2str(i) ' to region ' num2str(ClosestRegion(1,1))]);
                    LeftHemiSphere(i,1) = ClosestRegion(1,1);
                        
                elseif(length(find(LeftVertexData(i,:) > 0)) == 1)
                    LeftHemiSphere(i,1) = LeftVertexData(i,find(LeftVertexData(i,:) > 0));
                end
            end
            
            for i = 1:length(RightVertexData(:,1))
                if(length(find(LeftVertexData(i,:) > 0)) > 1)
                    %find out which region the vertex is closest to and
                    %assign the vertex to that region
                    ClosestRegion = [0 100000000];
                    for j = 1:length(RightHemiSphereRegions)
                        if( sqrt( ...
                                 (RightHemiSphereRegions(j).CenterOfMass(1) - RightHemiSphereVertices(i,1) )^2 + ...
                                 (RightHemiSphereRegions(j).CenterOfMass(2) - RightHemiSphereVertices(i,2) )^2 + ...
                                 (RightHemiSphereRegions(j).CenterOfMass(3) - RightHemiSphereVertices(i,3) )^2) ...
                                 < ClosestRegion(1,2) && (RightVertexData(i-1,j) ~= 0 && RightVertexData(i+1,j) ~= 0))
                           ClosestRegion = [RightHemiSphereRegions(j).RegionID sqrt( ...
                                 (RightHemiSphereRegions(j).CenterOfMass(1) - RightHemiSphereVertices(i,1) )^2 + ...
                                 (RightHemiSphereRegions(j).CenterOfMass(2) - RightHemiSphereVertices(i,2) )^2 + ...
                                 (RightHemiSphereRegions(j).CenterOfMass(3) - RightHemiSphereVertices(i,3) )^2)];
                        end
                    end
                    disp(['Assigning vertex ' num2str(i) ' to region ' num2str(ClosestRegion(1,1))]);
                    RightHemiSphere(i,1) = ClosestRegion(1,1);
                elseif(length(find(RightVertexData(i,:) > 0)) == 1)
                    RightHemiSphere(i,1) = RightVertexData(i,find(RightVertexData(i,:) > 0, 1));
                end
            end
            
            save_gifti10k([SubjectID '_mpr_surf_cluster_com'], LeftHemiSphere, RightHemiSphere);
            disp('');
            %%=================================================================
    end

    success = true;
%end
    
