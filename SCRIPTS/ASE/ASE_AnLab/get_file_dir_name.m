%{
This software is developed by Yasheng Chen and Chia-Ling Phua in WUSTL as part of the pre-processing pipeline for FLAIR WMH segmentation.
Please email chen.yasheng@gmail.com for questions and comments.
03/30/2022
%}

function [name_dir, name_file] = get_file_dir_name(name_in)

   locs = strfind(name_in, '/');

   name_dir = name_in(1:locs(end)-1);
   name_file = name_in(locs(end)+1:end);

   clear locs;

