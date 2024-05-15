function write333nii( data,name )
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here
img3d=reshape(data,48,64,48);
x=load_nii('/Applications/workbench/HCP_WB_Tutorial_Beta0.82/MNITemplate/template.nii');
x.img=img3d;
x.img=flipdim(x.img,1);
x.img=flipdim(x.img,2);
save_nii(x,[name '.nii']) 

end

