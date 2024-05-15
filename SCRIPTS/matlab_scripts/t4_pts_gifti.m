function [] =  t4_pts_gifti(giipath,t4_file_in,gifti_file_in,gifti_file_out,save_lsts)
addpath(genpath(giipath));

%to keep matlab from using its libraries for t4_pts
setenv('LD_LIBRARY_PATH','/lib64');

%Optional .lst output filenames
pts_list_1_out=[gifti_file_in '.v.lst'];
pts_list_2_out=[gifti_file_out '.v.lst'];

%Read input (requires correct gifti toolbox version for file)
x=gifti(gifti_file_in);

%Write vertices to list file
fid=fopen(pts_list_1_out,'w');
fprintf(fid,'%f %f %f \n',x.vertices');
fclose(fid);

%Apply t4_file to pts_list_1_out to make pts_list_2_out
system(sprintf('t4_pts %s %s %s',t4_file_in,pts_list_1_out,pts_list_2_out));

%Read transformed vertices
fid=fopen(pts_list_2_out);
x_t4=cell2mat(textscan(fid,'%f %f %f \n'));
fclose(fid);

%Modify gifti structure and save to file
x.vertices=x_t4;
save(x,gifti_file_out,'GZipBase64Binary') %May want to add optional encoding argument

%Delete intermediary lists if requested
if ~save_lsts
    system(sprintf('rm %s',pts_list_1_out));
    system(sprintf('rm %s',pts_list_1_out));
end
