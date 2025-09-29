%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

function [rx, ry, rz, tx, ty, tz] = load_par(name_in, dimt)

   rx = zeros(dimt, 1);
   ry = zeros(dimt, 1);
   rz = zeros(dimt, 1);
   tx = zeros(dimt, 1);
   ty = zeros(dimt, 1);
   tz = zeros(dimt, 1);

   fid = fopen(name_in ,'rt');

   for i=1:dimt,
      rx(i) = fscanf(fid, '%f', 1);
      ry(i) = fscanf(fid, '%f', 1);
      rz(i) = fscanf(fid, '%f', 1);
      tx(i) = fscanf(fid, '%f', 1);
      ty(i) = fscanf(fid, '%f', 1);
      tz(i) = fscanf(fid, '%f', 1);
   end;

   fclose(fid);


