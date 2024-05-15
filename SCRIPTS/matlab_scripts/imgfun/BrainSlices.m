function BrainSlices( stat_img,range,outfile)
%BRAINSLICES Takes a 3x3x3 vector (147456x1) and makes a simple 
%   image of values in a brain-masked 3D image.
%
% Optional inputs: 
%   outfile - if you want an image to be saved, just provide the name of
%   the output image here
% This requires the 'Panels' matlab scripts (they can be downloaded online)
%
% Josh Siegel, 2016 (c)

figure1 = figure;
set(figure1,'Color',[1 1 1])
set(figure1,'Position',[1 100 1000 500])
p = panel();
p.pack(2,6);
if ndims(stat_img)==2
    img3d = reshape(stat_img,48,64,48);
else
    img3d = stat_img;
end
wb=read_4dfp_img('/data/nil-bluearc/corbetta/ATLAS/TRIO_STROKE_NDC/glm_atlas_mask_333_b100.4dfp.img');
wb=wb.voxel_data;wb = double(wb>0.5);
posmask = reshape(wb,48,64,48);
s=1;axis off
for i = 1:2
    for j = 1:6
        p(i,j).select();
        c = flipdim(squeeze(img3d(:,:,s*3+9))',1);c = flipdim(c,2);
        m = flipdim(squeeze(posmask(:,:,s*3+9))',1);m = flipdim(m,2);
        imagesc(c,'AlphaData',m);
        
        if exist('range','var')
            caxis(range)
        else
            caxis([-max(abs(stat_img)) max(abs(stat_img))])
        end
        colormap('jet');
        axis off
        axis([0 48 0 64])
        s=s+1;
    end
end
p.de.margin = 5;
colorbar('East');
if ~isempty(range)
    caxis(range)
else
    caxis([-max(abs(stat_img)) max(abs(stat_img))])
end
set(gcf,'color',[1 1 1])


if exist('outfile','var')
    set(figure1,'PaperPositionMode','auto')
    saveas(figure1,outfile,'jpg')
end

end

