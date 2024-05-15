function plot_fc_matrix(all_FCS,thr)
%% all_FCS=plot_average_fc(FCS_data,thr)
% FCS_data=matrix timepoint x subj x 'x' x 'y'
% thresh = [min max] for colorbar
if ~exist('thr','var')||isempty(thr),
thr=[-1 1];
end

run('/data/nil-bluearc/corbetta/Studies/FCStroke/Analysis/ramseyl/Scripts/Matlab/variables_to_load/network_boundaries.m');
size_f=[1 1 600 500]; %[1 1 1200 1000]; %figure size
%nw_c=(nw_b(1:end-1)+nw_b(2:end))/2; %network centers for labels
%nw_l=nw_b(2:end)-0.5; %network boundaries
if ndims(all_FCS)>2
    error('enter 169x169 or 20x20 matrix')
end

figure;set(gcf,'position',size_f);
imagesc(all_FCS,[thr(1) thr(2)])
colorbar
hold on
if size(all_FCS,1)>100
    for i=1:(length(nw_l)-1), %% to make network lines
        plot([nw_l(i) nw_l(i)],[.5 nw_l(end)+1]);plot([.5 nw_l(end)+1],[nw_l(i) nw_l(i)]);
    end
    hold off
    set(gca,'Ytick',nw_c,'Yticklabel',nw_n)
    set(gca,'Xtick',nw_c,'Xticklabel',nw_n)          
elseif size(all_FCS,1)==20,
    inds = { 'Vnf_l', 'Vnf_r', 'Vnp_l', 'Vnp_r',  'Dan_l', 'Dan_r', 'Mot_l','Mot_r', 'Aud_l','Aud_r', 'Con_l','Con_r', 'Van_l', 'Van_r','Lan_l', 'Lan_r','Fpn_l','Fpn_r', 'Dmn_l', 'Dmn_r'};
    nw_n2=inds;
    hold off
    set(gca,'Ytick',1:length(nw_n2),'Yticklabel',nw_n2)
    set(gca,'Xtick',1.5:2:length(nw_n)*2,'Xticklabel',nw_n)
end

figure;set(gcf,'position',size_f);
imagesc(all_FCS,[thr(1) thr(2)])
load('/data/nil-bluearc/corbetta/Studies/FCStroke/Analysis/ramseyl/Data/colormap_middlegray.mat');
colormap(Colormap_middlegray);
colorbar
hold on
if size(all_FCS,1)>100
    for i=1:(length(nw_l)-1), %% to make network lines
        plot([nw_l(i) nw_l(i)],[.5 nw_l(end)+1]);plot([.5 nw_l(end)+1],[nw_l(i) nw_l(i)]);
    end
    hold off
    set(gca,'Ytick',nw_c,'Yticklabel',nw_n)
    set(gca,'Xtick',nw_c,'Xticklabel',nw_n)   
elseif size(all_FCS,1)==20,
    inds = { 'Vnf_l', 'Vnf_r', 'Vnp_l', 'Vnp_r',  'Dan_l', 'Dan_r', 'Mot_l','Mot_r', 'Aud_l','Aud_r', 'Con_l','Con_r', 'Van_l', 'Van_r','Lan_l', 'Lan_r','Fpn_l','Fpn_r', 'Dmn_l', 'Dmn_r'};
    nw_n2=inds;
    hold off
    set(gca,'Ytick',1:length(nw_n2),'Yticklabel',nw_n2)
    set(gca,'Xtick',1.5:2:length(nw_n)*2,'Xticklabel',nw_n)      
end



%% save
% date_now=datestr(now,'mmddyy');
% savefile=['/home/usr/ramseyl/matlab/results/fcmaps/' date_now '/']
% if isdir(savefile)==0,
%     mkdir(savefile);
% end
% saveas(gcf, strcat(savefile,'FCS_', tp_n{t}, '_Ave_N',num2str(nr_s),'.jpg'))
