function Output = masks_overlap( mask1, mask2 )
%mask_overlap checks the two 4dfp images to see if they overlap
%   returns true if they do, false otherwise, and -1 on error
Output = true;

    if(length(mask1.voxel_data) ~= length(mask2.voxel_data))
        disp('Masks have different number of voxels.');
        return;
    end
    
    %find the defined indicies
    Mask1_Defined_Voxels = find(mask1.voxel_data > 0);
    Mask2_Defined_Voxels = find(mask2.voxel_data > 0);
    
    %bubble search mask1 against mask2
    for i = 1:length(Mask1_Defined_Voxels)
        Index = round(length(Mask2_Defined_Voxels) / 2) - 1;
        
        Floor = 1;
        Ceiling = length(Mask2_Defined_Voxels);
        
        while(Floor ~= Index)
            if(Mask1_Defined_Voxels(i) == Mask2_Defined_Voxels(Index))
                disp(sprintf('Voxel %i and %i overlap!', Mask1_Defined_Voxels(i), Mask2_Defined_Voxels(Index)));
                return;
            else
                if(Mask1_Defined_Voxels(i) < Mask2_Defined_Voxels(Index))
                    Ceiling = Index;
                else
                    Floor = Index;
                end
                Index = round(Floor + (Ceiling - Floor) / 2) - 1;
            end
        end
    end
    
%     for i = 1:length(mask1.voxel_data)
%         if(mask1.voxel_data == mask2.voxel_data)
%             return;
%         end
%     end

    Output = false;
    
    return;
end

