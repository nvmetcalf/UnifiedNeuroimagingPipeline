function [networks,net_ids,labels,coordinates]=Parse_ROI_List_Anto(infile,net_labels)
fid = fopen(infile);
%s= textscan(fid,'%s %s %s %s %s','delimiter','_')
s=textscan(fid,'%f %f %f %s %s');
fclose('all');

networks=s{5};
labels=s{4};

coordinates=[s{1} s{2} s{3}];

for i = 1:length(net_labels)
    net_id_binary(:,i)=~cellfun(@isempty,strfind(networks,net_labels{i}));
end
[c,net_ids]=max(net_id_binary');
net_ids=net_ids';
