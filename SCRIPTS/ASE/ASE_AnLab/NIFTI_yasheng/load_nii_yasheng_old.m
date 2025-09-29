
function nii = load_nii_yasheng_old(fname)

   nii = load_untouch_nii(fname);

   srow_x = nii.hdr.hist.srow_x;
   srow_y = nii.hdr.hist.srow_y;   
   srow_z = nii.hdr.hist.srow_z;

   if srow_x(1) < 0
      nii.img = flipdim(nii.img, 1);
   end;

   if srow_y(2) < 0
      fprintf('%s srow_y %f %f %f\n', fname, srow_y(1), srow_y(2), srow_y(3));
      pause;
   end;

   if srow_z(2)<0
      fprintf('%s srow_z %f %f %f\n', fname, srow_z(1), srow_z(2), srow_z(3));
      pause;
   end;




