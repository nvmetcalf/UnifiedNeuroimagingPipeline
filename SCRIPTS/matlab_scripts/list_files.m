function [ FileList ] = list_files( SearchTerm )
%list_files lists files in SearchTerm in by timestamp in a cell array
    [~, list] = system(['ls -rtl ' SearchTerm ' | awk ''{print $NF} ''' ],'-echo');

    FileList = {};
    start = 1;
    for i = 1:length(list)

        if(isspace(list(i)))
            FileList = vertcat(FileList, list(start:i-1));
            start = i + 1;
        end

        if(i == length(list))
            FileList = vertcat(FileList, list(start:i));
        end
    end

end

