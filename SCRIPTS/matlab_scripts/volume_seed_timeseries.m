function [Seed_Timeseries RegionID_List] = volume_seed_timeseries(BOLD_TimeSeries_NiftiFilename, Parcellation_Filename, RegionIDs)

    BOLD_TimeSeries_volume = load_nifti(BOLD_TimeSeries_NiftiFilename);
    BOLD_TimeSeries_volume = reshape(BOLD_TimeSeries_volume.vol, BOLD_TimeSeries_volume.dim(2) * BOLD_TimeSeries_volume.dim(3) * BOLD_TimeSeries_volume.dim(4), BOLD_TimeSeries_volume.dim(5));
    Parcellation = load_nifti(Parcellation_Filename);
    
    Parcellation = reshape(Parcellation.vol, Parcellation.dim(2) * Parcellation.dim(3) * Parcellation.dim(4), 1)';
    
    if(exist('RegionIDs'))
        RegionID_List = RegionIDs;
    else
        RegionID_List = unique(Parcellation);
    end
    
    %exclude 0 and NaN values
    RegionID_List = RegionID_List(RegionID_List > 0);

    Seed_Timeseries = [];
    for i = 1:length(RegionID_List)
        disp(RegionID_List(i));
        try
            Region_Timeseries = mean(BOLD_TimeSeries_volume(find(Parcellation == RegionID_List(i)),:))';
            Seed_Timeseries = horzcat(Seed_Timeseries, Region_Timeseries);
        catch 
            disp('no data in roi');
            Seed_Timeseries = horzcat(Seed_Timeseries, zeros(length(BOLD_TimeSeries_volume(1,:)),1));
        end
        
    end
end