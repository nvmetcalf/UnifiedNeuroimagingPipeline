%function plot_4dfp(Filename, BaseImage, view_orientation, Limits, Zoom, slices_per_row, number_of_rows)
clear all
    %load the 4dfp
    %create figure with as many subplots as there are dimensions in the desired
    %view orientation
    %plot the slices in the orientation direction

    view_orientation = 2

    Limits = [4 10];

    Zoom = 1.5;
    slices_per_row = [];
    number_of_rows = [];
    

    Filename = 'CORBETTA_SNR_4_32CH_PRODUCT_faln_dbnd_xr3d_uwrp_atl_uout_resid_bpss_tcorr_ds_r_to_t_5.4dfp.img'
    BaseImage = '../../atlas/CORBETTA_SNR_4_32CH_PRODUCT_func_vols_ave.4dfp.img';

    Base = read_4dfp_img(BaseImage);

    %t_voxels = r_to_t_4dfp(Filename,[strip_extension(strip_extension(Filename)) '_r_to_t.4dfp.img'], 123, 2, true)
    t_voxels = read_4dfp_img(Filename);
    voxels = t_voxels;

    %voxels.voxel_data = voxels.voxel_data(:,1);

    if(voxels.ifh_info.matrix_size(1) ~= Base.ifh_info.matrix_size(1) ...
    || voxels.ifh_info.matrix_size(2) ~= Base.ifh_info.matrix_size(2) ...
    || voxels.ifh_info.matrix_size(3) ~= Base.ifh_info.matrix_size(3))
        error('Base image and overlay image have different dimension.');
    end

    voxel_volume = reshape(voxels.voxel_data, voxels.ifh_info.matrix_size(1), voxels.ifh_info.matrix_size(2), voxels.ifh_info.matrix_size(3));

    base_volume = reshape(Base.voxel_data, Base.ifh_info.matrix_size(1), Base.ifh_info.matrix_size(2), Base.ifh_info.matrix_size(3));


    if(isempty(slices_per_row))
        slices_per_row = ceil(sqrt(voxels.ifh_info.matrix_size(view_orientation)));
    end

    if(isempty(number_of_rows))
        number_of_rows = voxels.ifh_info.matrix_size(view_orientation)/slices_per_row;
    end

    if(isempty(Limits))
        Limits = [0.000000001 max(voxels.voxel_data)];
    end

    slice_figure = figure;

    hold on;
    colormap jet
    colorbar('EastOutside');

    hold on;

    Slice = 1;

    CM_under = gray(4096);
    CM_over  = jet(4096);

    for row = 1:number_of_rows
        for column = 1:slices_per_row
            a = subplot(number_of_rows, slices_per_row, Slice);
            %disp(get(a,'position'));
    %         CellDimensions = get(a,'position');
    %         CellDimensions(1) = CellDimensions(1) - 0.2; 
    %         CellDimensions(2) = CellDimensions(2) + 0.05; 
    %         CellDimensions(3) = CellDimensions(3) + 0.1; 
    %         CellDimensions(4) = CellDimensions(4) + 0.1; 

            %CellDimensions(3:4) = CellDimensions(3:4) * Zoom;
    %        set(a,'position', CellDimensions);

            switch(view_orientation)
                case 1
                    Dimension1 = 2;
                    Dimension2 = 3;
                    UnderlaySlice = reshape(base_volume(Slice,:,:),[Base.ifh_info.matrix_size(Dimension1) Base.ifh_info.matrix_size(Dimension2)]);
                    OverlaySlice = reshape(voxel_volume(Slice,:,:),[voxels.ifh_info.matrix_size(Dimension1) voxels.ifh_info.matrix_size(Dimension2)]);

                case 2
                    Dimension1 = 1;
                    Dimension2 = 3;
                    UnderlaySlice = reshape(base_volume(:,Slice,:),[Base.ifh_info.matrix_size(Dimension1) Base.ifh_info.matrix_size(Dimension2)]);
                    OverlaySlice = reshape(voxel_volume(:,Slice,:),[voxels.ifh_info.matrix_size(Dimension1) voxels.ifh_info.matrix_size(Dimension2)]);

                    UnderlaySlice = rot90(UnderlaySlice,1);
                    OverlaySlice = rot90(OverlaySlice,1);

                case 3
                    Dimension1 = 1;
                    Dimension2 = 2;
                    UnderlaySlice = reshape(base_volume(:,:,Slice),[Base.ifh_info.matrix_size(Dimension1) Base.ifh_info.matrix_size(Dimension2)]);
                    OverlaySlice = reshape(voxel_volume(:,:,Slice),[voxels.ifh_info.matrix_size(Dimension1) voxels.ifh_info.matrix_size(Dimension2)]);

            end


            %convert the underlay slice and overlay slice to RGB maps
            U_RGB = convert_to_RGB(UnderlaySlice, CM_under);
            O_RGB = convert_to_RGB(OverlaySlice, CM_over);

            Slice_RGB = [];

            %go through the overlay and voxels that are thresheld out, replace
            %with the underlay
            for i = 1:length(UnderlaySlice(:,1))
                for j = 1:length(UnderlaySlice(1,:))
                    if(abs(OverlaySlice(i,j)) >= Limits(1))
                        Slice_RGB(i,j,:) = O_RGB(i,j,:);
                    else
                        Slice_RGB(i,j,:) = U_RGB(i,j,:);
                    end
                end
            end

            image(Slice_RGB);
            hold on;

            axis off;
            Slice = Slice + 1;
        end 
    end

%end