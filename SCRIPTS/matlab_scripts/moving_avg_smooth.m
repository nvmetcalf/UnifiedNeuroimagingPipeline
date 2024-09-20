function [ SmoothedTimeSeries ] = moving_avg_smooth( TimeSeries, Width)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

    if(~mod(Width,2))
        error('Width must be an odd number');
    end
    
    SmoothedTimeSeries = zeros(1,length(TimeSeries));
    
    for i = 1:length(TimeSeries)
       Bins = i-floor(Width/2):i+floor(Width/2);
       UsableBins = Bins(Bins > 0 & Bins <= length(TimeSeries));
       
       SmoothedTimeSeries(i) = mean(TimeSeries(UsableBins));
    end
    
end

