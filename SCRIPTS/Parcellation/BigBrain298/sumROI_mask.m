%%% quick script to add together ROIs into a final mask, with each ROI numbered in its proper order

roi_names_file = 'BigBrain298_roilist.txt' %'potentialROIs_updated_711/potentialROIs_updated_711_roilist_modified.txt';
[imgfiles x y z] = textread(roi_names_file,'%s%f%f%f');

all_mat = zeros(147456,1);
for r = 1:length(imgfiles)
    [roi_mat f v] = read_4dfpimg(imgfiles{r});
    all_mat(roi_mat>0) = r;
    clear roi_mat f v;
end
[v f endiantype] = fcimage_attributes(imgfiles{1});

%fout = 'cerebellumROIs_711-2b_allROIs.4dfp.img';
fout = 'BigBrain298_711-2b_allROIs.4dfp.img';
write_4dfpimg(all_mat,fout,endiantype);
write_4dfpifh(fout,f,endiantype);

% make nii version
command = sprintf('nifti_4dfp -n %s %s',fout(1:end-9),fout(1:end-9));
system(command);

% and convert to MNI
command = sprintf('t4img_4dfp -n $RELEASE/711-2B_to_MNI152lin_T1_t4 %s %sMNI_allROIs.4dfp.img',fout,fout(1:12));
system(command);
command = sprintf('nifti_4dfp -n %sMNI_allROIs %sMNI_allROIs',fout(1:12),fout(1:12));
system(command);
