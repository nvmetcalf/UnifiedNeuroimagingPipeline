function [ z ] = p_to_z( p )
%p_to_z( p ) Convert a p value to a z score
    z = -sqrt(2) * erfcinv(p*2);
end

