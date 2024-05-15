function [success RegionFileList] = region2gii(SubjectID, StudyPath, RegionFileList, TargetSubjectID, KeepIntermediateFiles, ClusterSurfaceRegions, ClusterArg, TargetSpace)
    % transform a freesurfer label, 4dfp region, and nifti region file to
    % the subjects surface
    %
    %   4dfp images may be multi region images. If they are, the individual
    %   regions will be extracted from the 4dfp image.
    %
    %   TargetSubjectID is the name of antoher subject in the StudyPath
    %   that you would like to use instead of the SubjectID for warping to
    %   the surface.
    %
    %   ClusterSurfaceRegions has a few ways of handling overlapping vertices:
    %       1. Discard all overlapping vertices
    %       2. First come first serve
    %       3. Last come last serve
    %       4. Center of mass
    %       5. Surface Center of Mass
    %           Requires ClusterArg to be set to a distance in mm
    %
    %       6. ClusterArg is used when ClusterSurfaceRegions requires more
    %           parameters.
    %       7. TargetSpace is the number of vertices you want to use for
    %       the region mesh. Options are 10 (default) and 32.
    %
    

    
    success = false;
    LeftVertexData = [];
    RightVertexData = [];
    
    if(isempty(RegionFileList))
        error('Region list is empty!');
    end
    
    if(~exist('TargetSubjectID'))
        TargetSubjectID = SubjectID;
    elseif(isempty(TargetSubjectID))
        TargetSubjectID = SubjectID;
    end
    
    if(~exist('KeepIntermediateFiles'))
        KeepIntermediateFiles = false;
    end
    
    if(~exist('ClusterSurfaceRegions'))
        ClusterSurfaceRegions = false;
    end
    
    if(~iscell(RegionFileList))
        %convert the string to a cell array
        FileListString = RegionFileList;
        
        RegionFileList = cell(0);
        
        Start = 1;
        for i = 1:length(FileListString)
            if(FileListString(i) == ',' || FileListString(i) == ' ')
                RegionFileList = horzcat(RegionFileList,FileListString(Start:i-1));
                
                Start = i + 1;
            end
        end
        
        RegionFileList = horzcat(RegionFileList,FileListString(Start:length(FileListString)));   %grab the last region
    end
    
    if(~exist('TargetSpace'))
        TargetSpace = 10;
    end
    %Set the Subject we are transforming to to the target
    %subject ID. If it wasn't defined by the user, then this
    %will be the SubjectID.
	UsedSubjectID = TargetSubjectID;
    
    %read the freesurfcer subject directory variable so we know where to
    %look for the surface anatomy.
    FreeSurfer_SubjectDir = getenv('SUBJECTS_DIR');
        
    %List of hemispheres that each region belongs to. Useful later when
    %assigning regions to vertices.
    HemiSphereList = [];
         
    i = 0;
    while(i < length(RegionFileList))
        
        i = i + 1;
        CurrentRegion = RegionFileList{i};
        
        %Directory of the surface in atlas space
        NativeDir = [StudyPath '/' UsedSubjectID '/atlas/TRIO_Y_NDC'];  
    
        switch(GetExtension(CurrentRegion))
            case 'img'  %is a 4dfp img region/region file
                IsSurface = false;
                
                Image = read_4dfp_img(CurrentRegion);
                
                DefinedVoxel = cast(Image.voxel_data(Image.voxel_data >= 1), 'uint16');
                
                if(min(DefinedVoxel) ~= max(DefinedVoxel))
                    
                    disp([CurrentRegion ' is a multi-region 4dfp volume. Extracting its sub regions.']);
                    %this is a 4dfp region file, need to extract each
                    %region individually and insert them into the region
                    %list in place
                    temp = Image;
                    
                    ExtractedRegionFilenames = {};
                    
                    RegionIndicies = sort(unique(DefinedVoxel));
                    j = 1;
                    
                    while(j <= length(RegionIndicies))
                             
                        RegionIndex = RegionIndicies(j);
                        temp = Image;
                        temp.voxel_data = zeros(length(Image.voxel_data(:,1)),1);
                        
                        %assign all voxels of the current region
                        for k = 1:length(Image.voxel_data(:,1))
                            if(Image.voxel_data(k,1) == RegionIndex)
                                temp.voxel_data(k,1) = RegionIndex;
                            end
                        end
                        
                        %write the 4dfp image
                        write_4dfp_img(temp, [strip_extension(strip_extension(CurrentRegion)) '_r' num2str(RegionIndex) '.4dfp.img']);
                        
                        ExtractedRegionFilenames = vertcat( ExtractedRegionFilenames, [strip_extension(strip_extension(CurrentRegion)) '_r' num2str(RegionIndex) '.4dfp.img']);
                        
                        j = j + 1;
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
                       
                    i = i - 1;  %we want to revisit this record as it is now a single region 4dfp roi
                    continue;
                else
                    %We have a single region, binarize it and convert to
                    %nifti
                    
                    if((Image.ifh_info.matrix_size(1) == 176 && Image.ifh_info.matrix_size(2) == 208 && Image.ifh_info.matrix_size(3) == 176) ...
                    || (Image.ifh_info.matrix_size(1) == 128 && Image.ifh_info.matrix_size(2) == 128 && Image.ifh_info.matrix_size(3) == 75) ...
                    || (Image.ifh_info.matrix_size(1) == 48 && Image.ifh_info.matrix_size(2) == 64 && Image.ifh_info.matrix_size(3) == 48))
                        disp(['grep AtlasName ' NativeDir '/../../' UsedSubjectID '*.params | cut -d= -f2']);
                        %determine the atlas used.
                         [br AtlasName] = system(['grep AtlasName ' NativeDir '/../../' UsedSubjectID '*.params | cut -d= -f2'],'-echo');
                         AtlasName = AtlasName(~isspace(AtlasName));
                         NativeDir = [StudyPath '/' UsedSubjectID '/atlas/' AtlasName];  
                    end
                    
                    disp([CurrentRegion ' is a singe-region 4dfp volume. Converting to nifti.']);
                    Image.voxel_data = Image.voxel_data ./ Image.voxel_data;
                    
                    
                    NiftiFilename = strip_extension(strip_extension(CurrentRegion));
                    CurrentImage = NiftiFilename;
                    
                    nifti_4dfp_command = [ 'nifti_4dfp -n ' NiftiFilename ' ' NiftiFilename '.nii' ];     
                    assert(~system(nifti_4dfp_command,'-echo'));
                    NiftiFilename = [ NiftiFilename '.nii' ];   
                end
                
            case 'label'    %freesurfer label file
                IsSurface = true;  % this will hopefully become surf->surf in the future
                %embed the surface defined labels into a nifti volume with the same
                %dimensions as the orig.mgz that the surface is based on

                mean_coord = mean(read_label(SubjectID, strip_extension(CurrentRegion)));
                
                if(mean_coord(2) < 0)   %lh
                    HemiSphere = 'L';
                    command = ['mris_convert --label ' CurrentRegion ' ' strip_extension(CurrentRegion) ' ' FreeSurfer_SubjectDir '/' SubjectID '/surf/lh.white ' strip_extension(CurrentRegion) '.gii' ];
                else
                    HemiSphere ='R';
                    command = ['mris_convert --label ' CurrentRegion ' ' strip_extension(CurrentRegion) ' ' FreeSurfer_SubjectDir '/' SubjectID '/surf/rh.white ' strip_extension(CurrentRegion) '.gii' ];
                end
                
                assert(~system(command,'-echo'));
                
