function [Seeds] = volume_mean_region(NiftiIn, Parcellation_Filename, brainmask_filename)

    volume = load_nifti(NiftiIn);
    volume = reshape(volume.vol, volume.dim(2) * volume.dim(3) * volume.dim(4), volume.dim(5))';
    Parcellation = load_nifti(Parcellation_Filename);
    
    Parcellation = reshape(Parcellation.vol, Parcellation.dim(2) * Parcellation.dim(3) * Parcellation.dim(4), 1)';
        
    RegionID_List = unique(Parcellation);
    
    brainmask = load_nifti(brainmask_filename);
    brainmask = logical(reshape(brainmask.vol, brainmask.dim(2) * brainmask.dim(3) * brainmask.dim(4), 1)');
    
    if(length(brainmask) ~= length(Parcellation))
        error('brainmask and parcellation have different dimensions');
    end
    %exclude 0 and NaN values
    RegionID_List = RegionID_List(RegionID_List > 0);
    
    volume = volume(:,brainmask > 0);
    Parcellation = Parcellation(brainmask > 0);
    
    Filtered_RegionID_List = unique(Parcellation);
    Filtered_RegionID_List(Filtered_RegionID_List == 0) = [];
    
    if(length(RegionID_List) ~= length(Filtered_RegionID_List))
        disp('Number of regions before and after brain masking changes.');
    end
    
    Seeds = [];
    for i = 1:length(RegionID_List)
        %disp(RegionID_List(i));
        Region_mean = nanmean(volume(Parcellation == RegionID_List(i)));
       
        try
            Seeds = horzcat(Seeds, Region_mean);
        catch 
            disp(RegionID_List(i));
            disp('no data in roi');
            Seeds = horzcat(Seeds, nan(length(tmask),1));
        end
        
    end

end