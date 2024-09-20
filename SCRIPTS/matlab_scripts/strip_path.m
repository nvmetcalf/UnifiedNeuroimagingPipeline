function [ OutString ] = strip_path( String )
%strip_path returns a string without characters preceding the last
%slash

    Slashes = find(String == '/');
    
    if(isempty(Slashes))
        Slashes = find(String == '\');
    end
    
    if(length(Slashes) == 0)
        OutString = String;
    else
        OutString = String( (Slashes(length(Slashes))+1) : length(String));
    end
end

