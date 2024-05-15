function [ String ] = VectorToString( Vector, divider )
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

    String = '';
    
    if(~exist('divider'))
        divider = ' ';
    end
    
    for i= 1:length(Vector)
       String = sprintf('%s%s%3.3f',String, divider, Vector(i));
    end
end

