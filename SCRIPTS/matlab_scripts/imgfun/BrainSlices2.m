function BrainSlices(ulay,varargin)
%BRAINSLICES Takes a 3x3x3 vector (147456x1) and makes a simple 
%   image of values in a brain-masked 3D image.
%
% Optional inputs: 
%   outfile - if you want an image to be saved, just provide the name of
%   the output image here
% This requires the 'Panels' matlab scripts (they can be downloaded online)
%
%
% Keywords
%    range: set range for overlay color - give range
%    thres: [lower upper] for olay
%     mask: 3D mask applied to olay
%     save: save output image - give name
%     grid: [nrow ncol]
%    alpha: control transparency for overlay
%
%
%
%
% Josh Siegel, 2016 (c)

%% defaults
olay = 0;
olower=0;          % lower threshold for overlay
oupper=0;          % upper threshold for overlay
oalpha=1;          % transparency parameter
ulayrange = [min(ulay(:)) max(ulay(:))];         % underlay range
ucmap='gray';      % colormap for underlay
mask = ones(size(ulay)); % overlay mask
ocmap='y2c';       % coloarmap for overlay (yellow-red-blue-cray)
ocmapni=256;       % number of indices used in the underlay colormap


%% keyword-value pairs
if rem(nargin,2)==1
     kwstart = 1;
%      flag_ocolorbar=0;
%      flag_otextbox=0;
else
     olay=varargin{1};
     range = [min(olay(:)) max(olay(:))];
     if ndims(olay)==4
         olay_data=olay;
         olay=olay(:,:,:,1);
     end
     kwstart = 2;
end

for i=kwstart:2:size(varargin,2)
    Keyword = varargin{i};
    Value   = varargin{i+1};
    if ~ischar(Keyword) 
        printf('BrainSlices(): keywords must be strings')
        return
    end
    if strcmpi(Keyword,'mask')
        mask=Value;
    elseif strcmpi(Keyword,'alpha') || strcmpi(Keyword,'oalpha')
        oalpha=Value;
    elseif strcmpi(Keyword,'thres') || strcmpi(Keyword,'threshold')
        if isnumeric(Value)
            if isscalar(Value)
                olower=-Value;
                oupper=Value;
            else
                olower=Value(1);
                oupper=Value(2);
            end
        end
    elseif strcmpi(Keyword,'range')
        range = Value;
    else
        fprintf(['BrainSlices(): ' Keyword ' is an unknown keyword']);
    end
end


if ndims(olay)==2
    ol_img3d = reshape(olay,48,64,48);
else
    ol_img3d = olay;
end

if ndims(ulay)==2
    ulay = reshape(ulay,48,64,48);
end



% mask olay if a "mask" is provided
if exist('mask','var')
    olay=olay.*(mask>0);
end


figure1 = figure;
set(figure1,'Color',[1 1 1])
set(figure1,'Position',[1 100 1000 500])



