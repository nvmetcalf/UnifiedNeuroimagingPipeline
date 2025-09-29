
%% Subroutine for ASE pipeline
%% AnLab 2025/02/10
  
function hematocrit_value = get_hematocrit(name_subject,name_folder)

  hematocrit_value = -1;

  %s_all = sprintf('%s_%s_%s', name_subject, date_subject, time_subject);

  % fid = fopen('../Orig_ASE/hct_info.txt', 'rt');
  fid = fopen(sprintf('%s/hct_info.txt',name_folder), 'rt');
  while feof(fid) ~= 1
     s1 = fscanf(fid, '%s', 1); s1=strtrim(s1);
     s2 = fscanf(fid, '%s', 1); s2=strtrim(s2);

     if strcmp(s1, name_subject) == 1 
        hematocrit_value = str2num(s2)/100;
        break;
     end;

     clear s1 s2;
   end;

   fclose(fid);


