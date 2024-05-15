function write_back(stat,OutputImage,mask,threshold)

if ~strcmp(OutputImage((end-2):end),'img')
    OutputImage = [OutputImage '.4dfp.img'];
end

if nargin > 2
stat_img=single(zeros(length(mask),1));
maskmat=find(mask>=threshold);
for i=1:length(maskmat)
    stat_img(maskmat(i))=stat(i);
end
else
    stat_img = stat;
end
write_4dfpimg(stat_img,OutputImage,'littleendian')
write_4dfpifh(OutputImage,1,'littleendian')

end