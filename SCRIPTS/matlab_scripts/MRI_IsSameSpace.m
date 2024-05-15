function [ result ] = MRI_IsSameSpace( VolumeImage1, VolumeImage2, ErrorOut )
%MRI_IsSameSpace returns true if the two images are in the same volume
%space and false if they are not. If ErrorOut is set to true, the result
%is also written to stdout.

    result = true;
    
    Image1Dimensions = [0 0 0];
    Image2Dimensions = [0 0 0];
    
    if(~exist('ErrorOut'))
        ErrorOut = false;
    end
    
    switch(GetExtension(VolumeImage1))
        case 'nii'
            Image1Header = niftiRead(VolumeImage1, []);
            Image1Dimensions = Image1Header.dim(1:3);
        case 'img'
            Image1Header = read_4dfp_ifh([strip_extension(VolumeImage1) '.ifh']);
            Image1Dimensions = Image1Header.matrix_size(1:3);
        otherwise
            error(['Unknown image type on first volume: ' GetExtension(VolumeImage1)]);
    end
    
    switch(GetExtension(VolumeImage2))
        case 'nii'
            Image2Header = niftiRead(VolumeImage2, []);
            Image2Dimensions = Image2Header.dim(1:3);
        case 'img'
            Image2Header = read_4dfp_ifh([strip_extension(VolumeImage2) '.ifh']);
            Image2Dimensions = Image2Header.matrix_size(1:3);
        otherwise
            error(['Unknown image type on first volume: ' GetExtension(VolumeImage2)]);
    end
    
    if( Image1Dimensions(1) ~= Image2Dimensions(1) ...
     || Image1Dimensions(2) ~= Image2Dimensions(2) ...
     || Image1Dimensions(2) ~= Image2Dimensions(2) )
        result = false;    
    end  
    
    if(ErrorOut)
        a = fopen('.result','w');
        fwrite(a, sprintf('%i',result));
        fclose(a);
        disp(result);
	end
    
    return;
end

