function [ mean_matrix ] = mean_mat( varargin )
%mean_mat compute the mean of each x,y across supplied matricies. 3D
%matricies can be provided

    unpacked_input = [];
    %unpack the varargin cell array and form it into a 3d matrix
    for i = 1:length(varargin)
        curr_mat = varargin{i};
        if(isempty(unpacked_input))
            unpacked_input = curr_mat;
        else
            stack_start = length(unpacked_input(1,1,:)) + 1;
            stack_end = stack_start + length(curr_mat(1,1,:))-1;
            unpacked_input(:,:, stack_start:stack_end) = curr_mat;
        end
    end

    mean_matrix = zeros(length(unpacked_input(1,:,1)), length(unpacked_input(:,1,1)));

    for x = 1:length(unpacked_input(1,:,1))
        for y = 1:length(unpacked_input(:,1,1))

            mean_matrix(y,x) = mean(unpacked_input(y,x,:)); 
        end
    end

end

