
function [im_out] = imresample_xyz_super(im_in, sx, sy, sz, interp_sign)

   [dimx, dimy, dimz] = size(im_in);
   dimx_out = dimx * sx;
   dimy_out = dimy * sy;
   dimz_out = dimz * sz;

   im_out=zeros(dimx_out, dimy_out, dimz_out);

   %for i=1:dimx,
   %   for j=1:dimy,
   %      for k=1:dimz,
   %         start_x = (i-1)*sx+1; end_x = i*sx;
   %         start_y = (j-1)*sy+1; end_y = j*sy;
   %         start_z = (k-1)*sz+1; end_z = k*sz;

   %         im_out(start_x:end_x, start_y:end_y, start_z:end_z) = im_in(i,j,k);
   %      end;
   %   end;
   %end;

   %return;

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   xin_range = [0:dimx-1]*sx;
   yin_range = [0:dimy-1]*sy;
   zin_range = [0:dimz-1]*sz;

   xmin = 0; xmax = dimx_out-1;
   ymin = 0; ymax = dimy_out-1;
   zmin = 0; zmax = dimz_out-1;

   xout_range = [xmin:1:xmax];
   yout_range = [ymin:1:ymax];
   zout_range = [zmin:1:zmax];

   %when using meshgrid, need to switch x, y. otherwise, the dimensions of the grid and image won't match
   [x, y, z] = meshgrid(yin_range, xin_range, zin_range);
   [xi, yi, zi] = meshgrid(yout_range, xout_range, zout_range);

   im_out = [];
   im_tmp = [];

   if interp_sign == 1
      im_out = interp3(x,y,z,im_in,xi,yi,zi,'cubic');
      im_tmp = interp3(x,y,z,im_in,xi,yi,zi,'linear');
   
      I = find(im_out<0);
      im_out(I) = im_tmp(I);
   end;

   %if interp_sign == 1
   %   im_out = interp3(x,y,z,im_in,xi,yi,zi,'linear');
   %end;

   if interp_sign == 0
      im_out = interp3(x,y,z,im_in,xi,yi,zi,'nearest');
   end;

   clear x y z xi yi zi xin_range yin_range zin_range;
   clear xout_range yout_range zout_range im_tmp;


