function [ Success ] = WriteMatrix( File, Matrix )
%UNTITLED2 Summary of this function goes here
%   Converts a matrix of any size to a string with line feeds and writes it
%   to a fileID

    Type = [];
    
    if(isinteger(Matrix(1,1)))
        Type = 1;
    else
        Type = 2;
    end
    
    for i = 1:length(Matrix(1,:))
        Buffer = sprintf('%i', i);

        %gives a standardized cell width of 6 characters
        while length(Buffer) < 7
            Buffer = sprintf(' %s',Buffer);
        end
        fwrite(File, Buffer);        
    end

    
    %copy the matrix we want to the output matrix with the labeling
    for i = 1:length(Matrix(:,1))
        
        Buffer = sprintf('\n%i', i);

        while length(Buffer) < 3
           Buffer = sprintf('%s ',Buffer);
        end

        fwrite(File, Buffer);
        
        for j = 1:length(Matrix(1,:))
            if Matrix(i,j) < 0
                if(isinteger(Matrix(i,j)))
                    Buffer = sprintf('  %i  ', Matrix(i,j));
                else
                    Buffer = sprintf(' %1.3f', Matrix(i,j));
                end
            else
                if(isinteger(Matrix(i,j)))
                    Buffer = sprintf('   %i   ', Matrix(i,j));
                else
                    Buffer = sprintf('  %1.3f', Matrix(i,j));
                end
            end
            
            fwrite(File, Buffer);
        end
    end
end

