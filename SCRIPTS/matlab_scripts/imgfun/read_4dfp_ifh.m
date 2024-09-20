function ifh_info = read_4dfp_ifh(ifh_file_name, Verbose)

    if(~exist('Verbose'))
        Verbose = false;
    end
    
    %parse the ifh file to extract all the fields and store them in the ifh
    %structure for future use.

    %known fields
    % INTERFILE                         :=
    % version of keys                   := 3.3
    % name of data file                 := 
    % number format                     := float
    % number of bytes per pixel         := 4
    % orientation                       := 2
    % number of dimensions              := 4
    % matrix size [1]                   := 70
    % matrix size [2]                   := 70
    % matrix size [3]                   := 43
    % matrix size [4]                   := 1
    % scaling factor (mm/pixel) [1]     := 3.000000
    % scaling factor (mm/pixel) [2]     := 3.000000
    % scaling factor (mm/pixel) [3]     := 3.000000
    % imagedata byte order              := littleendian
    % center                            := 105.000000 -108.000000 -66.000000
    % mmppix                            := 3.000000 -3.000000 -3.000000
    % fwhm in voxels                    := 0.000000
    if(Verbose)
        disp('Reading IFH...');
    end
    
    %ifh_info = struct('INTERFILE',{},'version_of_keys',3.3,'name_of_data_file',{},'number_format',{},'number_of_bytes_per_pixel',{},'orientation',{},'number_of_dimension',{},'matrix_size',{},'scaling_factor',{},'imagedata_byte_order',{},'center',{},'mmppix',{},'fwhm_in_voxels',{});
    ifh_info.INTERFILE = '';
	ifh_info.version_of_keys = 3.3;
	ifh_info.region_names = [];
	RegionIndex = 1;
        
    File = fopen(ifh_file_name,'r');

    ifh_data = fread(File)';
    RawBuffer = [];
    Buffer = [];

    for i = 1:length(ifh_data)
        if(ifh_data(i) == 10)   %10 = ASCII line feed
            Buffer = cast(RawBuffer,'char');    %convert the ints to chars
            
            %extract the field
            FieldNameEnd = find(Buffer == ':');
            
            FieldName = Buffer(1:FieldNameEnd-1);
            
            %remove blank space from the field name
            
            Spaces = isspace(FieldName);
            while Spaces(length(Spaces))
                FieldName(length(FieldName)) = [];
                Spaces(length(Spaces)) = [];
            end
            
            FieldValue = Buffer(FieldNameEnd+3:length(Buffer));
            
            if(length(FieldValue) == 0)
                if(Verbose)
                    disp(sprintf('Field %s is empty. Setting to empty.',FieldName));
                end
                FieldValue = [];
            end
            
            switch(FieldName)
                %                     case 'INTERFILE'
                %                         ifh_info.INTERFILE = FieldValue;
                %
                %                     case 'version of keys'
                %                         ifh_info.version_of_keys = str2num(FieldValue);
                
                case 'name of data file'
                    ifh_info.name_of_data_file = FieldValue;
                    
                case 'number format'
                    ifh_info.number_format = FieldValue;
                    
                case 'number of bytes per pixel'
                    ifh_info.number_of_bytes_per_pixel = str2num(FieldValue);
                    
                case 'orientation'
                    ifh_info.orientation = str2num(FieldValue);
                    
                case 'number of dimensions'
                    ifh_info.number_of_dimensions = str2num(FieldValue);
                    
                case 'matrix size [1]'
                    ifh_info.matrix_size(1) = str2num(FieldValue);
                    
                case 'matrix size [2]'
                    ifh_info.matrix_size(2) = str2num(FieldValue);
                    
                case 'matrix size [3]'
                    ifh_info.matrix_size(3) = str2num(FieldValue);
                    
                case 'matrix size [4]'
                    ifh_info.matrix_size(4) = str2num(FieldValue);
                    
                case 'scaling factor (mm/pixel) [1]'
                    ifh_info.scaling_factor(1) = str2num(FieldValue);
                    
                case 'scaling factor (mm/pixel) [2]'
                    ifh_info.scaling_factor(2) = str2num(FieldValue);
                    
                case 'scaling factor (mm/pixel) [3]'
                    ifh_info.scaling_factor(3) = str2num(FieldValue);
                    
                case 'imagedata byte order'
                    ifh_info.imagedata_byte_order = FieldValue;
                    
                case 'center'
                    %may need to extract them as there are 3 numbers
                    ifh_info.center = FieldValue;
                    
                case 'mmppix'
                    %may need to extract them as there are 3 numbers
                    ifh_info.mmppix = FieldValue;
                    
                case 'fwhm in voxels'
                    ifh_info.fwhm_in_voxels = str2num(FieldValue);
                    
                case 'region names'
                    ifh_info.region_names(RegionIndex).Region = FieldValue;
                    RegionIndex = RegionIndex + 1;
                
                otherwise
                    if(Verbose)
                        disp(sprintf('Unknown field %s',FieldName));
                    end
                                    
            end

            RawBuffer = [];
        else
            RawBuffer = horzcat(RawBuffer, ifh_data(i));
        end
    end
    fclose(File); 
    
    if(Verbose)
        disp('Completed reading IFH.');
    end
end