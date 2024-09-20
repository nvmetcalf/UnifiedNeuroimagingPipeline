function [ DataAboveDiag ] = ExtractDataAboveDiagonal( Matrix )
%Extracts the data above the diagonal of a matrix and returns the results
%as a vector

    Length = length(Matrix(:,1));

    %make our answer vector
    DataAboveDiag= [];
    
    for i = 1:Length
        start = length(DataAboveDiag) + 1;
        row_vector = Matrix(i,i+1:Length);
        stop = start + length(row_vector) - 1;
        DataAboveDiag(start:stop) = row_vector;
    end
end

