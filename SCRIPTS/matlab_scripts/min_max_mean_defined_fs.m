%returns the minimum, maximum, and mean value of a freesurfer volume image
%based on the defined voxel of a freesurfer volume.
clear all;
Path = '/scratch/SurfaceStroke'
MaskList = {'rh.V1-ventral_c1_template.mgh', 'rh.V1-ventral_c2_template.mgh', 'rh.V1-ventral_c3_template.mgh',...
            'rh.V1dorsal_c1_template.mgh', 'rh.V1dorsal_c2_template.mgh', 'rh.V1dorsal_c3_template.mgh',...
            'lh.V1-ventral_c1_template.mgh', 'lh.V1-ventral_c2_template.mgh', 'lh.V1-ventral_c3_template.mgh'...
            'lh.V1dorsal_c1_template.mgh', 'lh.V1dorsal_c2_template.mgh', 'lh.V1dorsal_c3_template.mgh'}; 

SubjectID = {'FCS_073_A', 'FCS_074_A', 'FCS_083_A_test', 'FCS_099_A', 'FCS_111_A', 'FCS_120_A', 'FCS_124_A', 'FCS_162_A', 'FCS_165_A', 'FCS_179_A'}

for j = 1:length(SubjectID)
    disp(SubjectID{j});
    disp(sprintf('Region Name\tMean Value\tMin Value\tMax Value'));

    for i = 1:length(MaskList)

        MaskImage = load_mgh([Path '/' SubjectID{j} '/label/' MaskList{i} ]);
        Value_LH_surface = load_mgh([ Path '/' SubjectID{j} '_lh_template_orig.mgh']);
        Value_RH_surface = load_mgh([ Path '/' SubjectID{j} '_rh_template_orig.mgh']);

        Value_LH_surface_a = reshape(Value_LH_surface,[],3);
        Value_RH_surface_a = reshape(Value_RH_surface,[],3);

        MaskImage_a = reshape(MaskImage,[],1);

        LH_RegionVoxels = Value_LH_surface_a(MaskImage_a > 0,2);
        LH_RegionVoxels = LH_RegionVoxels(LH_RegionVoxels ~= 0); %remove 0's

        RH_RegionVoxels = Value_RH_surface_a(MaskImage_a > 0,2);
        RH_RegionVoxels = RH_RegionVoxels(RH_RegionVoxels ~= 0); %remove 0's

        if(isnan(mean(LH_RegionVoxels)))
            Buffer = sprintf('%s\t%f\t%f\t%f', MaskList{i}, mean(RH_RegionVoxels), min(RH_RegionVoxels), max(RH_RegionVoxels));
        else
            Buffer = sprintf('%s\t%f\t%f\t%f', MaskList{i}, mean(LH_RegionVoxels), min(LH_RegionVoxels), max(LH_RegionVoxels));
        end

        disp(Buffer);
    end
    disp(' ');
end