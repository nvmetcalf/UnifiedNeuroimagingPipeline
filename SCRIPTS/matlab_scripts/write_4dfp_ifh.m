function write_4dfp_ifh(ifh_info)

Dots = find(ifh_info.name_of_data_file == '.');

ifh_filename = [ifh_info.name_of_data_file(1:Dots(length(Dots))) 'ifh'];

disp(sprintf('Writting %s...',ifh_filename));

% write ifh
fidifh=fopen(ifh_filename,'w');
fprintf(fidifh,['INTERFILE       := ' ifh_info.INTERFILE '\n']);
fprintf(fidifh,['version of keys := ' num2str(ifh_info.version_of_keys) '\n']);
fprintf(fidifh,['number format           := ' ifh_info.number_format '\n']);
fprintf(fidifh,['conversion program      := write_4dfp_img.m\n']);
fprintf(fidifh,['name of data file       := ' ifh_info.name_of_data_file '\n']);
fprintf(fidifh,['number of bytes per pixel       := ' num2str(ifh_info.number_of_bytes_per_pixel) '\n']);
fprintf(fidifh,['imagedata byte order    := ' ifh_info.imagedata_byte_order '\n']);
fprintf(fidifh,['orientation             := ' num2str(ifh_info.orientation) '\n']);
fprintf(fidifh,['number of dimensions    := ' num2str(ifh_info.number_of_dimensions) '\n']);
fprintf(fidifh,['matrix size [1] := ' num2str(ifh_info.matrix_size(1)) '\n']);
fprintf(fidifh,['matrix size [2] := ' num2str(ifh_info.matrix_size(2)) '\n']);
fprintf(fidifh,['matrix size [3] := ' num2str(ifh_info.matrix_size(3)) '\n']);
fprintf(fidifh,['matrix size [4] := ' num2str(ifh_info.matrix_size(4)) '\n']);
fprintf(fidifh,['scaling factor (mm/pixel) [1]   := ' num2str(ifh_info.scaling_factor(1)) '\n']);
fprintf(fidifh,['scaling factor (mm/pixel) [2]   := ' num2str(ifh_info.scaling_factor(2)) '\n']);
fprintf(fidifh,['scaling factor (mm/pixel) [3]   := ' num2str(ifh_info.scaling_factor(3)) '\n']);

try
    fprintf(fidifh,['mmppix  :=   ' num2str(ifh_info.mmppix) '\n']);
end

try
    fprintf(fidifh,['center  :=    ' num2str(ifh_info.center) '\n']);
end

if(length(ifh_info.region_names) > 0)
    for i = 1:length(ifh_info.region_names)
        fprintf(fidifh,['region names  :=    ' ifh_info.region_names(i).Region '\n']);
    end
end

fclose(fidifh);
