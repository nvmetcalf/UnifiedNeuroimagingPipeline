function [pc , c , T] = rbv( pet , roi , fwhm , path , normroi)
%function [pc , c , T ] = rbv( pet , roi , fwhm , path , normroi )
%   This function implementes rbv correction as described in Thomas et al 2011,
%   Eur J Nucl Med Mol Imaging, 38(6): 1104-19.  There is one important
%   modification: GTM is replaced by sGTM.
%
%   Inputs - 
%   pet - file name of PET image (4dfp, no suffix)
%   roi - file name of ROI image. Single volume with value indexing region.
%       0 is not modeled.(4dfp, no suffix)
%   fwhm - resolution of the gaussian blur in mm
%   path - (optional) path to where the MATLAB 4dfp tools live.  Default is AT's bin
%   normroi - (optional) an ROI image to normalize to (e.g., for SUVR
%       calculation)
%   
%   Outputs - 
%   pc - the RBV corrected image
%   c - condition number of matrix Omega (the only inversion step)
%   T - sGTM corrected ROI estimates

% Adding path to 4DFP tools
% if nargin > 3 & not(isempty(path))
%     addpath(path);
% else
%     addpath(genpath('/data/jsp/human2/fcMRI/Aaron/MATLAB2017a'))
% end

% Error checking files names to make sure they exist
if exist([pet '.4dfp.img'],'file') == 0
    error('PET FILE DOES NOT EXIST');
end
if exist([roi '.4dfp.img'],'file') == 0
    error('ROI FILE DOES NOT EXIST');
end

% Load images into memory, in 3D mode so blurring can happen
p = read_4dfp_img([pet '.4dfp.img'],'3D');
r = read_4dfp_img([roi '.4dfp.img'],'3D');

if nargin == 5
    norm = mean(p.voxel_data(normroi == 1));
    p.voxel_data = p.voxel_data ./ norm;
end

% Check to make sure that pet and roi images are the same size
if sum(size(p.voxel_data) == size(r.voxel_data)) ~= 3
    error ('PET and ROI IMAGE NOT SAME SIZE');
end

% identify the resolution of the images
resolution = p.ifh_info.scaling_factor;

%% sGTM
% identify the labels of the ROI image, ignores 0
rr = unique(r.voxel_data);
rr = rr(rr~=0);

% convert fwhm value to standard deviation (fwhm = 2*sqrt(2 * ln(2))*sigma)
% and account for the resolution of the image
sigma = (fwhm./2.355)./resolution;

% apply gaussian blur to the ROI images and arrange into a voxel by ROI
% matrix
tic
R = zeros(numel(p.voxel_data),length(rr));
for i = 1:length(rr)
    disp(['current sigma region: ' num2str(rr(i))]);
    R(:,i) = reshape(imgaussfilt3(double(logical(r.voxel_data==rr(i))),sigma),[numel(p.voxel_data) 1]);
end
%Elapsed time is 238.224008 seconds.
toc

% calculate omega
tic
Omega = zeros(length(rr),length(rr));
for i = 1:length(rr)
    disp(['current omega region: ' num2str(rr(i))]);
    for j = 1:length(rr)
        Omega(i,j) = sum(R(:,i) .* R(:,j));
    end
end
%3895.604264 seconds
toc
% calculate t
t = sum(reshape(p.voxel_data,[numel(p.voxel_data) 1]) .* R)';

% Apply PVC
T = inv(Omega) * t;
c = cond(Omega);

%% RBV
tic
s = zeros(size(r.voxel_data));
for i = 1:length(T)
    s(r.voxel_data==i) = T(i);
end
toc
pc = p.voxel_data.*(s./imgaussfilt3(s,sigma));


end

