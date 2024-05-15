clear all;

BrainImage = 'FCS_084_A_brain.4dfp.img'
WMImage = 'FCS_084_A_wm.4dfp.img'
OutputName = 'FCS_084_A_brain_wm_csf_trimmed_masked.4dfp.img';

X_width = 10;   %distance in voxels +/- the center vertical slice to use as "V1"

%read in the segmented white matter and skull stripped brain image
Brain = read_4dfp_img(BrainImage,'uint8');
WM = read_4dfp_img(WMImage,'uint8');

%make the WM and CSF masks
WM_mask = make_4dfp_mask(1, WM, true);
CSF_mask = make_4dfp_mask2(70, Brain, true);

%apply the masks
Brain_masked = apply_4dfp_mask(WM_mask, Brain);
Brain_masked = apply_4dfp_mask(CSF_mask, Brain_masked);

%determine the width of the brain to figure out the "center" vertical slice
%change the voxel vector to a 3d volume
Brain_masked.voxel_data = reshape(Brain_masked.voxel_data, 256, 256, 256);
Brain.voxel_data = reshape(Brain.voxel_data, 256, 256, 256);

test = Brain.voxel_data(88, :, 124);

X_min = 1;
while(X_min <= 256 && Brain.voxel_data(88, X_min, 124) == 0)
    X_min = X_min + 1;
end

X_max = 255;
while(X_max > 0 && Brain.voxel_data(88, X_max, 124) == 0)
    X_max = X_max - 1;
end

%X_center = round((X_max + X_min)/2);

X_center = 128;

X_range = [1:(X_center-X_width) (X_center+X_width):256];

for x = X_range
    for y = 1:256
        for z = 1:256
            Brain_masked.voxel_data(x,y,z) = 0;
        end
    end
end

%change the 3d volume back to avector
Brain_masked.ifh_info = Brain.ifh_info;
Brain_masked.voxel_data = reshape(Brain_masked.voxel_data, [], 1);

write_4dfp_img(Brain_masked, OutputName);