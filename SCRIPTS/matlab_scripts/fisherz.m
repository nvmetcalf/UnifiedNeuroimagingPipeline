function [ fzt ] = fisherz( Matrix )
%fisherz Transforms the given matrix/vector/value from a r score to a
%fisher z score. NaN and inf values are ignored.

    fzt(length(Matrix(:,1,1)),length(Matrix(1,:,1)),length(Matrix(1,1,:))) = single(NaN);
    
    for i = 1:length(Matrix(:,1,1))
        for j = 1:length(Matrix(1,:,1))
            for k = 1:length(Matrix(1,1,:))
                
                if(~isnan(Matrix(i,j,k)) && ~isinf(Matrix(i,j,k)) && Matrix(i,j,k) ~= 0 )
                    fzt(i,j,k) = single(0.5 *( log(1 + Matrix(i,j,k)) - log(1 - Matrix(i,j,k)) ));
                else
                    fzt(i,j,k) = single(NaN);
                end
            end
        end
    end    
end

