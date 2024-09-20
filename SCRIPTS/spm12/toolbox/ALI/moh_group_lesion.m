function [FL,BL,CL,Fcardinality,Binary]=moh_group_lesion(outliers,thr_U,thr_size)
% function to group outliers (across tissue images) 
% and generate binary/contour images
% input:
% -------
%   outliers: volumes coding outliers in different tissue images
%   thr_U: threshold for the degree of abnormality (binarisation)
%   thr_size: thershold for the minimum size of lesions
% output:
% -------
%   FL: fuzzy lesion (continuous abnormal/outlier values)
%   BL: binary lesion at a given threshold
%   CL: contour of the binary lesion
%   Fcardinality and Binary: structure that contains details 
%                            about the volume of lesions
%
% ----------------------------
% Mohamed Seghier, 27.10.2008
%

if ~isstruct(outliers), outliers = spm_vol(outliers) ; end

connectivity = 18 ; % 18-connected neighborhood in 3D
morpho_se = reshape(...
    [[0 1 0; 1 1 1; 0 1 0];ones(3,3);[0 1 0; 1 1 1; 0 1 0]], 3,3,3) ;

im = spm_read_vols(outliers) ;

% the fuzzy lesion
if length(size(im)) == 4
    FL = max(im, [], 4) ;
elseif length(size(im)) == 3
    FL = im;
end

% the binary lesion
BL = FL > thr_U ;

% remove tiny/small lesions
[BL_labeled,nbles] = spm_bwlabel(1*BL, connectivity) ;
for ss=1:nbles
    if nnz(BL_labeled == ss) < thr_size
        BL(BL_labeled == ss) = 0 ;
    end
end

% lesion contour (external contour)
CL = spm_dilate(1*BL, morpho_se) - BL ;


% write a strcture with all volumetric info
% with fuzzy cardinality (approx.)
% Fcardinality.GM = sum(imG(:)) ;
% Fcardinality.WM = sum(imW(:)) ;
Fcardinality = sum(FL(:)) ;

% with the binary volume (also works with multi-lesions)
[mask_labeled, sublesions] = spm_bwlabel(1*BL,connectivity) ;
Binary.voxels(1)=0; Binary.cm3(1)=0; Binary.centre{1}=[0 0 0];
for j=1:sublesions
    Binary.voxels(j) = nnz(mask_labeled == j) ;
    Binary.cm3(j) = nnz(mask_labeled == j) * ...
        prod(abs(diag(outliers(1).mat(1:3,1:3)))) / 1000 ;
    [xx yy zz] = ind2sub(outliers(1).dim, find(mask_labeled == j)) ;
    Binary.centre{j} = (mean([xx yy zz]) .* ...
        diag(outliers(1).mat(1:3,1:3))') + outliers(1).mat(1:3,4)';

end


return ;

