
function save_ase_para(DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0, name_para)

num = length(DTE);

fid = fopen(name_para, 'wt');

fprintf(fid, '%d\n', num);

fprintf(fid, '%f %f %f %f\n', TE1, TE2, TE3, B0);

for i=1:num,
   fprintf(fid, '%f  %f  %f  %f\n', DTE(i), ZMoment1(i), ZMoment2(i), ZMoment3(i));
end;

fclose(fid);

