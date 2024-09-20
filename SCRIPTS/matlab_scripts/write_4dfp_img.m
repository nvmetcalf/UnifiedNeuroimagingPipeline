function write_4dfp_img(img_4dfp,output_name,endian_type_out)
%Usage: write_4dfp_img(img_4dfp_struct, outputname,<endian_type_out -
%optional>
%NOTE: Always writes 4dfp images as single precision. If you read the 4dfp
%as an integer type, the image is cast as a single precision floating point
%image.

if(~isstruct(img_4dfp))
    error('Input 4dfp image is not a struct.');
    return;
end

if(isempty(output_name))
    output_name = img_4dfp.ifh_info.name_of_data_file;
    disp(sprintf('Using %s as output name', output_name));
end

if(~exist('endian_type_out'))
    endian_type_out = img_4dfp.ifh_info.imagedata_byte_order;
    disp(sprintf('Using %s as byte order.', endian_type_out));
end

% what is endian type
switch endian_type_out(1)
    case 'b'
        endian_type = ['ieee-be'];
        img_4dfp.ifh_info.imagedata_byte_order = ['bigendian'];
    case 'l'
        endian_type = ['ieee-le'];
        img_4dfp.ifh_info.imagedata_byte_order = ['littleendian'];
    otherwise
        error('Endian type selected was neither bigendian nor littleendian.');
end

img_4dfp.ifh_info.name_of_data_file = output_name;

disp(sprintf('Writting %s...',output_name));
fid=fopen(output_name,'w',endian_type);

if(~isfloat(img_4dfp.voxel_data))
    fwrite(fid, cast(img_4dfp.voxel_data, 'single'), img_4dfp.ifh_info.number_format, 0, endian_type);
else
    fwrite(fid, img_4dfp.voxel_data, img_4dfp.ifh_info.number_format, 0, endian_type);
end

write_4dfp_ifh(img_4dfp.ifh_info);
fclose(fid);