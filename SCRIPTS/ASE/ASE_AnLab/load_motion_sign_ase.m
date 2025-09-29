%% Subroutine for ASE pipeline
%% AnLab 2025/02/10
   
function [sign_motion1, sign_motion2, sign_motion3] = load_motion_sign_ase(name_sign, dimt)

   sign_motion1 = zeros(dimt, 1);
   sign_motion2 = zeros(dimt, 1);
   sign_motion3 = zeros(dimt, 1);

   fid = fopen(name_sign, 'rt');
try
   for i=1:dimt
      
      sign_motion1(i) = fscanf(fid, '%d', 1);
      sign_motion2(i) = fscanf(fid, '%d', 1);
      %sign_motion3(i) = fscanf(fid, '%d', 1);
   end
catch
   disp('error'); 
end
   fclose(fid);

   
