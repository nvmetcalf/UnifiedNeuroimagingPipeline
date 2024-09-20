%for each ddat file, we want to import it, plot it, and save the plot

%assume we are in the movement folder already
FileList = dir('*.ddat');

%work our way through them all
for i = 1:length(FileList)
    [ddx,ddy,ddz,drX,drY,drZ] = import_ddat(FileList(i).name);
    
    %replace the _ with spaces so the plot titles don't look crazy.
    FileOut = FileList(i).name
    FileOut(FileOut == '_') = ' ';
    
    plot_movement_parameters(FileOut, [ddx ddy ddz drX drY drZ], [strip_extension(FileList(i).name) '_movement_plot.pdf']);
end