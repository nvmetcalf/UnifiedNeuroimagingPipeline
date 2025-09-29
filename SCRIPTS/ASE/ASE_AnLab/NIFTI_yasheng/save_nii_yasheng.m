function save_nii_yasheng(im, px, py, pz, data_type, name_out)


   nii = make_nii(im, [px py pz], [0 0 0], data_type);

   nii.hdr.dime.scl_slope=1;
   nii.hdr.dime.scl_inter=0;

   nii.hdr.dime.pixdim(1) = 1;

   nii.hdr.hist.srow_x=[px 0 0 0];
   nii.hdr.hist.srow_y=[0 py 0 0];
   nii.hdr.hist.srow_z=[0 0 pz 0];

   nii.hdr.hist.qform_code=0;
   nii.hdr.hist.sform_code=0;

   nii.hdr.hist.quatern_b=0;
   nii.hdr.hist.quatern_c=0;
   nii.hdr.hist.quarern_d=0;

   nii.hdr.qoffset_x = 0;
   nii.hdr.qoffset_y = 0;
   nii.hdr.qoffset_z = 0;



   save_nii(nii, name_out);
