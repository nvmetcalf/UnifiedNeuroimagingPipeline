function [ output_4dfp_img ] = make_4dfp_mask2( Threshold, img_4dfp, compliment )
%make_4dfp_mask changes all voxel values LESS than or equal t othe
%specified threshold to 1' and everything else to 0's. Returns as the same
%data type specified when the 4dfp was loaded.

    if(~exist('compliment'))
        compliment = false;
    end
    
    output_4dfp_img = img_4dfp;
    
    for i = 1:length(img_4dfp.voxel_data(:,1))
        if(output_4dfp_img.voxel_data(i,1) <= Threshold)
            if(compliment)
                output_4dfp_img.voxel_data(i,1) = 0;
            else
                output_4dfp_img.voxel_data(i,1) = 1;
            end
        else
            if(compliment)
                output_4dfp_img.voxel_data(i,1) = 1;
            else
                output_4dfp_img.voxel_data(i,1) = 0;
            end
        end
    end
end

