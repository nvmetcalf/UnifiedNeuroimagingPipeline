function addmask(sub_list,Study)
mask = '/data/nil-bluearc/corbetta/Studies/DysFC/ROIs/N21_aparc+aseg+GMctx_711-2V_333_avg_pos_mask_t0.3_symmetric.4dfp.img';        

num_voxels=38070;
fid=fopen(sub_list,'r');
C=textscan(fid,'%s %s %n %n %c %c','HeaderLines',1);
fclose(fid);

for i=1:length(C{1,1})
   C{1,1}{i,1}
   SubjOutput=[ '/scratch/' Study '/' C{1,1}{i,1} '/0.3symmetric_RawData.mat'];
   save(SubjOutput,'num_voxels','-append');
end

% fid=fopen(sub_list,'r');
% C=textscan(fid,'%s %s %n %n %c %c %c','HeaderLines',1);
% fclose(fid);
% tic
% for i=1:length(C{1,1})
%    C{1,1}{i,1}
%         SubjOutput=[ '/scratch/' Study '/' C{1,1}{i,1} '/0.3symmetric_RawData.mat'];
%         load(SubjOutput);
%         CorVector=int8(CorVector*100);
%         save(SubjOutput,'CorVector','mask','frames','DDATcut','num_voxels','Age','threshold','-v7.3');
%         toc
% end

end