%                 NiftiFilename = [strip_extension(Label) '.nii'];
%                 label2vol_command = ['mri_label2vol --label ' Label ...
%                                      ' --temp ' FreeSurfer_SubjectDir '/' SubjectID '/mri/orig.mgz' ...
%                                      ' --regheader ' FreeSurfer_SubjectDir '/' SubjectID '/mri/orig.mgz' ...
%                                      ' --fillthresh 1'...
%                                      ' --o ' NiftiFilename];
% 
%                 assert(~system(command,'-echo'));

                wb_command = ['wb_command -metric-resample ' strip_extension(CurrentRegion) '.gii ' NativeDir '/' SubjectID '.' HemiSphere '.sphere.reg.reg_LR.native.surf.gii ' NativeDir '/../fsaverage_LR' num2str(TargetSpace) 'k/' SubjectID '.' HemiSphere '.sphere.' num2str(TargetSpace) 'k_fs_LR.surf.gii BARYCENTRIC ' strip_extension(CurrentRegion) '.' HemiSphere '.' num2str(TargetSpace) 'k.func.gii'];
                assert(~system(wb_command,'-echo'));
                
%                 %change the nifti image to a 4dfp image so we can transform it from
%                 %orig -> atlas
%                 nifti_4dfp_command = ['nifti_4dfp -4 ' NiftiFilename ' ' strip_extension(NiftiFilename)];
% 
%                 assert(~system(nifti_4dfp_command,'-echo'));
% 
%                 clear nifti_4dfp_command;
% 
%                 %do the transform from orig - > atlas
%                 OrigtoMPRTransform = [StudyPath '/' UsedSubjectID '/atlas/' UsedSubjectID '_orig_to_' UsedSubjectID '_mpr1_t4'];
%                 t4img_4dfp_command = ['t4img_4dfp ' OrigtoMPRTransform ' ' strip_extension(NiftiFilename) ' ' strip_extension(NiftiFilename) '_mpr -O' StudyPath '/' UsedSubjectID '/atlas/' UsedSubjectID '_mpr1 -n'];
%                 assert(~system(t4img_4dfp_command,'-echo'));
% 
%                 %convert the atlas transformed 4dfp back to nifti
%                 nifti_4dfp_command = [ 'nifti_4dfp -n ' strip_extension(NiftiFilename) '_mpr ' strip_extension(NiftiFilename) '_mpr.nii' ];
%                 assert(~system(nifti_4dfp_command,'-echo'));

            case 'nii'  %nifti region
                IsSurface = false;
                
                nifti_image = niftiRead(CurrentRegion);
                nifti_data = reshape(nifti_image.data,[],1);
                nifti_regions = nifti_data(nifti_data >= 1);
                
                %see if we are working with a single region nifti
                if(min(nifti_regions) ~= max(nifti_regions))
                    disp([CurrentRegion ' is a multi-region nifti volume. Extracting into its sub regions.']);
                    %this is a 4dfp region file, need to extract each
                    %region individually and insert them into the region
                    %list in place
                    temp = nifti_data;
                    
                    ExtractedRegionFilenames = {};
                    
                    RegionIndicies = sort(unique(DefinedVoxel));
                    j = 1;
                    
                    while(j <= length(RegionIndicies))
                             
                        RegionIndex = RegionIndicies(j);
                                                
                        temp = zeros(length(nifti_data),1);
                        
                        %assign all voxels of the current region
                        for k = 1:length(nifti_data)
                            if(nifti_data(k) == RegionIndex)
                                temp(k,1) = RegionIndex;
                            end
                        end
                        
                        nifti_temp = nifti_image;
                        nifti_temp.data = reshape(temp,length(nifti_image.data(:,1,1)),length(nifti_image.data(1,:,1)),length(nifti_image.data(1,1,:)));
                        
                        %write the 4dfp image
                        fname = [strip_extension(CurrentRegion) '_r' num2str(RegionIndex) '.nii'];
                        save_nii(niftiVista2ni(nifti_temp), fname);
                        
                        ExtractedRegionFilenames = vertcat( ExtractedRegionFilenames, [strip_extension(CurrentRegion) '_r' num2str(RegionIndex) '.nii']);
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
                       
                    i = i - 1;  %we want to revisit this record as it is now a single region 4dfp roi
                    continue;
                else
                    %We have a single region, binarize it and convert to
                    %nifti
                    
                    disp([CurrentRegion ' is a singe-region nifti volume. Assuming in MPRAGE space.']);
                    
                end
                
            case 'mgh'  %mgh surface region
                
                
                %   Surface -> Surface if the surf->vol->surf doesn't work well
                IsSurface = true;
                
                %try left hemi sphere conversion
                disp('Attempting to convert volume-encoded-surface to a Left Hemisphere gifti...');
                command = ['mris_convert -c ' pwd '/' CurrentRegion ' ' FreeSurfer_SubjectDir '/' SubjectID '/surf/lh.white ' strip_extension(CurrentRegion) '.gii']
                
                HemiSphere = 'L';
                
                if(system(command)) %detects if we are a left or right hemisphere region based on the outcome of the overlay -> gifti conversion
                    disp('Region must be in Right Hemisphere...');
                    
                    command = ['mris_convert -c ' pwd '/' CurrentRegion ' ' FreeSurfer_SubjectDir '/' SubjectID '/surf/rh.white ' strip_extension(CurrentRegion) '.gii']
                    assert(~system(command));

                    HemiSphere = 'R';    
                end
                
                disp(['Success! Resampling freesurfer space region to ' num2str(TargetSpace) 'k template space.']);
                
                wb_command = ['wb_command -metric-resample ' strip_extension(CurrentRegion) '.gii ' NativeDir '/' SubjectID '.' HemiSphere '.sphere.reg.reg_LR.native.surf.gii ' NativeDir '/../fsaverage_LR' num2str(TargetSpace) 'k/' SubjectID '.' HemiSphere '.sphere.' num2str(TargetSpace) 'k_fs_LR.surf.gii BARYCENTRIC ' strip_extension(CurrentRegion) '.' HemiSphere '.' num2str(TargetSpace) 'k.func.gii'];
                assert(~system(wb_command,'-echo'));
                    
