function write_back(stat,OutputImage,mask,threshold)
stat_img=single(zeros(length(mask),1));
maskmat=find(mask>=threshold);
for i=1:length(maskmat)
    stat_img(maskmat(i))=stat(i);
end
write_4dfpimg(stat_img,OutputImage,'littleendian')
write_4dfpifh(OutputImage,1,'littleendian')

end