%load parcellation volume
%load the source volume
%return mean, sd, and median of each parcel

function [MeanVector SDVector MedianVector ParcelIDs] = extract_volume_parcel_values(SourceVolumeFilename, ParcellationFilename, MinValueClamp, MaxValueClamp)
    MeanVector = [];
    SDVector = [];
    MedianVector = [];
    
    %load the volumes
    ParcellationVolume = load_nifti(ParcellationFilename);
    SourceVolume = load_nifti(SourceVolumeFilename);
    
    %test dimensions
    ParcellationSize = size(ParcellationVolume.vol);
    SourceSize = size(SourceVolume.vol);
    
    if(ParcellationSize(1) ~= SourceSize(1) ...
    || ParcellationSize(2) ~= SourceSize(2) ...
    || ParcellationSize(3) ~= SourceSize(3))
        error('Source Volume and Parcellation volume have different dimensions.');
    end
    
    ParcellationVolume = reshape(ParcellationVolume.vol,1,[]);
    SourceVolume = reshape(SourceVolume.vol,1,[]);
    
    if(exist('MinValueClamp'))
        SourceVolume(SourceVolume < MinValueClamp) = NaN;
    end
    
    if(exist('MaxValueClamp'))
        SourceVolume(SourceVolume > MaxValueClamp) = NaN;
    end
    ParcelIDs = unique(ParcellationVolume);
    ParcelIDs(ParcelIDs <= 0) = [];
    
    for i = 1:length(ParcelIDs)
        MeanVector = horzcat(MeanVector, nanmean(SourceVolume(ParcellationVolume == ParcelIDs(i))));
        SDVector = horzcat(SDVector, nanstd(SourceVolume(ParcellationVolume == ParcelIDs(i))));
        MedianVector = horzcat(MedianVector, nanmedian(SourceVolume(ParcellationVolume == ParcelIDs(i))));
    end
end
