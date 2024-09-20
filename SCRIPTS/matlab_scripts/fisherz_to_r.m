function [ r ] = fisherz_to_r( Matrix )
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here

r(length(Matrix(:,1)),length(Matrix(1,:))) = NaN;
    
    for i = 1:length(Matrix(:,1))
        for j = 1:length(Matrix(1,:))
            if(~isnan(Matrix(i,j)) && ~isinf(Matrix(i,j)) && Matrix(i,j) ~= 0 )
                r(i,j) = (exp(2 * Matrix(i,j)) - 1)/(exp(2*Matrix(i,j)) + 1);
            else
                r(i,j) = NaN;
            end
        end
    end 
end