%                 command = ['mri_surf2vol --surfval ' Label ' --hemi lh --fillribbon --identity ' SubjectID ' --subject '...
%                             SubjectID ' --template ' FreeSurfer_SubjectDir '/' SubjectID '/mri/orig.mgz --o ' strip_extension(Label) '_vol.nii'];
%                 if(system(command,'-echo'))
%                     command = ['mri_surf2vol --surfval ' Label ' --hemi rh --fillribbon --identity ' SubjectID ' --subject '...
%                             SubjectID ' --template ' FreeSurfer_SubjectDir '/' SubjectID '/mri/orig.mgz --o ' strip_extension(Label) '_vol.nii'];
%                     assert(~system(command,'-echo'));
%                     
%                 end
%                 
%                 NiftiFilename = [strip_extension(Label) '_vol.nii'];
%                 
%                 %change the nifti image to a 4dfp image so we can transform it from
%                 %orig -> mpr
%                 nifti_4dfp_command = ['nifti_4dfp -4 ' NiftiFilename ' ' strip_extension(NiftiFilename)];
% 
%                 assert(~system(nifti_4dfp_command,'-echo'));
% 
%                 clear nifti_4dfp_command;
% 
%                 %do the transform from orig - > atlas
%                 OrigtoMPRTransform = [StudyPath '/' UsedSubjectID '/atlas/' UsedSubjectID '_orig_to_' UsedSubjectID '_mpr1_t4'];
%                 t4img_4dfp_command = ['t4img_4dfp ' OrigtoMPRTransform ' ' strip_extension(NiftiFilename) ' ' strip_extension(NiftiFilename) '_mpr -O' StudyPath '/' UsedSubjectID '/atlas/' UsedSubjectID '_mpr1 -n'];
%                 assert(~system(t4img_4dfp_command,'-echo'));
% 
%                 %convert the atlas transformed 4dfp back to nifti
%                 nifti_4dfp_command = [ 'nifti_4dfp -n ' strip_extension(NiftiFilename) '_mpr ' strip_extension(NiftiFilename) '_mpr.nii' ];
%                 assert(~system(nifti_4dfp_command,'-echo'));
            case 'gii'
                %gifti metric file
                %
                % to process properly, need to:
                %   1) break into sub-gifti files (one per file like with
                %       4dfp)
                %   2) add them to the list of regions properly (like 4dfp)
                %   3) verify they are in the proper vertex space
                %   4) flag them as IsSurface
                %   5) set the proper hemisphere
            otherwise
                error([CurrentRegion ' does not have a known extension.']);
        end
        
        %surface regions are resampled to a surface, so we know the
        %hemisphere. Volume regions need a bit more work to figure out
        %which hemisphere the region is in.
        if(~IsSurface)
            
            %we will need to figure out where the center of mass of the
            %region is to see if it is left or right hemisphere.
            CurrentRegionFileName = [strip_extension(NiftiFilename) '.nii'];
            
            %NiftiImage = niftiRead(CurrentRegionFileName);
            NiftiImage = load_nifti(CurrentRegionFileName);

            NiftiImage_Data = NiftiImage.vol;
            clear NiftiImage;

            Coordinates = [];
            for a = 1:length(NiftiImage_Data(:,1,1))
                for b = 1:length(NiftiImage_Data(1,:,1))
                    for c = 1:length(NiftiImage_Data(1,1,:))
                        if(NiftiImage_Data(a,b,c) > 0)
                            Coordinates = vertcat(Coordinates,[a b c]);
                        end    
                    end
                end
            end

            if(mean(Coordinates(:,1,1)) <= (length(NiftiImage_Data(:,1,1))/2))
                HemiSphere = 'L';
                HemiSphereList = vertcat(HemiSphereList, 0);
            elseif(mean(Coordinates(:,1,1)) > (length(NiftiImage_Data(:,1,1))/2))
                HemiSphere = 'R';
                HemiSphereList = vertcat(HemiSphereList, 1);
            else
                error('Could not determine the hemisphere the region resides in.');
            end

            disp(sprintf('Dataspace center of mass: X: \t%f \tY:%f \tZ: %f', mean(Coordinates(:,1,1)), mean(Coordinates(1,:,1)), mean(Coordinates(1,1,:))));
            disp([ 'Hemisphere is ' HemiSphere]);

            clear Coordinates NiftiImage_Data;

            %project the region onto the surface
            disp('Projecting to template space...');
            wb_command = ['nice +19 wb_command -volume-to-surface-mapping ' CurrentRegionFileName ' ' NativeDir '/' UsedSubjectID '.' HemiSphere '.midthickness.' num2str(TargetSpace) 'k_fs_LR.surf.gii ' strip_extension(CurrentRegionFileName) '.' HemiSphere '.' num2str(TargetSpace) 'k_fs_LR.func.gii' ...
                          ' -ribbon-constrained ' NativeDir '/' UsedSubjectID '.' HemiSphere '.white.' num2str(TargetSpace) 'k_fs_LR.surf.gii ' NativeDir '/' UsedSubjectID '.' HemiSphere '.pial.' num2str(TargetSpace) 'k_fs_LR.surf.gii'];

            %converting
            disp(['Downsampling to ' num2str(TargetSpace) 'k space...']);
            assert(~system(wb_command,'-echo'));

