
function [num_dicoms, DTE, TE1, TE2, ZMoment1, ZMoment2, B0] = getASEParameters_2echoes(name_dir1, name_dir2)

%path(path, '/hongyu/yyang/ASE_nico/ASE/Dicom');

%name_dir1 = '../Dicom_CNDA/0831_007/scans/14/DICOM/';
%name_dir2 = '../Dicom_CNDA/0831_007/scans/15/DICOM/';

num_dicoms = -1;
DTE = [];
TE1 = [];
TE2 = [];
ZMoment1 = [];
ZMoment2 = [];
B0 = [];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%5
name1_pattern = sprintf('%s/*', name_dir1);
name2_pattern = sprintf('%s/*', name_dir2);

names1 = dir(name1_pattern);
names2 = dir(name2_pattern);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
num1 = 0; num2 = 0;

for i=1:length(names1),
   if strcmp(names1(i).name, '.')==1 | strcmp(names1(i).name, '..')==1
      continue;
   end;
   
   nnn = sprintf('%s/%s', name_dir1, names1(i).name);
   
   if isdicom(nnn)==0
      clear nnn
      continue;
   end;
   
   num1 = num1 + 1;
   names1_tobe_sorted{num1} = names1(i).name;
   clear nnn;
end;

for i=1:length(names2),
   if strcmp(names2(i).name, '.')==1 | strcmp(names2(i).name, '..')==1
      continue;
   end;

   nnn = sprintf('%s/%s', name_dir2, names2(i).name);

   if isdicom(nnn)==0
      continue;
   end;
   
   num2 = num2 + 1;
   names2_tobe_sorted{num2} = names2(i).name;
   clear nnn;
end;

if num1~=num2
   fprintf('the numbers are different %d %d\n', num1, num2);
   return;
end;

%% 112: Very old version
%% 98: Most used version: 2/3 Echo, w/  zshimming
%% 90: Most used version: 2/3 Echo, w/o zshimming
%% 82: WU-Vanderbilt, MaxDTE=40, w/o zshimming, 2 Repetition
%% 41: WU-Vanderbilt, MaxDTE=40, w/o zshimming, 1 Repetition

if num1 ~= 112 & num1 ~= 98 & num1 ~= 90 & num1 ~= 82 & num1 ~= 41
   fprintf('the numbers are %d, num1, please check %s\n', num1, name_dir1);
   return;
end;

num = num1;
num_dicoms = num;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%need to sort the order of dicom files 
[names1_sorted, index1] = sort_nat(names1_tobe_sorted, 'ascend');
[names2_sorted, index2] = sort_nat(names2_tobe_sorted, 'ascend');

%for i=1:num,
%   fprintf('%s\n', names1_sorted{i});
%end;

%fprintf('\n\n');

%for i=1:num,
%   fprintf('%s\n', names2_sorted{i});
%end;

%fprintf('\n\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for k=1:2,
   for i=1:num,
      switch k,
         case 1
            name_in = sprintf('%s/%s', name_dir1, names1_sorted{i});
         case 2
            name_in = sprintf('%s/%s', name_dir2, names2_sorted{i});
      end;

      %%%%%fprintf('echo %d  %d  %s\n', k, i, name_in);

      info = dicominfo(name_in);
      % b0(k,i) = info.MagneticFieldStrength;
      
      if strfind(info.SoftwareVersion,'syngo MR XA')
      	TE(k,i) = info.PerFrameFunctionalGroupsSequence.Item_1.MREchoSequence.Item_1.EffectiveEchoTime;
         b0(k,i) = info.SharedFunctionalGroupsSequence.Item_1.MRImagingModifierSequence.Item_1.TransmitterFrequency/42.576;
      else
      	TE(k,i) = info.EchoTime;
         b0(k,i) = info.ImagingFrequency/42.576;
      end
      
      imagecomments = info.ImageComments;
      a = strread(imagecomments,'%s', 'delimiter', ',');
      if  strfind(info.SoftwareVersion,'syngo MR XA') && length(a) == 8
          a2=char(a(3));
          a3=char(a(4));
          a7=char(a(8));
      else
          a2=char(a(2));
          a3=char(a(3));
          a7=char(a(7));
      end
          
      [b1,b2,b3] = strread(a2, '%s%s%d', 'delimiter', ' ');
      DTEArr(k, i) = b3;
      clear b1 b2 b3;

      [b1,b2,b3] = strread(a3, '%s%s%d', 'delimiter', ' ');
      zmoment(k, i) = b3;
      clear b1 b2 b3;

      [b1,b2,b3] = strread(a7, '%s%s%d', 'delimiter', ' ');
      dTE(k, i) = b3;
      clear b1 b2 b3;

      clear a imagecomments info name_in;
   end;
end;

%%%%%%%%%check the results to make things are correct
te1 = squeeze(TE(1,:));
te2 = squeeze(TE(2,:));

if max(te1)~=min(te1) | max(te2)~=min(te2)
   fprintf('TE wrong %f %f, %f %f, %f %f\n', min(te1), max(te1), min(te2), max(te2));
end;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for i=1:num
   if DTEArr(1,i)~=DTEArr(2,i) 
      fprintf('DTIArr %d %f %f\n', i, DTEArr(1,i), DTEArr(2,i)); 
   end;
end;

for i=1:num-8
   if zmoment(1,i)~=0 | zmoment(2,i)~=0
      fprintf('zmoment %d %f %f\n', i, zmoment(1,i), zmoment(2,i)); 
   end;
end;

if max(b0(:)) ~= min(b0(:))
   fprintf('field strength %f %f\n', min(b0(:)), max(b0(:)));
end;

DTE = squeeze(DTEArr(1,:));
TE1 = TE(1,1);
TE2 = TE(2,1);

ZMoment1 = squeeze(zmoment(1,:));
ZMoment2 = squeeze(zmoment(2,:));

B0 = b0(1,1);

