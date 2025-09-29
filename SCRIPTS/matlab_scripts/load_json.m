function json_struct = load_json(JSON_FILENAME)
    %loads a json file ans converts it to a structure to be used in matlab
    
    File = fopen(JSON_FILENAME);
    RawJSON = fread(File,inf);
    fclose(File);
    
    json_struct = json_decode(char(RawJSON'));
end