%read the atlas
%read the atlas mask
%read the registered image
%read the registered image mask
%mask images by their respective masks
%extract cubes from each image and remove undefined voxels
%compute correlation
%replace voxels with the correlation R
%when complete, write image to disk

function ComputeStructuralETA(AtlasTargetFilename, AtlasTargetMaskFilename, RegisteredImageFilename, RegisteredImageMaskFilename, CellDimensions)

    if(length(CellDimensions) < 3)
        CellDimensions = [CellDimensions(1) CellDimensions(1) CellDimensions(1)]
    end
% 
%     CellDimensions = [3 3 3];    %x y z dimensions of the cell that will be used to make the correlations, in voxels
% 
%     AtlasTargetFilename = '/home/metcalfn/Repo/Repository/ATLAS/MNI152_T1_1mm_t88/MNI152_T1_1mm_t88_333.4dfp.img';
%     AtlasTargetMaskFilename ='/home/metcalfn/Repo/Repository/ATLAS/MNI152_T1_1mm_t88/MNI152_T1_1mm_t88_brain_mask_333.4dfp.img';
% 
%     RegisteredImageFilename = 'AnatOnly_mpr_n1_333_t88_fnirt.4dfp.img';
%     RegisteredImageMaskFilename = 'AnatOnly_used_voxels_fnirt_333.4dfp.img';

    disp(AtlasTargetFilename);
    disp(AtlasTargetMaskFilename);
    disp(RegisteredImageFilename);
    disp(RegisteredImageMaskFilename);
    disp(CellDimensions);
    
    AtlasTargetVolume = load_nifti(AtlasTargetFilename);
    AtlasTargetMaskvolume = load_nifti(AtlasTargetMaskFilename);

    RegisteredImageVolume = load_nifti(RegisteredImageFilename);
    RegisteredImageMaskvolume = load_nifti(RegisteredImageMaskFilename);

    AtlasVolumeVector = reshape(AtlasTargetVolume.vol,1,[]);
    AtlasTargetMaskVolumeVector = logical(reshape(AtlasTargetMaskvolume.vol,1,[]));
    
    RegisteredVolumeVector = reshape(RegisteredImageVolume.vol,1,[]);
    RegisteredImageMaskVolumeVector = logical(reshape(RegisteredImageMaskvolume.vol,1,[]));
    
    AtlasVolumeMasked = reshape(AtlasVolumeVector .* AtlasTargetMaskVolumeVector, AtlasTargetVolume.dim(2),AtlasTargetVolume.dim(3),AtlasTargetVolume.dim(4));
    RegisteredImageMasked = reshape(RegisteredVolumeVector .* RegisteredImageMaskVolumeVector, AtlasTargetVolume.dim(2),AtlasTargetVolume.dim(3),AtlasTargetVolume.dim(4));

    % we don't clear the atlasvolume as we need that as a template later
    clear AtlasTargetMaskvolume RegisteredImageVolume RegisteredImageMaskvolume;

    ResultVolume(1:AtlasTargetVolume.dim(2),1:AtlasTargetVolume.dim(3),1:AtlasTargetVolume.dim(4)) = NaN;
    SamplesVolume(1:AtlasTargetVolume.dim(2),1:AtlasTargetVolume.dim(3),1:AtlasTargetVolume.dim(4)) = 0;

    UsedCells = 0;
    for i = 1:ceil(AtlasTargetVolume.dim(2)/CellDimensions(1))
        for j = 1:ceil(AtlasTargetVolume.dim(3)/CellDimensions(2))
            for k = 1:ceil(AtlasTargetVolume.dim(4)/CellDimensions(3))

                StartX = ((i-1)*CellDimensions(1))+1;
                StartY = ((j-1)*CellDimensions(2))+1;
                StartZ = ((k-1)*CellDimensions(3))+1;

                EndX = i * CellDimensions(1);
                EndY = j * CellDimensions(2);
                EndZ = k * CellDimensions(3);

                if(EndX > AtlasTargetVolume.dim(2))
                    EndX = AtlasTargetVolume.dim(2);
                end

                if(EndY > AtlasTargetVolume.dim(3))
                    EndY = AtlasTargetVolume.dim(3);
                end

                if(EndZ > AtlasTargetVolume.dim(4))
                    EndZ = AtlasTargetVolume.dim(4);
                end

                AtlasVoxels = reshape(AtlasVolumeMasked(StartX:EndX, StartY:EndY, StartZ:EndZ),1,[]);
                RegisteredVoxels = reshape(RegisteredImageMasked(StartX:EndX, StartY:EndY, StartZ:EndZ),1,[]);

                CommonDefinedVoxels = [];
                for n = 1:length(AtlasVoxels)
                    if(AtlasVoxels(n) ~= 0 && RegisteredVoxels(n) ~= 0)
                        CommonDefinedVoxels = vertcat(CommonDefinedVoxels, [AtlasVoxels(n) RegisteredVoxels(n)]);
                    end
                end

                if(length(CommonDefinedVoxels) >= 10)
                     Sim = corr(CommonDefinedVoxels);
                     UsedCells = UsedCells +1;
                else
                    %disp(['Not enough data for cell: ' num2str(i) ' ' num2str(j) ' ' num2str(k) ' # voxels: ' num2str(length(CommonDefinedVoxels))]);
                    Sim = [NaN NaN];
                end

                ResultVolume(StartX:EndX, StartY:EndY, StartZ:EndZ) = Sim(1,2);
                SamplesVolume(StartX:EndX, StartY:EndY, StartZ:EndZ) = length(CommonDefinedVoxels);
            end
        end
    end

    AtlasTargetVolume.vol = ResultVolume;
    AtlasTargetVolume.datatype = 16;

    save_nifti(AtlasTargetVolume,['StructuralETA_' strip_path(strip_extension(strip_extension(RegisteredImageFilename))) '_cd' num2str(CellDimensions(1)) 'x' num2str(CellDimensions(2)) 'x' num2str(CellDimensions(3)) '.nii.gz']);

    AtlasTargetVolume.vol = SamplesVolume;

    save_nifti(AtlasTargetVolume,['StructuralETA_' strip_path(strip_extension(strip_extension(RegisteredImageFilename))) '_cd' num2str(CellDimensions(1)) 'x' num2str(CellDimensions(2)) 'x' num2str(CellDimensions(3)) '_df.nii.gz']);

    disp(['Used Cells: ' num2str(UsedCells)]);

end