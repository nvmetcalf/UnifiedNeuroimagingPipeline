%This function uses parabolic interpolation to find the lag using the
%extremum of the lagged cross correlation.

%The function first uses the
%sign of the cross correlation at zero to decide whether to find a maximum
%or minmum. Next, we look for the global max/min.

%lcc is the empirical lagged covariance curve, lags is a vector with the TRs 
%in each temporal direction (e.g. -5:1:5), and TR is the scan TR. I have 
%set a boundary condition such that any lag greater than 7 seconds is recorded 
%as a NaN-- this is based on our experience that giant lags tend to be noise. 
%You can relax or abolish this boundary condition if you like.

function [peak_lag,peak_cov]= parabolic_interp(lcc,lags,TR)

peak_lag = [];
peak_cov = [];
index = [];
%lags = -5:1:5;
zero = find(lags==0); %Index for zero lag


%Local Maximum
%if lcc(zero) > 0
    [D I] = max(lcc);
    if I==1 || I==length(lags)
        peak_lag = (I-zero)*TR;
        peak_cov = D;
        return
    end
    index = [I-1 I I+1]; %These are the three x values to be used for parabolic interpolation
%end

% %Local Minimum
% if lcc(zero) < 0
%     [D I] = min(lcc);
%     if abs(lags(I)*TR) > 7
%         peak_lag = NaN;
%         peak_cov = NaN;
%         return
%     end
%     index = [I-1 I I+1]; %These are the three x values to be used for parabolic interpolation
% end

%Calculate the lag [x value of extremum]
%     points = lcc(index); % Y values of the three points that are being interpolated through, in seconds instead of frames
%     a1 = 0.5*(points(3)-points(1))/TR;
%     a2 = 0.5*(points(1) - 2*points(2) + points(3))/(TR^2);
%
%     peak_lag = -0.5*(a1/a2);

%Handles the straight line case
if isempty(index) == 1
    peak_lag = NaN;
    peak_cov = NaN;
end

if isempty(peak_lag) == 1
    ypoints = lcc(index);
    xpoints = lags(index);
    X = [(xpoints.^2)' xpoints' ones(3,1)]; %Matrix of x-terms
    constants = X\(ypoints)';
    peak_lag = -.5*(constants(2)/constants(1)); %From the first derivative
    peak_cov = constants(1)*peak_lag^2 + constants(2)*peak_lag + constants(3); peak_cov = abs(peak_cov);
    peak_lag = TR*peak_lag; %Get the lag in seconds
end

end