function [pth fbase ext] = MYfilenamefinder(filename,dots)

[pth,fbase,ext]=fileparts(filename);
if isempty(pth)
    pth=pwd;
end

switch dots
    case 'dotsin'
    case 'dotsout'
        fbase=regexprep(fbase,'\.','');
        pth=regexprep(pth,'\.','');
    otherwise
        error('Use dotsin or dotsout');
end