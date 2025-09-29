%% Subroutine for T1 segmentation with spm
%% AnLab 2025/04/14

function run_t1_process_2_spm_seg(name_dir_t1, nnn)

   name_dir_seg = sprintf('%s/spm_seg', name_dir_t1);

   if ~exist(name_dir_seg)
      mkdir(name_dir_seg);
   end; 

   name_in = sprintf('%s/%s_t1.nii.gz', name_dir_t1, nnn);
   name_out = sprintf('%s/%s_t1.nii.gz', name_dir_seg, nnn);

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   %%%resave adni t1
   nii = load_untouch_nii(name_in);
   px = nii.hdr.dime.pixdim(2);
   py = nii.hdr.dime.pixdim(3);
   pz = nii.hdr.dime.pixdim(4);

   save_nii_yasheng(nii.img, px, py, pz, nii.hdr.dime.datatype, name_out);
      
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   run_spm_seg_brain_mpr_original_header(name_out);

   assign_original_header_to_spm_segmentation(name_dir_t1, nnn);
