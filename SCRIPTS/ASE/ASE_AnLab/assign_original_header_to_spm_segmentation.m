%% Subroutine for copying original T1 headers to the segmentation maps
%% AnLab 2025/04/14

function assign_original_header_to_spm_segmentation(name_dir_t1, nnn)

   name_ext{1} = 'brain';
   name_ext{2} = 'brain_mask';
   name_ext{3} = 'spm_csf';
   name_ext{4} = 'spm_wm';
   name_ext{5} = 'spm_gm';
   
   num_ext = length(name_ext);

   name_dir_spm= sprintf('%s/spm_seg', name_dir_t1);

   name_t1 = sprintf('%s/%s_t1.nii.gz', name_dir_t1, nnn);

   for j=1:num_ext,
      name_spm = sprintf('%s/%s_t1_%s.nii.gz', name_dir_spm, nnn, name_ext{j});
      name_out = sprintf('%s/%s_t1_%s.nii.gz', name_dir_t1,  nnn, name_ext{j});

      if exist(name_out)
         continue;
      end;

      cp = sprintf('cp %s %s', name_spm, name_out);
      disp(cp);
      system(cp);
      
      if exist('/usr/local/pkg/fsl5.0.11/bin/fslcpgeom')
         fsl = sprintf('/usr/local/pkg/fsl5.0.11/bin/fslcpgeom %s %s', name_t1, name_out);
      else
         fsl = sprintf('fslcpgeom %s %s', name_t1, name_out);
      end;
            
      disp(fsl);
      system(fsl);

      clear name_spm name_out cp fsl;
   end;
   
   clear name_ext name_dir_spm name_t1;