%             wb_command = ['nice +19 wb_command -metric-resample ' strip_extension(CurrentRegionFileName) '.func.gii ' NativeDir '/' UsedSubjectID '.' HemiSphere '.sphere.reg.reg_LR.native.surf.gii ' NativeDir '/../fsaverage_LR' num2str(TargetSpace) 'k/' UsedSubjectID '.' HemiSphere '.sphere.' num2str(TargetSpace) 'k_fs_LR.surf.gii ' ...
%                           'ADAP_BARY_AREA ' strip_extension(CurrentRegionFileName) '.' HemiSphere '.' num2str(TargetSpace) 'k.func.gii -area-surfs ' NativeDir '/' UsedSubjectID '.' HemiSphere '.midthickness.native.surf.gii ' NativeDir '/../fsaverage_LR' num2str(TargetSpace) 'k/' UsedSubjectID '.' HemiSphere '.midthickness.' num2str(TargetSpace) 'k_fs_LR.surf.gii -current-roi ' NativeDir '/' UsedSubjectID '.' HemiSphere '.roi.native.shape.gii'];

%            assert(~system(wb_command,'-echo'));
        else
            if(strcmp(HemiSphere,'L'))
                HemiSphereList = vertcat(HemiSphereList, 0);
            else
                HemiSphereList = vertcat(HemiSphereList, 1);
            end
            
            CurrentRegionFileName = CurrentRegion;
        end
        
        CurrentRegionFileName = [strip_extension(CurrentRegionFileName) '.' HemiSphere '.' num2str(TargetSpace) 'k_fs_LR.func.gii'];
        
        wb_command = ['wb_command -metric-remove-islands ' NativeDir '/' UsedSubjectID '.' HemiSphere '.sphere.' num2str(TargetSpace) 'k_fs_LR.surf.gii ' CurrentRegionFileName ' ' CurrentRegionFileName];
        assert(~system(wb_command,'-echo'));

        %Assign the surface region vertices to a region number. The number
        %will be based upon the index of the region label in the region
        %list.
        gifti_region = gifti(CurrentRegionFileName);
        
        for j = 1:length(gifti_region.cdata)
            if(gifti_region.cdata(j,1) > 0)
                gifti_region.cdata(j,1) = i;
            else
                gifti_region.cdata(j,1) = 0;
            end
        end
        
        %Cluster each individual region into a single gifti region file
        if(ClusterSurfaceRegions > 0)
            delete(CurrentRegionFileName);
            
            if(HemiSphere == 'L')
                LeftVertexData = horzcat(LeftVertexData, gifti_region.cdata); %left
            else
                RightVertexData = horzcat(RightVertexData, gifti_region.cdata); %right
            end
        else
            %or save each individual region
            save_gii(CurrentRegionFileName, TargetSpace, gifti_region);
        end
        
        if(~KeepIntermediateFiles && ~IsSurface)
            disp('Removing intermediate files');
            delete(NiftiFilename, ...
                   [ strip_extension(NiftiFilename) '_r*.4dfp.*'], ...
                   [ strip_extension(NiftiFilename) '.nii'], ...
                   [ strip_extension(NiftiFilename) '.func.gii']);
        end
    end
    
    disp('HemiSphere by region index:');
    
    for i = 1:length(HemiSphereList)
        disp(sprintf('%i. %i', i, HemiSphereList(i)));
    end
    
    LeftHemiSphereShape = [NativeDir '/' UsedSubjectID '.L.atlasroi.' num2str(TargetSpace) 'k_fs_LR.shape.gii'];
    RightHemiSphereShape = [NativeDir '/' UsedSubjectID '.R.atlasroi.' num2str(TargetSpace) 'k_fs_LR.shape.gii'];
    
    %cluster the regions together by hemisphere. This will also mask all
    %the regions by each other so only unique vertices will remain. 
    OutputTrailer = '';
    
    switch(ClusterSurfaceRegions)
        case 1
            disp('Clustering regions and excluding all overlapping vertices.');
            if(exist('LeftVertexData','var') && ~isempty(LeftVertexData))
                LeftHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
            else
                LeftHemiSphere(1:length(RightVertexData(:,1)),1) = 0;
                LeftVertexData(1:length(LeftHemiSphere(:,1)),1) = 0;
            end
            
            if(exist('RightVertexData','var') && ~isempty(RightVertexData))
                RightHemiSphere(1:length(RightVertexData(:,1)),1) = 0;
            else
                RightHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
                RightVertexData(1:length(RightHemiSphere(:,1)),1) = 0;
            end
            
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
            
            
            OutputTrailer = '.mpr_surf_cluster_exld';
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
            
            OutputTrailer = '.mpr_surf_cluster_fcfs';
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
            
            OutputTrailer = '.mpr_surf_cluster_lcfs';
            %%=================================================================
        case 4
            disp('Clustering regions using center of mass');
            
            if(isempty(LeftVertexData))
                %initialize to the other hemisphere length if no data is on this side
                LeftHemiSphere(1:length(RightVertexData(:,1)),1) = 0;   
                LeftVertexData = LeftHemiSphere;
            else
                LeftHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
            end
            
            if(isempty(RightVertexData))
                RightHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
                RightVertexData = RightHemiSphere;
            else
                RightHemiSphere(1:length(RightVertexData(:,1)),1) = 0;
            end
            
            %load the vertex to volume mappings
            LeftHemiSphereVertices = gifti([StudyPath '/' UsedSubjectID '/atlas/fsaverage_LR' num2str(TargetSpace) 'k/' UsedSubjectID '.L.midthickness.' num2str(TargetSpace) 'k_fs_LR.surf.gii']);
            LeftHemiSphereTriplets = LeftHemiSphereVertices.faces;
            LeftHemiSphereVertices = LeftHemiSphereVertices.vertices;
            
            RightHemiSphereVertices = gifti([StudyPath '/' UsedSubjectID '/atlas/fsaverage_LR' num2str(TargetSpace) 'k/' UsedSubjectID '.R.midthickness.' num2str(TargetSpace) 'k_fs_LR.surf.gii']);
            RightHemiSphereTriplets = RightHemiSphereVertices.faces;
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
                        
            [ LeftHemiSphere LeftVertexData] = AssignSurfaceVertices_CenterOfMass( LeftHemiSphereTriplets, LeftVertexData, LeftHemiSphereRegions, LeftHemiSphereVertices );
            disp(max(LeftHemiSphere));
            
