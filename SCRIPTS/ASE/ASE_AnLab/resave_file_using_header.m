
function resave_file_using_header(name_in, name_out, name_header)

   %%%name_resaved and name_header must have the same dimensions and the same
   %%%voxel size

   nii_header = load_untouch_nii(name_header);
   nii_in = load_untouch_nii(name_in);

   nii_out = nii_header;
   nii_out.img = nii_in.img;

   nii_out.hdr.dime.scl_slope = nii_in.hdr.dime.scl_slope;
   nii_out.hdr.dime.scl_inter = nii_in.hdr.dime.scl_inter;

   nii_out.hdr.dime.datatype = nii_in.hdr.dime.datatype;
   nii_out.hdr.dime.bitpix   = nii_in.hdr.dime.bitpix;

   save_untouch_nii(nii_out, name_out);


