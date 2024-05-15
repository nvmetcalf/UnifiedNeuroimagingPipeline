
%load parcellation
%compute the average coordinate across voxels of each mask.
%compute coordinate relative to the center
%output center of the mask

Parcellation = '/data/nil-bluearc/corbetta/Pipeline/SCRIPTS/Parcellation/GLParcels/reordered/MNI/GLParcels_324_reordered_w_SubCortical_volume_MNI152.nii.gz'

AllCentroidWorldCoordinates = [];
AllCentroidAtlasCoordinates = [];

ParcellationVolume = load_nifti(Parcellation);

RegionIDs = unique(ParcellationVolume.vol);
RegionIDs(RegionIDs == 0) = []; %get rid of the undefined voxel ID

ImageDims = size(ParcellationVolume.vol);

for i = 1:length(RegionIDs)

    CurrRegion = RegionIDs(i);
    DefinedVoxelCoords = [];
    %get the world coordinate of each voxel that is defined.
    for x = 1:ImageDims(1)
        for y = 1:ImageDims(2)
            for z = 1:ImageDims(3)
                if(ParcellationVolume.vol(x,y,z) == CurrRegion)
                   DefinedVoxelCoords = vertcat(DefinedVoxelCoords, [x y z]); 
                end
            end
        end
    end
    
    AllCentroidWorldCoordinates = vertcat(AllCentroidWorldCoordinates, [mean(DefinedVoxelCoords)]);
    AllCentroidAtlasCoordinates = vertcat(AllCentroidAtlasCoordinates, [mean(DefinedVoxelCoords)] + [ParcellationVolume.quatern_x ParcellationVolume.quatern_y ParcellationVolume.quatern_z]);

end

disp('RegionID world_x world_y world_z atlas_x atlas_y atlas_z');

for i = 1:length(AllCentroidWorldCoordinates(:,1))
    
    disp([num2str(RegionIDs(i)) ' ' num2str(AllCentroidWorldCoordinates(i,:)) ' ' num2str(AllCentroidAtlasCoordinates(i,:))]);
    %disp(['World Centroid Coord: ' num2str(WorldCentroidCoord)]);
    %disp(['Atlas Centroid Coord: ' num2str(AtlasCentroidCoord)]);
    
end