%             for j = 1:length(LeftVertexData(1,:))
%                 save_gifti10k([UsedSubjectID '_lh_region_' num2str(max(LeftVertexData(:,j))) '_mpr_surf_cluster_com'], LeftVertexData(:,j), []);
%             end
            
            [ RightHemiSphere RightVertexData] = AssignSurfaceVertices_CenterOfMass( RightHemiSphereTriplets, RightVertexData, RightHemiSphereRegions, RightHemiSphereVertices );
            disp(max(RightHemiSphere));

%             for j = 1:length(RightVertexData(1,:))
%                 save_gifti10k([UsedSubjectID '_rh_region_' num2str(max(RightVertexData(:,j))) '_mpr_surf_cluster_com'], [], RightVertexData(:,j));
%             end
            
            OutputTrailer = '.cluster_com';
            %%=================================================================
        case 5  
            %find all the places the volume regions intersect with the
            %surface.
            %compute the center of those intersections
            %find all verticies within SurfaceDiameter of the center
            %write the circle to a file.
            SurfaceRadius = ClusterArg;
                        
            %load the inflated vertex mappings
            LeftHemiSphereInflatedVertices = gifti([ NativeDir '/' UsedSubjectID '.L.sphere.' num2str(TargetSpace) 'k_fs_LR.surf.gii']);
            LeftHemiSphereInflatedVertices = LeftHemiSphereInflatedVertices.vertices;
            
            RightHemiSphereInflatedVertices = gifti([ NativeDir '/' UsedSubjectID '.R.sphere.' num2str(TargetSpace) 'k_fs_LR.surf.gii']);
            RightHemiSphereInflatedVertices = RightHemiSphereInflatedVertices.vertices;
            
            if(isempty(LeftVertexData))
                %initialize to the other hemisphere length if no data is on this side
                LeftHemiSphere(1:length(RightVertexData(:,1)),1) = 0;   
                LeftVertexData = LeftHemiSphere;
            else
                LeftHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
            end
            
            if(isempty(RightVertexData))
                RightHemiSphere(1:length(LeftVertexData(:,1)),1) = 0;
                RightVertexData = RightHemiSphere;
            else
                RightHemiSphere(1:length(RightVertexData(:,1)),1) = 0;
            end
            
            %We have the center of mass for each region, now need to assign
            %vertices to the region.
            [ LeftHemiSphere] = AssignSurfaceVertices_CenterOfSurface( LeftVertexData, LeftHemiSphereInflatedVertices, SurfaceRadius );
            disp(max(LeftHemiSphere));

