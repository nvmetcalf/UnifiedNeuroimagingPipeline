
%% Subroutine for ASE pipeline
%% AnLab 2025/02/10
   
function [im_out] = imresample(im_in, xin_range, yin_range, zin_range, xout_range, yout_range, zout_range, interp_sign)

   [dimx, dimy, dimz] = size(im_in);
   dimx_out = length(xout_range);
   dimy_out = length(yout_range);
   dimz_out = length(zout_range);

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   xmax = max(xin_range);
   ymax = max(yin_range);
   zmax = max(zin_range);

   xmin = min(xin_range);
   ymin = min(yin_range);
   zmin = min(zin_range);

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   Ix = find(xout_range>=xmin & xout_range<=xmax);
   Iy = find(yout_range>=ymin & yout_range<=ymax);
   Iz = find(zout_range>=zmin & zout_range<=zmax);

   sx = min(Ix); ex = max(Ix);
   sy = min(Iy); ey = max(Iy);
   sz = min(Iz); ez = max(Iz);

   xout_within = xout_range(sx:ex);
   yout_within = yout_range(sy:ey);
   zout_within = zout_range(sz:ez);

   [xin, yin, zin] = meshgrid(yin_range, xin_range, zin_range);
   [xout,yout,zout] = meshgrid(yout_within, xout_within, zout_within);

   %%%cubic interpolation sometimes create negative value in the low intensity region
   im_out_within = interp3(xin,yin,zin,im_in,xout,yout,zout,interp_sign);

   im_out = zeros(dimx_out, dimy_out, dimz_out);
   im_out(sx:ex,sy:ey,sz:ez) = im_out_within;

   clear im_out_within;

