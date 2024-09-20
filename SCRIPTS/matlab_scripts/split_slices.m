function split_slices(Input_4dfp_ROI, AllSlices)

    %writes all slices that are defined, unless AllSlices is set

    if(~exist('AllSlices'))
        AllSlices = false
    end
    ROI_4dfp = read_4dfp_img(Input_4dfp_ROI);
    
    ROI_4dfp_volume = reshape(ROI_4dfp.voxel_data, ROI_4dfp.ifh_info.matrix_size(1), ROI_4dfp.ifh_info.matrix_size(2), ROI_4dfp.ifh_info.matrix_size(3));

    output_4dfp = ROI_4dfp;
    
    for slice = 1:ROI_4dfp.ifh_info.matrix_size(3)
        Slice_volume = zeros(ROI_4dfp.ifh_info.matrix_size(1), ROI_4dfp.ifh_info.matrix_size(2), ROI_4dfp.ifh_info.matrix_size(3));
        
        Slice_volume(:,:,slice) = ROI_4dfp_volume(:,:,slice);
        
        output_4dfp.voxel_data = reshape(Slice_volume,1,[]);
        
        
        if(count(find(Slice_volume ~= 0)) > 0 || AllSlices)  
            write_4dfp_img(output_4dfp,[strip_extension(strip_extension(Input_4dfp_ROI)) '_slice_' num2str(slice) '.4dfp.img']);
        end
    end
end