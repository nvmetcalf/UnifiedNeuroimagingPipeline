function Compute_Volume_ALFF(BOLD_in, Brainmask_in, LowFreq, HighFreq, TR)
    timeseries = load_nifti(BOLD_in);
    brainmask = load_nifti(Brainmask_in);
    
    timeseries.vol = reshape(timeseries.vol, timeseries.dim(2) * timeseries.dim(3) * timeseries.dim(4),timeseries.dim(5));
    brainmask.vol = reshape(brainmask.vol, 1, []);
    
    timeseries_out = timeseries;
    timeseries_out.vol = [];
    timeseries_out.vol = brainmask.vol .* 0;
     
    for i=1:length(timeseries_out.vol)
        if(brainmask.vol(i))
            [P,F]=pwelch(timeseries.vol(i,:),50,[],256,1);
            power = P(F >= LowFreq & F <= HighFreq);
            power_sqrt = sqrt(power);
            power_sqrt_mean = mean(power_sqrt);
            timeseries_out.vol(i) = power_sqrt_mean;
        end
    end
    %compute standard units for the magnitude
    timeseries_out_standard_units = timeseries_out;
    timeseries_out_standard_units.vol = timeseries_out.vol./mean(timeseries_out.vol(timeseries_out.vol ~= 0));
    
    timeseries_out.vol = reshape(timeseries_out.vol, timeseries.dim(2), timeseries.dim(3), timeseries.dim(4));
    save_nifti(timeseries_out, [strip_extension(strip_extension(strip_extension(BOLD_in))) '_alff.nii.gz']);
    
    timeseries_out_standard_units.vol = reshape(timeseries_out_standard_units.vol,timeseries_out_standard_units.dim(2), timeseries_out_standard_units.dim(3), timeseries_out_standard_units.dim(4));
    save_nifti(timeseries_out_standard_units, [strip_extension(strip_extension(strip_extension(BOLD_in))) '_alff_standard.nii.gz']);
end