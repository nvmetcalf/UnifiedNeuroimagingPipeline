function [ CIFTI ] = flip_hemi_cifti( CiftiInputFile, OutputFilename )
%flip_hemi_cifti : flips the hemispheres of a cifti timeseries
%   flip_hemi_cifti takes CiftiInputFile and flips the hemisphers of the
%   data. The data is stored based on the OutputFilename. If the output
%   method is a string(ie filename), the flipped cifti will be written to
%   that filename. If OutputFilename is not specified or empty, the flipped
%   cifti will be returned via CiftiOut. The dtseries.nii does not need to
%   be a part of the output filename

    if(~exist(CiftiInputFile))
        error([ CiftiInputFile ' does not exist!']);

    end

    CIFTI = ft_read_cifti_mod(CiftiInputFile);

    lverts = sum(CIFTI.brainstructure == 1);
    rverts = sum(CIFTI.brainstructure == 2);
    
    htot = length(CIFTI.brainstructure);    %set how many total verticies there can be
    
    wholebrain = zeros(htot,length(CIFTI.data(1,:)));
        
    wholebrain(find(CIFTI.brainstructure == 1), :) = CIFTI.data(1:lverts, :);   %load in the right verts to the left hemi
    wholebrain(CIFTI.brainstructure == 2, :) = CIFTI.data((lverts+1):(lverts+rverts), :);   %load in the left verts to the right hemi 
    
    temp = wholebrain(1:htot/2,:);  %save the left hemi
    wholebrain(1:htot/2,:) = wholebrain((htot/2)+1:htot, :); %swap the right into left hemi
    wholebrain((htot/2)+1:htot, :) = temp;  %swap left into right
        
    CIFTI.data = wholebrain(CIFTI.brainstructure > 0, :);  %sort out those vertices that shouldn't exist
    
    if(exist('OutputFilename'))
        disp('Writing flipped cifti.');
        ft_write_cifti_mod([OutputFilename '.dtseries.nii'],CIFTI);
    end
    
end

