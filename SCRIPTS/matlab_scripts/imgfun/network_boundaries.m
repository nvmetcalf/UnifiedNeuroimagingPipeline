%% network boundaries
% boundaries and network names

nw_b=[1 13 30 54 79 94 100 114 127 139 170]; %network boundaries
nw_n={'Vnf' 'Vnp' 'Dan' 'Mot' 'Aud' 'Con' 'Van' 'Lan' 'Fpn' 'Dmn'}; %network names %
nw_n_lr = { 'Vnf_l', 'Vnf_r', 'Vnp_l', 'Vnp_r',  'Dan_l', 'Dan_r', 'Mot_l','Mot_r', 'Aud_l','Aud_r', 'Con_l','Con_r', 'Van_l', 'Van_r','Lan_l', 'Lan_r','Fpn_l','Fpn_r', 'Dmn_l', 'Dmn_r'};

nw_c=(nw_b(1:end-1)+nw_b(2:end))/2; %nwcenters
nw_l=nw_b(2:end)-0.5; %to make lines

    Dan_l=[30 41]; Dan_r=[42 53];
    Van_l=[100 103]; Van_r=[104 113];
    Vnp_l=[13 20]; Vnp_r=[21 29];
    Vnf_l=[1 3]; Vnf_r=[4 12];
    Dmn_l=[149 160]; Dmn_r=[161 169]; %middle = 139:148
    Mot_l=[55 68]; Mot_r=[69 78]; % middle = 54
    Fpn_l=[128 133]; Fpn_r=[134 138]; %middle = 127
    Con_l=[95 96]; Con_r=[97 99]; %middle = 94
    Lan_l=[114 122]; Lan_r=[123 126];
    Aud_l=[79 86]; Aud_r=[87 93];

    bound_lr_nw=[Vnf_l Vnf_r Vnp_l Vnp_r Dan_l Dan_r Mot_l Mot_r Aud_l Aud_r Con_l ...
        Con_r Van_l Van_r Lan_l Lan_r Fpn_l Fpn_r Dmn_l Dmn_r];
    bound_lr_het=[Vnf_r Vnf_l Vnp_r Vnp_l Dan_r Dan_l Mot_r Mot_l Aud_r Aud_l Con_r ...
        Con_l Van_r Van_l Lan_r Lan_l Fpn_r Fpn_l Dmn_r Dmn_l];
    
    
    for i=1:length(nw_n)
        bald_nw(nw_b(i):(nw_b(i+1)-1)) = i;
    end
    
 %% YEO PARCELLATION
 load('YeoParc169.mat')
 
 %% Hacker Networks - NEEDS CLARIFICATION FROM CARL
% Here is the conversion from Anto's 10 to 7. Basically its just lumping 
% networks based on [1-10] net IDs in that "final.mat," but also indexing 
% this back into coords labels, etc from Anto.