p = panel();
p.pack({19/20 []},1)
p(1,1).pack(2,6);
s=1;axis off
for i = 1:2
    for j = 1:6
        p(1,1,i,j).select();
        
        % show underlay
        u = flipdim(ulay(:,:,s*3+9)',1);u = flipdim(u,2);
        imagesc(u);axis off;axis([0 48 0 64])
        colormap(ucmap);
        axis([0 48 0 64])
        hold on
        
        if exist('olay','var')
            % show overlay
            c = flipdim(squeeze(ol_img3d(:,:,s*3+9))',1);c = flipdim(c,2);
            m = flipdim(squeeze(mask(:,:,s*3+9))',1);m = flipdim(m,2);
            m(c>=0 & c<oupper)=0;
            m(c<=0 & c>olower)=0;
            
            
            
            
            oimg=c;
            oclim = range;
            
            if ischar(ocmap)
                if strcmpi(ocmap,'y2c') || strcmpi(ocmap,'yrbc') % yellow-red-blue-cray
                    ocmap=zeros(ocmapni,3);
                    mid=fix(ocmapni/2);
                    ocmap(1:mid,1)=linspace(0,0,mid);
                    ocmap(1:mid,2)=linspace(1,0,mid);
                    ocmap(1:mid,3)=linspace(1,1,mid);
                    ocmap(mid+1:end,1)=linspace(1,1,ocmapni-mid);
                    ocmap(mid+1:end,2)=linspace(0,1,ocmapni-mid);
                    ocmap(mid+1:end,3)=linspace(0,0,ocmapni-mid);
                elseif strcmpi(ocmap,'yrbg')                    % yellow-red-blue-green
                    ocmap=zeros(ocmapni,3);
                    mid=fix(ocmapni/2);
                    ocmap(1:mid,1)=linspace(0,0,mid);
                    ocmap(1:mid,2)=linspace(1,0,mid);
                    ocmap(1:mid,3)=linspace(0,1,mid);
                    ocmap(mid+1:end,1)=linspace(1,1,ocmapni-mid);
                    ocmap(mid+1:end,2)=linspace(0,1,ocmapni-mid);
                    ocmap(mid+1:end,3)=linspace(0,0,ocmapni-mid);
                elseif strcmpi(ocmap,'spectral')
                    ocmap=spectral(ocmapni);
                else
                    ocmap=eval([ocmap '(' num2str(ocmapni) ')']);
                end
            else
                % an N-by-3 matrix can also be loaded as the colormap
                ocmapni=size(ocmap,1);
            end
            ocmap=ocmap/max(ocmap(:));
            
            
            [nx,ny]=size(oimg);
            oimg=oimg(:);
            oimg_index = zeros(size(oimg));
            if length(oclim)==2
                vmin=min(oclim);
                vmax=max(oclim);
                cmin=1;
                cmax=ocmapni;
                now_what=(oimg>vmin&oimg<vmax);
                oimg_index(now_what)=...
                    round((oimg(now_what)-vmin)/(vmax-vmin)*(cmax-cmin)+cmin);
                now_what=oimg<=min(oclim);
                oimg_index(now_what)=1;
                now_what=oimg>=max(oclim);
                oimg_index(now_what)=ocmapni;
            elseif length(oclim)==4
                % negative range
                vmin=oclim(1);
                vmax=oclim(2);
                cmin=1;
                cmax=ocmapni/2;
                now_what=(oimg>vmin&oimg<vmax);
                oimg_index(now_what)=...
                    round((oimg(now_what)-vmin)/(vmax-vmin)*(cmax-cmin)+cmin);
                now_what=(oimg<=vmin);
                oimg_index(now_what)=1;
                now_what=(oimg>=vmax&oimg<=0);
                oimg_index(now_what)=cmax;
                % positive range
                vmin=oclim(3);
                vmax=oclim(4);
                cmin=ocmapni/2+1;
                cmax=ocmapni;
                now_what=(oimg>vmin&oimg<vmax);
                oimg_index(now_what)=...
                    round((oimg(now_what)-vmin)/(vmax-vmin)*(cmax-cmin)+cmin);
                now_what=oimg>=vmax;
                oimg_index(now_what)=cmax;
                now_what=(oimg>0&oimg<vmin);
                oimg_index(now_what)=cmin;
            end
            oimg=oimg_index;
            oimg=reshape(oimg,nx,ny);
            
            
            oimg=ind2rgb(oimg,ocmap);
            
            h_image=image(oimg);
            set(h_image,'AlphaData',m);
            axis([0 48 0 64])
        end
        
        s=s+1;
    end
end
p.de.margin = 5;
p(2,1).select();
o=reshape(ocmap,1,256,3);
image(o)
set(gca,'Xtick',1:20,'XtickLabel',1:20)




if exist('outfile','var')
    set(figure1,'PaperPositionMode','auto')
    saveas(figure1,outfile,'jpg')
end

end

