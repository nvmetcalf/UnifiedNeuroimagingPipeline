function [ nwmat ] = GLrsnFC( GLmat )
%GLrsnFC Converts a 324x324 matrix in to 13x13 RSN-wise matrix
%   Detailed explanation goes here
nwmat=nan(13);
load('/data/nil-bluearc/corbetta/PP_SCRIPTS/Parcellation/GLParcels/reordered/GLParcels_324_reordered.mat');
GLmat = squeeze(GLmat);
if ~size(GLmat,1)==size(GLmat,2)
    GLmat = squareform(GLmat);
end

for i=1:13
    in = GL.Community_n == i;
    for j =1:13
        out = GL.Community_n == j;
        inout = double(in)*double(out)';
        nwmat(i,j)=nanmean(GLmat(find(inout)));
    end
end

end

