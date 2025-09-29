
function nii_out = generate_nifti_with_updated_image(nii, img, px, py, pz, datatype, bitpix, sign_keepscale)

   nii_out = nii;
   px_orig = nii_out.hdr.dime.pixdim(2);
   py_orig = nii_out.hdr.dime.pixdim(3);
   pz_orig = nii_out.hdr.dime.pixdim(4);

   nii_out.hdr.dime.pixdim(2)=px;
   nii_out.hdr.dime.pixdim(3)=py;
   nii_out.hdr.dime.pixdim(4)=pz;

   nii_out.hdr.dime.dim(2) = size(img, 1);
   nii_out.hdr.dime.dim(3) = size(img, 2);
   nii_out.hdr.dime.dim(4) = size(img, 3);

   mat_org = zeros(3,3);
   mat_new = zeros(3,3);
   mat_scale = zeros(3,3);

   mat_org(1,1:3) = nii.hdr.hist.srow_x(1:3);
   mat_org(2,1:3) = nii.hdr.hist.srow_y(1:3);
   mat_org(3,1:3) = nii.hdr.hist.srow_z(1:3);

   mat_scale(1,1) = px/px_orig;
   mat_scale(2,2) = py/py_orig;
   mat_scale(3,3) = pz/pz_orig;

   mat_new = mat_org*mat_scale;

   [dimx, dimy, dimz] = size(nii.img);
   [dimx_out, dimy_out, dimz_out]=size(img);

   dx = (dimx_out-dimx)/2*px;
   dy = (dimy_out-dimy)/2*py;
   dz = (dimz_out-dimz)/2*pz;

   nii_out.hdr.hist.srow_x(1:3) = mat_new(1,1:3);
   nii_out.hdr.hist.srow_y(1:3) = mat_new(2,1:3);
   nii_out.hdr.hist.srow_z(1:3) = mat_new(3,1:3);

   nii_out.hdr.hist.qoffset_x = nii_out.hdr.hist.qoffset_x + dx;
   nii_out.hdr.hist.qoffset_y = nii_out.hdr.hist.qoffset_y + dy;
   nii_out.hdr.hist.qoffset_z = nii_out.hdr.hist.qoffset_z + dz;

   nii_out.hdr.hist.srow_x(4) = nii_out.hdr.hist.qoffset_x;
   nii_out.hdr.hist.srow_y(4) = nii_out.hdr.hist.qoffset_y;
   nii_out.hdr.hist.srow_z(4) = nii_out.hdr.hist.qoffset_z;

   if sign_keepscale == 0
      nii_out.hdr.dime.scl_slope = 1;
      nii_out.hdr.dime.scl_inter = 0;
   end;
 
   if datatype ==0 | bitpix == 0
      datatype = nii.hdr.dime.datatype;
      bitpix = nii.hdr.dime.bitpix;
   else
      nii_out.hdr.dime.datatype = datatype;
      nii_out.hdr.dime.bitpix = bitpix;
   end;

   if datatype == 2 & bitpix == 8
      nii_out.img = int8(img);
   end;

   %%%4 and 16 for most images with unsigned short
   if datatype == 4 & bitpix == 16
      nii_out.img = int16(img);
   end;

   %%%16 and 32 for images with single float
   if datatype == 16 & bitpix == 32
      nii_out.img = single(img);
   end;

   %%%64 and 64 for images with double float
   if datatype == 64 & bitpix == 64
      nii_out.img = double(img);
   end;
         
 %     1 Binary                         (ubit1, bitpix=1) % DT_BINARY 
%     2 Unsigned char         (uchar or uint8, bitpix=8) % DT_UINT8, NIFTI_TYPE_UINT8 
%     4 Signed short                  (int16, bitpix=16) % DT_INT16, NIFTI_TYPE_INT16 
%     8 Signed integer                (int32, bitpix=32) % DT_INT32, NIFTI_TYPE_INT32 
%    16 Floating point    (single or float32, bitpix=32) % DT_FLOAT32, NIFTI_TYPE_FLOAT32 
%    32 Complex, 2 float32      (Use float32, bitpix=64) % DT_COMPLEX64, NIFTI_TYPE_COMPLEX64
%    64 Double precision  (double or float64, bitpix=64) % DT_FLOAT64, NIFTI_TYPE_FLOAT64 
%   128 uint RGB                  (Use uint8, bitpix=24) % DT_RGB24, NIFTI_TYPE_RGB24 
%   256 Signed char            (schar or int8, bitpix=8) % DT_INT8, NIFTI_TYPE_INT8 
%   511 Single RGB              (Use float32, bitpix=96) % DT_RGB96, NIFTI_TYPE_RGB96
%   512 Unsigned short               (uint16, bitpix=16) % DT_UNINT16, NIFTI_TYPE_UNINT16 
%   768 Unsigned integer             (uint32, bitpix=32) % DT_UNINT32, NIFTI_TYPE_UNINT32 
%  1024 Signed long long              (int64, bitpix=64) % DT_INT64, NIFTI_TYPE_INT64
%  1280 Unsigned long long           (uint64, bitpix=64) % DT_UINT64, NIFTI_TYPE_UINT64 
%  1536 Long double, float128  (Unsupported, bitpix=128) % DT_FLOAT128, NIFTI_TYPE_FLOAT128 
%  1792 Complex128, 2 float64  (Use float64, bitpix=128) % DT_COMPLEX128, NIFTI_TYPE_COMPLEX128 
%  2048 Complex256, 2 float128 (Unsupported, bitpix=256) % DT_COMPLEX128, NIFTI_TYPE_COMPLEX128   
