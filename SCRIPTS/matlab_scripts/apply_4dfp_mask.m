function [masked_4dfp] = apply_4dfp_mask( Mask4dfp, Image4dfp)
%   Applies a mask to the Image4dfp. The voxels are removed from the
%   Image4dfp. When writing the Image4dfp to the disk, be sure to send in
%   the mask as well, so that the voxels can be reinstated into the final
%   image.

    masked_4dfp = Image4dfp;
    
    if(length(Mask4dfp.voxel_data(:,1)) ~= length(Image4dfp.voxel_data(:,1)))
        disp('The 4dfp mask cannot be applied to the 4dfp image as they have differing numbers of voxels.');
        return;
    end
    
    %go through the mask and keep the voxels from the 4dfpImage that are to
    %be kept.
    
    
    i = 1;
    j = 1;
    VoxelCount = length(Mask4dfp.voxel_data(:,1));
    masked_4dfp.voxel_data(length(find(Mask4dfp.voxel_data > 0)), length(Image4dfp.voxel_data(1,:))) = 0;
    
    %see if the user prepared the mask properly (ie binary)
    if(max(Mask4dfp.voxel_data) == 1)
        masked_4dfp.voxel_data = Mask4dfp.voxel_data .* Image4dfp.voxel_data;
    else
        while(i <= VoxelCount)
            if(Mask4dfp.voxel_data(i,1) > 0)
                masked_4dfp.voxel_data(j,:) = Image4dfp.voxel_data(i,:);
                j = j + 1;
            end   

            i = i + 1;
        end
    end
return;
end
