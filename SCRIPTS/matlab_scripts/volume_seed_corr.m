function [SeedCorrMatrix Seed_Timeseries] = volume_seed_corr(BOLD_TimeSeries_NiftiFilename, Parcellation_Filename, tmask_filename)

    BOLD_TimeSeries_volume = load_nifti(BOLD_TimeSeries_NiftiFilename);
    BOLD_TimeSeries_volume = reshape(BOLD_TimeSeries_volume.vol, BOLD_TimeSeries_volume.dim(2) * BOLD_TimeSeries_volume.dim(3) * BOLD_TimeSeries_volume.dim(4), BOLD_TimeSeries_volume.dim(5))';
    Parcellation = load_nifti(Parcellation_Filename);
    
    Parcellation = reshape(Parcellation.vol, Parcellation.dim(2) * Parcellation.dim(3) * Parcellation.dim(4), 1)';
    
    tmask = importdata(tmask_filename);
    
    RegionID_List = unique(Parcellation);
    
    %exclude 0 and NaN values
    RegionID_List = RegionID_List(RegionID_List > 0);
    
    %drop timepoints that are "bad"
    BOLD_TimeSeries_volume = BOLD_TimeSeries_volume(tmask == 1,:);
    
    Filtered_RegionID_List = unique(Parcellation);
    Filtered_RegionID_List(Filtered_RegionID_List == 0) = [];
    
    if(length(RegionID_List) ~= length(Filtered_RegionID_List))
        disp('Number of regions before and after brain masking changes.');
    end
    
    Seed_Timeseries = [];
    for i = 1:length(RegionID_List)
        %disp(RegionID_List(i));
        Region_Timeseries = mean(BOLD_TimeSeries_volume(:,Parcellation == RegionID_List(i))')';
       
        try
            Seed_Timeseries = horzcat(Seed_Timeseries, Region_Timeseries);
        catch 
            disp(RegionID_List(i));
            disp('no data in roi');
            Seed_Timeseries = horzcat(Seed_Timeseries, nan(sum(tmask),1));
        end
        
    end

    SeedCorrMatrix = corr(Seed_Timeseries);
end