
%% Subroutine for ASE pipeline
%% AnLab 2025/02/10
	
function [DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0, indices] = load_ase_para_with_index(name_para, date_para, time_para)

%fname = sprintf('../Para/%s_%s_%s.dat', name_para, date_para, time_para);
%fprintf('%s\n', fname);

fid = fopen(name_para, 'rt');

num = fscanf(fid, '%d', 1);
TE1 = fscanf(fid, '%f', 1);
TE2 = fscanf(fid, '%f', 1);
TE3 = fscanf(fid, '%f', 1);
B0 = fscanf(fid, '%f', 1);

DTE = zeros(num, 1);
ZMoment1 = zeros(num, 1);
ZMoment2 = zeros(num, 1);
ZMoment3 = zeros(num, 1);
indices = zeros(num, 1);

for i=1:num,
   indexi = fscanf(fid, '%d', 1);
   DTE(i) = fscanf(fid, '%f', 1);
   ZMoment1(i) = fscanf(fid, '%f', 1);
   ZMoment2(i) = fscanf(fid, '%f', 1);
   ZMoment3(i) = fscanf(fid, '%f', 1);
   indices(i) = indexi;

   fprintf('i %d indexi %d DTE %f Z1 %f Z2 %f Z3 %f\n', i, indexi, DTE(i), ZMoment1(i), ZMoment2(i), ZMoment3(i));

   if indexi ~= i
      fprintf('check %s indexi %d, i %d\n', name_para, indexi, i);
   end;
end;

fclose(fid);
