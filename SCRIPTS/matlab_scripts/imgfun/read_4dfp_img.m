function img_4dfp = read_4dfp_img(varargin)
%read_4dfp_img(args) 
%Usage: read_4dfp_img('file1', 'file2', ...'fileN')
%returns a structure containing all 4dfp files specified. By default, the 
%structure will have an ifh_info variable and a voxel_data variable. The 
% voxel_data variable is a voxel * time matrix.
%   Options:
%       verbose = output all information and warnings when reading images
%       3D = return a 3D volume * time matrix for voxel_data instead of
%               voxel * time.
%       uint16 = cast value of each voxel to an unsigned 16 bit integer.
%                   can reduce the amount of memory required to hold data
%                   by 50% with a small loss of "precision". Only use if you 
%                   know the image has values greater than 0.
%       uint8 = cast value of each voxel to an unsigned 8 bit integer. Can
%                   reduce the amount of memory required to hold the image
%                   by 75% with 50% reduced precision. Use only if you know
%                   the voxel values in the image are greater than 0.
%       int16 = cast the value of each voxel to a signed 16 bit integer.
%                   Can reduce memory required to hold the image by 25%
%                   with a small reduction in "precision". Can hold both
%                   positive and negative values.
%       int8 = cast the value of each voxel to a signed 8 bit integer.
%                   Can reduce memory required to hold the image by 75%
%                   with a 50% reduction in "precision". Can hold both
%                   positive and negative values.
%       Examples of different data types ( example is a 111 space MPR):
%           Name               Size               Bytes  Class     Attributes
% 
%           default             1x1             46140306  struct              
%           int16               1x1             23071634  struct              
%           int8                1x1             11537298  struct              
%           uint16              1x1             23071634  struct              
%           uint8               1x1             11537298  struct

    img_4dfp = [];    
    Verbose = false;
    Convert3D = false;
    Cast = '';
    
    %set switches
    for ArgIn = 1:length(varargin)
        if(strcmp(varargin{ArgIn}, 'verbose'))
            Verbose = true;
        elseif(strcmp(varargin{ArgIn}, '3D'))
            Convert3D = true;
        elseif(strcmp(varargin{ArgIn}, 'uint16') || strcmp(varargin{ArgIn}, 'uint8') ...
            || strcmp(varargin{ArgIn}, 'int16')  || strcmp(varargin{ArgIn}, 'int8'))
            Cast = varargin{ArgIn};
        end
    end
    
    for ArgIn = 1:length(varargin)
        
        if(~strcmp(varargin{ArgIn},'verbose') && ~strcmp(varargin{ArgIn}, '3D') ...
        && ~strcmp(varargin{ArgIn}, 'uint16') && ~strcmp(varargin{ArgIn}, 'uint8') ...
        && ~strcmp(varargin{ArgIn}, 'int16')  && ~strcmp(varargin{ArgIn}, 'int8'))
            %extract the 4dfp filename
            img_4dfp_name = varargin{ArgIn};
            Current_4dfp = [];
            % Check to see if the file, img_4dfp_name, exists in the current
            % directory
            if(~exist(img_4dfp_name))
                error(sprintf('Could not find %s. Check for hidden characters.',img_4dfp_name));
                return;
            end

            %clear out trailing spaces
            while(img_4dfp_name(length(img_4dfp_name)) == ' ')
                img_4dfp_name(length(img_4dfp_name)) = [];
            end

            % get necessary info from the ifhfile
            %finds the indicies of the dots in the filename character array
            DotIndicies = find(img_4dfp_name == '.');

            %replace the img extension with ifh so that we can read the ifh
            %information associated with the img.
            ifh_4dfp_file = [img_4dfp_name(1:DotIndicies(length(DotIndicies))) 'ifh'];

            if(~exist(ifh_4dfp_file))
                error(sprintf('Could not find %s',Current_4dfp.ifh_4dfp_file));
                return;
            end

            %extract the ifh contents
            Current_4dfp.ifh_info = read_4dfp_ifh(ifh_4dfp_file, Verbose);

            Current_4dfp.ifh_info.name_of_data_file = img_4dfp_name; %store this for easy writting later

            % read in the 4dfp
            [fid message] = fopen(img_4dfp_name,'r',Current_4dfp.ifh_info.imagedata_byte_order(1));

            if(fid < 0)
                disp(['ERROR: ' message]);
                return;
            end
            
            switch(Cast)
                case 'uint16'
                    Current_4dfp.voxel_data = uint16(fread(fid, Current_4dfp.ifh_info.number_format));
                case 'uint8'
                    Current_4dfp.voxel_data = uint8(fread(fid, Current_4dfp.ifh_info.number_format));
                case 'int16'
                    Current_4dfp.voxel_data = int16(fread(fid, Current_4dfp.ifh_info.number_format));
                case 'int8'
                    Current_4dfp.voxel_data = int8(fread(fid, Current_4dfp.ifh_info.number_format));
                otherwise
                    Current_4dfp.voxel_data = single(fread(fid, Current_4dfp.ifh_info.number_format));
            end
            
            fclose(fid);

            voxels_per_volume = Current_4dfp.ifh_info.matrix_size(1) * Current_4dfp.ifh_info.matrix_size(2) * Current_4dfp.ifh_info.matrix_size(3);

            read_volumes = length(Current_4dfp.voxel_data)/voxels_per_volume;

            if ~isequal(read_volumes, Current_4dfp.ifh_info.matrix_size(4))
                error('ifh volumes and img volumes do not match!');
                img_4dfp = [];
                return;
            end

            %take the amazingly long vector, and turn it into a voxel vector * volume
            %matrix
            if(Convert3D)
                Current_4dfp.voxel_data = reshape(Current_4dfp.voxel_data,[Current_4dfp.ifh_info.matrix_size]);
            else
                Current_4dfp.voxel_data = reshape(Current_4dfp.voxel_data,[voxels_per_volume read_volumes]);
            end

            if(isempty(img_4dfp))
                img_4dfp = Current_4dfp;
            else
                if([img_4dfp.ifh_info.matrix_size(1:3)] == [Current_4dfp.ifh_info.matrix_size(1:3)])
                    img_4dfp.voxel_data = horzcat(img_4dfp.voxel_data, Current_4dfp.voxel_data);
                else
                    error(sprintf('%s 4dfp matrix x,y, and z dimensions must be the same! Check your 4dfp ifh files.', ifh_4dfp_file));
                    img_4dfp = [];
                    return;
                end
            end
        end
    end
    
    %convert the voxels x time data structure to volume x time
%     if(Convert3D)
%         Volume_Data = [];
%         
%         for i = 1:length(img_4dfp.voxel_data(1,:))
%             Current_Volume = reshape(img_4dfp.voxel_data(i,:),[img_4dfp.ifh_info.matrix_size(1:3)]);
%             Volume_Data = horzcat(Volume_Data, Current_Volume);
%         end
%         
%         img_4dfp.voxel_data = Volume_Data;
%     end
end
