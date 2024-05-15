function [Omega] = rbv_compute_Omega(R,rr,i)
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here
    Omega = single(zeros(1,rr));
    parfor j = 1:rr
        Omega(j) = sum(R(:,i) .* R(:,j));
    end
end

