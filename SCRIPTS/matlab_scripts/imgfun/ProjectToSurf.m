function  ProjectToSurf( X,resultname)
%UNTITLED3 Summary of this function goes here
%   Detailed explanation goes here
cii=ft_read_cifti_mod('/Applications/workbench/HCP_WB_Tutorial_Beta0.82/GLParcels/reordered/GLParcels_324_reordered.32k.dlabel.nii');
ROIinds = cii.data;
template_pos = zeros(size(cii.data));
for i=1:324
    template_pos(ROIinds == i) = X(i);
end
cii.data = [template_pos];
cii.mapname = {'Pos','Neg'};
ft_write_cifti_mod([resultname '.dscalar.nii'],cii)
end

