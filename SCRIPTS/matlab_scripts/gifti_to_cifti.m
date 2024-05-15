function [ cifti ] = gifti_to_cifti( LH_gii, RH_gii, Cifti_template )
%converts a left and right hemisphere gifti to a cifti. Requires either the
%brainstructure part of the cifti structure or the cifti structure itself.

    cifti = [];

    if(isstruct(Cifti_template))
        brainstructure = Cifti_template.brainstructure(1:(length(LH_gii) + length(RH_gii)));
    else
        brainstructure = Cifti_template(1:(length(LH_gii) + length(RH_gii)));
    end

    gii_brain = [LH_gii;RH_gii];

    cifti = gii_brain(brainstructure ~= -1);
    
    if(isstruct(Cifti_template))
        Cifti_template.data(1:length(cifti)) = cifti;
        cifti = Cifti_template;
    end
end

