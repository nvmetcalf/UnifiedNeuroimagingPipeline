%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

	
function [DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0] = load_ase_para(name_para, date_para, time_para)

%fname = sprintf('../Para/%s_%s_%s.dat', name_para, date_para, time_para);
%fprintf('%s\n', fname);

fid = fopen(name_para, 'rt');

templ = fgetl(fid); temps = str2num(templ);
num = temps;

templ = fgetl(fid); temps = str2num(templ);

TE1 = temps(1);
TE2 = temps(2);
TE3 = temps(3);
B0 = temps(4);

DTE = zeros(num, 1);
ZMoment1 = zeros(num, 1);
ZMoment2 = zeros(num, 1);
ZMoment3 = zeros(num, 1);

for i=1:num,
   templ = fgetl(fid);
   tempf = str2num(templ);

   if length(tempf) == 4
      %indexi = fscanf(fid, '%d', 1);
      DTE(i) = tempf(1);
      ZMoment1(i) = tempf(2);
      ZMoment2(i) = tempf(3);
      ZMoment3(i) = tempf(4);
   else
      %indexi = fscanf(fid, '%d', 1);
      DTE(i) = tempf(2);
      ZMoment1(i) = tempf(3);
      ZMoment2(i) = tempf(4);
      ZMoment3(i) = tempf(5);
   end;
      
   %if indexi ~= i
   %   fprintf('check %s indexi %d, i %d\n', name_para, indexi, i);
   %end;
end;

fclose(fid);
