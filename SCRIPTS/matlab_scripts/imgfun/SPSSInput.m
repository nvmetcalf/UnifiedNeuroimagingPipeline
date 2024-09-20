function [ output_args ] = SPSSInput(outfilename,inmat,labels )
%UNTITLED3 Summary of this function goes here
%   inatmat must be 196xN, labels must be 1xN
fid = fopen([outfilename '.csv'],'w');
fprintf(fid,'study_id,');
for n=1:length(labels)
    fprintf(fid,[labels{n} ',']);
end
fprintf(fid,'\n');

if size(inmat,1)==196
    
    for i=24:196
        if i<100;fprintf(fid,['FCS_0' num2str(i) ',']);
        else fprintf(fid,['FCS_' num2str(i) ',']);end
        
        for n=1:length(labels)
            fprintf(fid,'%.4f,',inmat(i,n));
        end
        fprintf(fid,'\n');
    end
    fclose(fid);
    
elseif size(inmat,1)==36
    
    for i=1:36
        if i<10;fprintf(fid,['FCS_00' num2str(i) ',']);
        else fprintf(fid,['FCS_0' num2str(i) ',']);end
        
        for n=1:length(labels)
            fprintf(fid,'%.4f,',inmat(i,n));
        end
        fprintf(fid,'\n')
    end
    fclose(fid)
    
else
    error('Unknown matrix size.');
end
end

