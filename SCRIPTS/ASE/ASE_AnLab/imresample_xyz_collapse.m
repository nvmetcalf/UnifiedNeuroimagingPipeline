
function [im_out] = imresample_xyz_collapse(im_in, sx, sy, sz)

   [dimx, dimy, dimz] = size(im_in);
   dimx_out = dimx / sx;
   dimy_out = dimy / sy;
   dimz_out = dimz / sz;

   im_out = zeros(dimx_out, dimy_out, dimz_out);

   for i=1:dimx_out,
      for j=1:dimy_out,
         for k=1:dimz_out,
            start_x = (i-1)*sx+1; end_x = i*sx;
            start_y = (j-1)*sy+1; end_y = j*sy;
            start_z = (k-1)*sz+1; end_z = k*sz;

            tmp = im_in(start_x:end_x, start_y:end_y, start_z:end_z);
            im_out(i,j,k) = mean(tmp(:));
            clear tmp;
         end;
      end;
   end;

   



  
