function  Project324( X,resultname)
%UNTITLED3 Summary of this function goes here
%   Detailed explanation goes here
cii=ft_read_cifti_mod('supportfunctions/GLParcels/GLParcels_324_reordered.32k.dlabel.nii');
ROIinds = cii.data;
Prc = prctile(1:size(X,1),[25,75]);
for i=1:size(X,1)
    sorti = sort(X(:,i));
    sortipos=sorti;
    sortipos(sorti<0)=nan;
    sortineg=sorti;
    sortineg(sorti>0)=nan;
    proj_hi25(i) = nanmean(sortipos(ceil(Prc(2)):end));
    proj_lo25(i) = nanmean(sortineg(1:floor(Prc(1))));
end
template_pos = zeros(size(cii.data));
template_neg = zeros(size(cii.data));
for i=1:324
    template_pos(ROIinds == i) = proj_hi25(i);
    template_neg(ROIinds == i) = proj_lo25(i);
end
cii.data = [template_pos template_neg];
cii.mapname = {'Pos','Neg'};
ft_write_cifti_mod([resultname '.dscalar.nii'],cii)
end

