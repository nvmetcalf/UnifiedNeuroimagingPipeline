%% Remove the edges between ROIs
clear
parcellation=ft_read_cifti_mod('GLParcels_324_reordered.10k.dlabel.nii');
walls = parcellation.data==0;
parcellation.data(walls)=nan;

% find neighbors
bufsize=16384;
caretdir = '/data/nil-bluearc/corbetta/PP_SCRIPTS/SurfacePipeline/Conte69_10k';
% Read in node neighbor file generated from caret -surface-topology-neighbors
[neighbors(:,1) neighbors(:,2) neighbors(:,3) neighbors(:,4)...
    neighbors(:,5) neighbors(:,6) neighbors(:,7)] = ...
    textread([caretdir '/node_neighbors.txt'],'%u %u %u %u %u %u %u',...
    'delimiter',' ','bufsize',bufsize,'emptyvalue',NaN);
neighbors = neighbors+1;

for i=1:10242
    myval = parcellation.data(i);
    neighborvals = parcellation.data(neighbors(i,~isnan(neighbors(i,:))));
    neighborvals(isnan(neighborvals))=[];
    n = unique(neighborvals);
    if length(n)>1
        LEdge(i)=1;
    end
    
    myval = parcellation.data(i+10242);
    neighborvals = parcellation.data(neighbors(i,~isnan(neighbors(i,:)))+10242);  
    neighborvals(isnan(neighborvals))=[];
    n = unique(neighborvals);
    if length(n)>1
        REdge(i)=1;
    end
end
save_gii('GLParcels_324_reordered_edges','10k',LEdge',REdge')

parcellation.data([LEdge' ; REdge' ]==1)=0;
parcellation.data(walls)=0;
ft_write_cifti_mod('GLParcels_324_reordered_eroded.10k',parcellation)
make_cifti_label('GLParcels_324_reordered_eroded.10k.dscalar.nii')

save_gii('GLParcels_324_reordered_eroded','10k',parcellation.data(1:10242),parcellation.data(10243:end))