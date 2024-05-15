% ReferenceImageFilename = '/home/metcalfn/Repo/Repository/ATLAS/MNI152_T1_1mm_t88/MNI152_T1_1mm_t88.nii'
% ReferenceImageMaskFilename = '/home/metcalfn/Repo/Repository/ATLAS/MNI152_T1_1mm_t88/MNI152_T1_1mm_t88_brain_mask.nii.gz'
% 
% InputImageFilename = '/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls/FCS_040_AMC/Anatomical/Volume/T1/FCS_040_AMC_T1T_111_fnirt.nii.gz'
% InputImageMaskFilename = '/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls/FCS_040_AMC/Masks/FCS_040_AMC_used_voxels_fnirt.nii.gz'
% 
% OutputFile = '/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls/FCS_040_AMC/QC/T1T_111_fnirt_to_MNI152_T1_1mm_t88';

function PercentOverlap = ComputeMaskOverlap(Mask1, Mask2, OutputFile)
    if(~strcmp(GetExtension(Mask1),'gz') && ~strcmp(GetExtension(Mask1),'nii')) 
        error('mask1 image is not nii or nii.gz');
    end

    if(~strcmp(GetExtension(Mask2),'gz') && ~strcmp(GetExtension(Mask2),'nii')) 
        error('mask2 image is not nii or nii.gz');
    end

    %read in the images
    Mask1_image = load_nifti(Mask1);
    Mask2_image = load_nifti(Mask2);

    %reshape the 3d matrices into vectors, binarize the masks and mask them by
    %each other

    Mask1_image_Vector = reshape(logical(Mask1_image.vol), 1,[]);
    Mask2_image_Vector = reshape(logical(Mask2_image.vol),1,[]);
    
    if(length(Mask1_image_Vector) ~= length(Mask2_image_Vector))
        error('different number of values between reference and input image.');
    end

    Mask1_Voxel_Count = sum(Mask1_image_Vector);
    Mask2_Voxel_Count = sum(Mask2_image_Vector(Mask1_image_Vector > 0));
    
    PercentOverlap = (Mask2_Voxel_Count/Mask1_Voxel_Count) * 100;

    if(exist('OutputFile') && ~isempty(OutputFile))
        File = fopen(OutputFile,'w');
        fwrite(File,num2str(PercentOverlap));
        fclose(File);
    end

end
