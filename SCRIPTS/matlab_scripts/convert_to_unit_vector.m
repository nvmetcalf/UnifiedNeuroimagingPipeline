function [ UnitVectorOut Bias] = convert_to_unit_vector( VectorIn, Bias)
%convert_to_unit_vector takes a vector and converts it to a unit vector. If
%a Bias value is supplied, it is also scaled.
if(~exist('Bias'))
    Bias = 0;
end

%compute the sum of squares for the vector
%sqrt the sum
%divide each element of the vector by the sqrt(sum) as well as the bias.

Magnitude = sqrt(sum(VectorIn.^2));

UnitVectorOut = VectorIn ./ Magnitude;

Bias = Bias / Magnitude;

end

