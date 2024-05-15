function save_gii(OutputImage, VertexSpace, varargin)
%save_gii(OutputImage, VertexSpace, Path, varargin)
%   Saves a cifti or two hemisphere gifti arrays to disk
%   OutputImage = root of the image you would like saved. Will have
%                   .L.func.gii and .R.func.gii appended appropriately
%   VertexSpace = number of verticies per hemisphere of your data
%                   Can be '10k', '32k', or '164k'
%   
%   varargin = specify the cifti data array OR the gifti left hemishpere
%                   and/or right hemisphere. To write out a single gifti
%                   hemisphere, use [] in place of the hemisphere you do
%                   not want written.
%               Can have a 3rd arguement that will set the path to the
%               surface templates for the space specified

if(length(varargin) > 3)
    error('Incorrect number of arguements in save_gii!');
end

%name output metric giis
if(ischar(VertexSpace))
    LOutputImage = [OutputImage '.L.' VertexSpace '.func.gii'];
    ROutputImage = [OutputImage '.R.' VertexSpace '.func.gii'];
else
    LOutputImage = [OutputImage '.L.' num2str(VertexSpace) 'k.func.gii'];
    ROutputImage = [OutputImage '.R.' num2str(VertexSpace) 'k.func.gii'];
end

if(length(varargin) == 3)
    Path = varargin(3);
else
    Path = [getenv('PP_SCRIPTS') '/GiiTemplates'];
end

disp(['Vertex space template path: ' Path]);

% load shape files to go from cii to gii
switch(VertexSpace)
    case 10
        Lshape = [ Path '/TEMPLATE.L.atlasroi.10k_fs_LR.shape.gii'];
        Rshape = [ Path '/TEMPLATE.R.atlasroi.10k_fs_LR.shape.gii'];
    case 32
        Lshape = [ Path '/TEMPLATE.L.atlasroi.32k_fs_LR.shape.gii'];
        Rshape = [ Path '/TEMPLATE.R.atlasroi.32k_fs_LR.shape.gii'];
    case 164
        Lshape = [ Path '/TEMPLATE.L.atlasroi.164k_fs_LR.shape.gii'];
        Rshape = [ Path '/TEMPLATE.R.atlasroi.164k_fs_LR.shape.gii'];
    case '10k'
        Lshape = [ Path '/TEMPLATE.L.atlasroi.10k_fs_LR.shape.gii'];
        Rshape = [ Path '/TEMPLATE.R.atlasroi.10k_fs_LR.shape.gii'];
    case '32k'
        Lshape = [ Path '/TEMPLATE.L.atlasroi.32k_fs_LR.shape.gii'];
        Rshape = [ Path '/TEMPLATE.R.atlasroi.32k_fs_LR.shape.gii'];
    case '164k'
        Lshape = [ Path '/TEMPLATE.L.atlasroi.164k_fs_LR.shape.gii'];
        Rshape = [ Path '/TEMPLATE.R.atlasroi.164k_fs_LR.shape.gii'];
    otherwise
        error('Unknown Vertex Space specified.');  
end

maskL=gifti(Lshape);
maskR=gifti(Rshape);

if length(varargin)==1 %% input is in cii format
    stat=varargin{1};
    
    [m n]=size(stat);
    
    if (n>m)
        stat=stat';
    end
    
    nmaskL=nnz(maskL.cdata);
    nmaskR=nnz(maskR.cdata);
    VL=zeros(size(maskL.cdata,1),size(stat,2));
    VR=zeros(size(maskR.cdata,1),size(stat,2));
    VL(find(maskL.cdata),:)=stat(1:nmaskL);
    VR(find(maskR.cdata),:)=stat(nmaskL+1:nmaskL+nmaskR);
    x=maskL;
    x.cdata=VL;
    save_gifti(x,LOutputImage)
    x=maskR;
    x.cdata=VR;
    save_gifti(x,ROutputImage)
elseif length(varargin)>1 %% input is in gii format
    if(~isempty(varargin{1}))
        [m n]=size(varargin{1});
    
        if(n>m) 
            varargin{1} = varargin{1}'; 
        end
        
        x = maskL;
        x.cdata=varargin{1};
        save_gifti(x,LOutputImage)
    else
        x = maskL;
%         x.cdata = zeros(length(x.cdata))';
        x.cdata = zeros(size(x.cdata));
        save_gifti(x,LOutputImage);
    end
    
    if(~isempty(varargin{2}))
        [m n] = size(varargin{2});
        
        if(n>m)
            varargin{2} = varargin{2}'; 
        end
   
        x = maskR;
        x.cdata=varargin{2};
        save_gifti(x,ROutputImage)
    else
        x = maskR;
%         x.cdata(1, 1:length(x.cdata)) = 0;
        x.cdata = zeros(size(x.cdata));
        save_gifti(x,ROutputImage);
    
    end
end