%% Subroutine for PVC pipeline

%% History

%% 2022/11/30 Chunwei
    %% Clean up the indentation
%% 2021/04/01 Chunwei
    %% Create file - From Yasheng Chen's code; 
    %% Modidfied for multiple pCASL/ASE per scan


function reg_pv_ants(folder, nnn, name_super, name_out_dir)

name_dir_t1 = sprintf('%s/T1',folder);
name_dir_lesion = sprintf('%s/Reg_to_T1',folder);

% tmp = strsplit(nnn,'_');
% if length(tmp) == 1
%     subjNow_subj = tmp{1};
% else
%     subjNow_subj = [];
%     for ii = 1:length(tmp)-1
%         subjNow_subj = cat(2,subjNow_subj,tmp{ii});
%         if ii~=length(tmp)-1
%             subjNow_subj = cat(2,subjNow_subj,'_');
%         end
%     end
% end

if ~exist(sprintf('%s/%s_t1_brain.nii.gz',name_dir_t1,nnn))
    subjNow_subj = nnn;
end

name_t1 = sprintf('%s/%s_t1_brain.nii.gz', name_dir_t1, subjNow_subj);
name_gm  = sprintf('%s/%s_t1_spm_gm.nii.gz', name_dir_t1, subjNow_subj);
name_wm  = sprintf('%s/%s_t1_spm_wm.nii.gz', name_dir_t1, subjNow_subj);
name_csf = sprintf('%s/%s_t1_spm_csf.nii.gz', name_dir_t1, subjNow_subj);
name_lesion = sprintf('%s/%s_flair_lesion.nii.gz',name_dir_lesion,subjNow_subj);

name_t1_out = sprintf('%s/Super/%s_t1_brain_super.nii.gz', name_out_dir, nnn);
name_gm_out = sprintf('%s/Super/%s_t1_gm_super.nii.gz', name_out_dir, nnn);
name_wm_out = sprintf('%s/Super/%s_t1_wm_super.nii.gz', name_out_dir, nnn);
name_csf_out = sprintf('%s/Super/%s_t1_csf_super.nii.gz', name_out_dir, nnn);
name_lesion_out = sprintf('%s/Super/%s_flair_lesion_super.nii.gz',name_out_dir,subjNow_subj);

name_out_root = sprintf('%s/Super/%s_t12super', name_out_dir, nnn);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ants1 = sprintf('/data/anlab/Yasheng/WMD_updated_pipeline/Code_pipeline/Supporting/antsRegistrationSyNQuick.sh -d 3 -f %s -m %s -o %s', name_super, name_t1, name_out_root);
disp(ants1); system(ants1);

ants2 = sprintf('antsApplyTransforms -d 3 -i %s -o %s -r %s -t %s1Warp.nii.gz -t %s0GenericAffine.mat', name_t1,  name_t1_out,  name_super, name_out_root, name_out_root);
ants3 = sprintf('antsApplyTransforms -d 3 -i %s -o %s -r %s -t %s1Warp.nii.gz -t %s0GenericAffine.mat', name_gm,  name_gm_out,  name_super, name_out_root, name_out_root);
ants4 = sprintf('antsApplyTransforms -d 3 -i %s -o %s -r %s -t %s1Warp.nii.gz -t %s0GenericAffine.mat', name_wm,  name_wm_out,  name_super, name_out_root, name_out_root);
ants5 = sprintf('antsApplyTransforms -d 3 -i %s -o %s -r %s -t %s1Warp.nii.gz -t %s0GenericAffine.mat', name_csf, name_csf_out, name_super, name_out_root, name_out_root);
ants6 = sprintf('antsApplyTransforms -d 3 -i %s -o %s -r %s -t %s1Warp.nii.gz -t %s0GenericAffine.mat', name_lesion, name_lesion_out, name_super, name_out_root, name_out_root);

disp(ants2); system(ants2);
disp(ants3); system(ants3);
disp(ants4); system(ants4);
disp(ants5); system(ants5);

if exist(name_lesion)
    disp(ants6); system(ants6);
end

fslcp2 = sprintf('fslcpgeom %s %s', name_super, name_t1_out);
fslcp3 = sprintf('fslcpgeom %s %s', name_super, name_gm_out);
fslcp4 = sprintf('fslcpgeom %s %s', name_super, name_wm_out);
fslcp5 = sprintf('fslcpgeom %s %s', name_super, name_csf_out);
fslcp6 = sprintf('fslcpgeom %s %s', name_super, name_lesion_out);

disp(fslcp2); system(fslcp2);
disp(fslcp3); system(fslcp3);
disp(fslcp4); system(fslcp4);
disp(fslcp5); system(fslcp5);
if exist(name_lesion_out)
    disp(fslcp6); system(fslcp6);
end



