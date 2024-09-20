function [netmat,names]=ROItoNetworks(corrmat,parcel)
%ROItoNetwork goes for 169x169 to MxM based on a M-network that the ROIs 
% have previously been assigned to.

network_boundaries
switch parcel 
    case 'yeo'
        names=yeo_n_s;
            z=1;
            for i=1:12
                for j=i:12
                con=squeeze(corrmat(yeo_nw_s==i,yeo_nw_s==j));
                if i==j
                    con=ExtractDataAboveDiagonal(con);
                end             
                netmat(z)=mean(mean(con));
                z=z+1;
            end
            end
        end
        
end



