% load 4dfp image
% convert all the r's to t's and t's to p's
% write image out

function voxels = r_to_p_4dfp(ImageInput, ImageOutput, N, NumberOfTails)

    if(N < 6)
        error('You must have at least 6 samples to transform a pearson R to student T');
    end
    
    if(~exist('NumberOfTails'))
        NumberOfTails = 2;
    end
    
    if(NumberOfTails > 2)
        error('P values cannot be computed for more than 2 tails.');
    end
    
    voxels = read_4dfp_img(ImageInput);
        
    for i = 1:length(voxels.voxel_data)
        voxels.voxel_data(i) = voxels.voxel_data(i)/sqrt((1-voxels.voxel_data(i)^2)/(N-2)); %compute students t for the pearson r
        
        if(voxels.voxel_data(i) > 1 && 0)
            disp('t > 2');
        end
        
        %voxels.voxel_data(i) = NumberOfTails*(1-tcdf(abs(voxels.voxel_data(i)),N-2));
    end

    write_4dfp_img(voxels,ImageOutput);
end