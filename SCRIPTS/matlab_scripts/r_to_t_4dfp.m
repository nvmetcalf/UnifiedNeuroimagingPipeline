% load 4dfp image
% convert all the r's to t's
% write image out

function voxels = r_to_t_4dfp(ImageInput, N, NumberOfTails, WriteIndividualFrames)

    if(N < 6)
        error('You must have at least 6 samples to transform a pearson R to student T');
    end
    
    if(~exist('NumberOfTails'))
        NumberOfTails = 2;
    end
    
    if(~exist('WriteIndividualFrames'))
        WriteIndividualFrames = 0;
    end
    if(NumberOfTails > 2)
        error('P values cannot be computed for more than 2 tails.');
    end
    
    voxels = read_4dfp_img(ImageInput);
        
    for i = 1:length(voxels.voxel_data(1,:))
        for(j = 1:length(voxels.voxel_data(:,1)))
            voxels.voxel_data(j,i) = voxels.voxel_data(j,i)/sqrt((1-voxels.voxel_data(j,i)^2)/(N-2)); %compute students t for the pearson r
        
            if(voxels.voxel_data(j,i) > 1 && 0)
                disp('t > 2');
            end
        
            %voxels.voxel_data(i) = NumberOfTails*(1-tcdf(abs(voxels.voxel_data(i)),N-2));
        end
    end
    if(WriteIndividualFrames)
        temp = voxels;
        for(i = 1:length(voxels.voxel_data(1,:)))
            disp(['Writing Volume: ' num2str(i)]);
            temp.voxel_data = voxels.voxel_data(:,i);
            temp.ifh_info.matrix_size(4) = 1;
            
            write_4dfp_img(temp,[strip_extension(strip_extension(ImageInput)) '_r_to_t_' num2str(i) '.4dfp.img']);
            system(['ifh2hdr ' strip_extension(strip_extension(ImageInput)) '_r_to_t_' num2str(i) '.4dfp.img']);
        end
    else
        write_4dfp_img(voxels,[strip_extension(strip_extension(ImageInput)) '_r_to_t.4dfp.img']);
        system(['ifh2hdr ' strip_extension(strip_extension(ImageInput)) '_r_to_t.4dfp.img']);
    end
end