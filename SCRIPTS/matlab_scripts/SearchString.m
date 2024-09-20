function [ found ] = SearchString( String, SearchTerm )
%SearchString Returns true if the SearchTerm is found in the String
    found = false;
    
    i = 1;
    while(i+length(SearchTerm)-1 <= length(String))
        if(strcmp(String(i:i+length(SearchTerm)-1), SearchTerm))
           found = true;
           return;
        end
        i = i + 1;
    end
end

