function [ OutString ] = strip_extension( String )
%strip_extension returns a string without characters following the last
%period

    Periods = find(String == '.');
    
    if(length(Periods) == 0)
        OutString = String;
    else
        OutString = String(1:Periods(length(Periods))-1);
    end
end

