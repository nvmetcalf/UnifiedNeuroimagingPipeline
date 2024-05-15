% ReferenceImageFilename = '/home/metcalfn/Repo/Repository/ATLAS/MNI152_T1_1mm_t88/MNI152_T1_1mm_t88.nii'
% ReferenceImageMaskFilename = '/home/metcalfn/Repo/Repository/ATLAS/MNI152_T1_1mm_t88/MNI152_T1_1mm_t88_brain_mask.nii.gz'
% 
% InputImageFilename = '/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls/FCS_040_AMC/Anatomical/Volume/T1/FCS_040_AMC_T1T_111_fnirt.nii.gz'
% InputImageMaskFilename = '/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls/FCS_040_AMC/Masks/FCS_040_AMC_used_voxels_fnirt.nii.gz'
% 
% OutputFile = '/home/metcalfn/Repo/Repository/Projects/FCStroke_2016/Controls/FCS_040_AMC/QC/T1T_111_fnirt_to_MNI152_T1_1mm_t88';

function ETA = ComputeAnatomicalVolumeCorrelation(ReferenceImageFilename, ReferenceImageMaskFilename, InputImageFilename, InputImageMaskFilename, OutputFile)
    if(~strcmp(GetExtension(ReferenceImageFilename),'gz') && ~strcmp(GetExtension(ReferenceImageFilename),'nii')) 
        error('reference image is not nii or nii.gz');
    end

    if(~strcmp(GetExtension(ReferenceImageMaskFilename),'gz') && ~strcmp(GetExtension(ReferenceImageMaskFilename),'nii')) 
        error('reference image mask is not nii or nii.gz');
    end

    if(~strcmp(GetExtension(InputImageFilename),'gz') && ~strcmp(GetExtension(InputImageFilename),'nii')) 
        error('input image is not nii or nii.gz');
    end

    if(~strcmp(GetExtension(InputImageMaskFilename),'gz') && ~strcmp(GetExtension(InputImageMaskFilename),'nii')) 
        error('input image mask is not nii or nii.gz');
    end

    %read in the images
    ReferenceImage = load_nifti(ReferenceImageFilename);
    ReferenceImageMask = load_nifti(ReferenceImageMaskFilename);

    InputImage = load_nifti(InputImageFilename);
    InputImageMask = load_nifti(InputImageMaskFilename);

    %reshape the 3d matrices into vectors, binarize the masks and mask them by
    %each other

    ReferenceMaskVector = reshape(logical(ReferenceImageMask.vol), 1,[]);
    InputMaskVector = reshape(logical(InputImageMask.vol),1,[]);

    UnionedMask = reshape(ReferenceMaskVector .* InputMaskVector,1,[]);

    ReferenceImage = reshape(ReferenceImage.vol,1,[]);
    ReferenceImage = ReferenceImage(UnionedMask == 1);
    InputImage = reshape(InputImage.vol,1,[]);
    InputImage = InputImage(UnionedMask == 1);

    if(length(ReferenceImage) ~= length(InputImage))
        error('different number of values between reference and input image.');
    end

    ETA = corrcoef(ReferenceImage,InputImage);

    if(exist('OutputFile') && ~isempty(OutputFile))
        File = fopen(OutputFile,'w');
        fwrite(File,num2str(ETA(1,2)));
        fclose(File);
    end

end
