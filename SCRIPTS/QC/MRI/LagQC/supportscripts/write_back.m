function write_back(stat,OutputImage,mask,threshold,varargin)

frames=size(stat,2);
stat_img=single(zeros(length(mask),frames));
if (nargin > 4)
    stat_img=nan(length(mask),frames);
end
maskmat=find(mask>=threshold);
for i=1:length(maskmat)
    stat_img(maskmat(i),:)=stat(i,:);
end
write_4dfpimg(stat_img,OutputImage,'littleendian')
write_4dfpifh(OutputImage,frames,'littleendian')

end