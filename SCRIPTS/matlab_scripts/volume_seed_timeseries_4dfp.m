function [Seed_Timeseries_4dfp] = volume_seed_timeseries(BOLD_TimeSeries_4dfpFilename, Parcellation_Filename)

    BOLD_TimeSeries_volume = read_4dfp_img(BOLD_TimeSeries_4dfpFilename);
    BOLD_TimeSeries_volume = BOLD_TimeSeries_volume.voxel_data;
    
    Parcellation = read_4dfp_img(Parcellation_Filename);
    
    Parcellation = Parcellation.voxel_data;
    
    RegionID_List = unique(Parcellation);
        
    %exclude 0 and NaN values
    RegionID_List = RegionID_List(RegionID_List > 0);
    
    Seed_Timeseries_4dfp = [];
    for i = 1:length(RegionID_List)
        disp(RegionID_List(i));
        try
            Region_Timeseries = mean(BOLD_TimeSeries_volume(find(Parcellation == RegionID_List(i)),:))';
            Seed_Timeseries_4dfp = horzcat(Seed_Timeseries_4dfp, Region_Timeseries);
        catch 
            disp('no data in roi');
            Seed_Timeseries_4dfp = horzcat(Seed_Timeseries_4dfp, nan(length(BOLD_TimeSeries_volume(:,1)),1));
        end
        
    end
end