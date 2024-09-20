function [ extension ] = GetExtension( String )
%GetExtension Returns the first extension of the string provided

    LastDot = find(String == '.',1,'last');
    
    extension = String(LastDot+1:length(String));

end