% hacker_n = {'DAN' 'VAN' 'SMN' 'VIS' 'FPN' 'LAN' 'DMN'};
% network_labels={'dat' 'vat' 'vis' 'fovea' 'def' 'mot' 'fpctl' 'coctl' 'lan' 'aud'};
% 
% [networks,net_ids,labels,coordinates] = Parse_ROI_List_Anto('all_netws_new_van_dan_o6_d12.txt',network_labels);
% s=load('/Users/jssiegel/Dropbox/strokelearning/scripts/imgfun/net_ids_z2_newVAN_DAN_d12_final.mat');net_ids=s.net_ids;
% 
% % Set up for 7 networks
% net_ids(net_ids==3)=4;
% net_ids(net_ids==6)=3;
% net_ids(net_ids==10)=3;
% net_ids(net_ids==5)=111;
% net_ids(net_ids==7)=5;
% net_ids(net_ids==8)=0;
% net_ids(net_ids==111)=7;
% net_ids(net_ids==9)=6;
% 
% rmd = find(net_ids==0);
% coordinates(rmd,:) = [];
% net_ids(rmd) = [];
% labels(rmd) = [];
% networks(rmd) = [];
% 
fid = fopen('/Users/jssiegel/Dropbox/StrokeLearning/scripts/imgfun/Corbetta169.txt');
s=textscan(fid,'%f %f %f %f %s');
coordinates(:,1)=s{2};
coordinates(:,2)=s{3};
coordinates(:,3)=s{4};
% fclose('all')
% rr = s{2}.*s{3}.*s{4};
% found = zeros(169,1);
% for i=1:169
%     %row = 0;
%     %row = strmatch(labels{i},s{5});
%     %if isempty(row)
%     for j=1:169
%         if s{2}(j)==coordinates(i,1) && s{3}(j)==coordinates(i,2) && s{4}(j)==coordinates(i,3)
%             row = j;
%             found(i)=1;
%         end
%         pdist([]);
%     end
%      %   ss = coordinates(i,1)*coordinates(i,2)*coordinates(i,3);
%      %   row = find(ss==rr);
%     %end
%     hacker_nw(row)=net_ids(i);
% end
%% Just use baldassarre networks
hacker_nw=bald_nw;
hacker_nw(hacker_nw>1)=hacker_nw(hacker_nw>1)-1;
hacker_nw(hacker_nw>3)=hacker_nw(hacker_nw>3)-1;
hacker_nw(hacker_nw>4)=hacker_nw(hacker_nw>4)-1;
hacker_n = {'VIS' 'DAN' 'MOT' 'VAN' 'LAN' 'FPN' 'DMN'}; %network names %
hacker_n_s = {'L Vis' 'R Vis' 'L Dan' 'R Dan' 'L Mot' 'R Mot' 'L Van' 'R Van' 'L Lan' 'R Lan' 'L Fpn' 'R Fpn' 'L Dmn' 'R Dmn'}; %network names %

hacker_nw_s=hacker_nw;
hacker_nw_s(side<0)=hacker_nw(side<0)-0.5;
hacker_nw_s=hacker_nw_s*2;
    
    % %Resort by new network blocks:
% [c,ind]=sort((net_ids));
% coordinates=coordinates(ind,:);
% net_ids=net_ids(ind);
 
%% HOMOTOPIC PAIRS
Homo(1,:)=[1 2 3 14 20 16 19 31 32 34 35 38 40 41 37 39 61 56 55 58 64 67 68 84 83 82 81 96 95 103 101 115 116 122 121 132 133 129 130 131 151 159 157 156 154 155 160];
Homo(2,:)=[7 5 11 23 24 29 26 43 44 45 46 47 50 51 48 53 74 69 71 72 76 77 78 93 90 91 88 99 98 112 108 123 124 126 125 137 138 134 135 136 162 168 167 166 163 165 169];

% Baldassarre networks
Homotopic(1).name='Vnf';
Homotopic(1).L=[1 2 3];
Homotopic(1).R=[7 11 5];

Homotopic(2).name='Vnp';
Homotopic(2).L=[13 14 20 16 19];
Homotopic(2).R=[26 23 24 29 22];

Homotopic(3).name='Dan';
Homotopic(3).L=[31 32 34 35 38 40 41 37 39];
Homotopic(3).R=[43 44 45 46 47 50 51 48 53];

Homotopic(4).name='Mot';
Homotopic(4).L=[61 56 55 58 64 67 68];
Homotopic(4).R=[74 69 71 72 76 77 78];

Homotopic(5).name='Aud';
Homotopic(5).L=[84 83 82 81];
Homotopic(5).R=[93 90 91 88];

Homotopic(6).name='Con';
Homotopic(6).L=[96 95];
Homotopic(6).R=[99 98];

Homotopic(7).name='Van';
Homotopic(7).L=[103 101];
Homotopic(7).R=[112 108];

Homotopic(8).name='Lan';
Homotopic(8).L=[115 116 122 121];
Homotopic(8).R=[123 124 126 125];

Homotopic(9).name='Fpn';
Homotopic(9).L=[132 133 129 130 131];
Homotopic(9).R=[137 138 134 135 136];

Homotopic(10).name='Dmn';
Homotopic(10).L=[151 159 157 157 154 155 160];
Homotopic(10).R=[162 168 167 166 163 165 169];