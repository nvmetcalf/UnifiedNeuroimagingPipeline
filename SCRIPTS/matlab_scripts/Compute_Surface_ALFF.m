function Compute_Surface_ALFF(Cifti_In, LowFreq, HighFreq, TR)
    dtseries = ft_read_cifti_mod(Cifti_In);
    
    dtseries_out = dtseries;
    dtseries_out.data = zeros(length(dtseries.data(:,1)),1);
    
    Result = dtseries_out.data;
    parfor i=1:length(dtseries_out.data(:,1))
        [P,F]=pwelch(dtseries.data(i,:),50,[],256,1);
        power = P(F >= LowFreq & F <= HighFreq);
        power_sqrt = sqrt(power);
        power_sqrt_mean = mean(power_sqrt);
        Result(i) = power_sqrt_mean;
    end
    dtseries_out.data = Result;
    ft_write_cifti_mod([strip_extension(strip_extension(strip_extension(Cifti_In))) '_alff.ctx.nii'],dtseries_out);
    
    dtseries_out.data = Result./mean(Result);
    ft_write_cifti_mod([strip_extension(strip_extension(strip_extension(Cifti_In))) '_alff_standard.ctx.nii'],dtseries_out)
end