%             for j = 1:length(LeftVertexData(1,:))
%                 save_gifti10k([UsedSubjectID '_lh_region_' num2str(max(LeftVertexData(:,j))) '_mpr_surf_cluster_com'], LeftVertexData(:,j), []);
%             end

            [ RightHemiSphere] = AssignSurfaceVertices_CenterOfSurface( RightVertexData, RightHemiSphereInflatedVertices, SurfaceRadius );
            disp(max(RightHemiSphere));

%             for j = 1:length(RightVertexData(1,:))
%                 save_gifti10k([UsedSubjectID '_rh_region_' num2str(max(RightVertexData(:,j))) '_mpr_surf_cluster_com'], [], RightVertexData(:,j));
%             end

            OutputTrailer = '.cluster_cos';
            %%=================================================================
    end
    
    if(exist('LeftHemiSphere') && exist('RightHemiSphere') )
        %save the gifti metrics
        save_gii([UsedSubjectID OutputTrailer], TargetSpace, LeftHemiSphere, RightHemiSphere);

            %% In order to make a .label.gii set:
        %       create the normal gifti hemi's
        %       create a label/rgb lookup file
        %       wb_command -metric-label-import GLParcels_324_reordered.L.10k.func.gii ParcelLabels_reordered.txt <output>.L.label.gii -drop-unused-labels
        %       profit


        %create the label region name rgb encoding text file
        File = fopen([UsedSubjectID OutputTrailer '.txt'],'w+');

        %Visual1 
        %1 0 0 153 255
        
        BaseChannels = 40;  %min rgb for colors across all channels
        Channels = [BaseChannels 0 0];
        
        StepsPerChannel = ceil((254*3)/length(RegionFileList))

        CurrentChannel = 2;

        for i = 1:length(RegionFileList)
            fwrite(File,sprintf('%s\n%i\t%i\t%i\t%i\t%i\n', RegionFileList{i}, i, Channels(1), Channels(2), Channels(3), 255));

            Channels(CurrentChannel) = Channels(CurrentChannel) + StepsPerChannel;
            
            if(Channels(CurrentChannel) >= 254)
                Channels(CurrentChannel) = 0;
                
                if(CurrentChannel < 3)
                    CurrentChannel = CurrentChannel + 1;
                end
                
                Channels(CurrentChannel) = BaseChannels;
            end
        end

        fclose(File);

        system(['wb_command -metric-label-import ' UsedSubjectID OutputTrailer '.L.' num2str(TargetSpace) 'k.func.gii ' UsedSubjectID OutputTrailer '.txt ' UsedSubjectID OutputTrailer '.L.' num2str(TargetSpace) 'k.label.gii'],'-echo');
        system(['wb_command -metric-label-import ' UsedSubjectID OutputTrailer '.R.' num2str(TargetSpace) 'k.func.gii ' UsedSubjectID OutputTrailer '.txt ' UsedSubjectID OutputTrailer '.R.' num2str(TargetSpace) 'k.label.gii'],'-echo');
    end
    
    success = true;
    disp(success);
end
    
