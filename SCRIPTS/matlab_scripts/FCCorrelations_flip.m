function FCCorrelations_flip(sub_list,masktype,varargin)
% Uses Gagans read_4dfpimg.m script to load 4dfp data into matlab for a
% list of subjects and create mat files in each subjects directory.
% Run from inside Study folder
% Study: name of the directory to which you propagated scans
% mask: 'graymatter' or 'wholebrain' or 'basalganglia' or '0.3symmetric'
% varargin: DDATcut. DDAT threshold requires hat "P2 -D" was run. 
% FCCorrelations_flip('Control_List.txt','wholebrain')
tic
% OTHER IMPORTANT VARIABLES:
DDATcut='none';
if length(varargin)>0
    DDATcut=varargin{1};
end
[~,Study,~]=fileparts(pwd);
OverwriteMatrices = 1; % set to 1 if you want to overwrite correl matrices for subjects that already have a RawData.mat file
fid=fopen(sub_list,'r');
C=textscan(fid,'%s %s %n %n %c %c %c','HeaderLines',1);
fclose(fid);
threshold=1;
switch masktype
    case 'graymatter'
        mask = read_4dfpimg('/data/nil-bluearc/corbetta/Hacker/ROIs/Cortex_Mask_20k/N21_aparc+aseg_GMctx_on_711-2V_333_avg.4dfp.img');
        threshold=0.3;
    case 'wholebrain'
        mask = read_4dfpimg('/data/petsun43/data1/atlas/glm_atlas_mask_333_b100.4dfp.img');
    case 'basalganglia'        
        mask = read_4dfpimg('/data/nil-bluearc/corbetta/Studies/Functional_Connectivity_Stroke_R01_HD061117-05A2/Analysis/callejasa/FC_Basal_Ganglia_Patients/ROIs_Barnes5n2ndry/DCsum_ROI333.4dfp.img');
    case '0.3symmetric'
        mask = read_4dfpimg('/data/nil-bluearc/corbetta/Studies/DysFC/ROIs/N21_aparc+aseg+GMctx_711-2V_333_avg_pos_mask_t0.3_symmetric.4dfp.img');        
end
num_voxels=int32(sum(mask>=threshold));

for i=1:length(C{1,1}) % Load data, create correlation matrix, save to scratch
    C{1,1}{i,1}
    Age = C{1,4}(i,1);
    SubjOutputDir=[ '/scratch/' Study '/' C{1,1}{i,1}];
    if C{1,7}(i,1)=='R'
        Output = ([ SubjOutputDir '/' masktype '_RawData_flip.mat']);
    else
        Output = ([ SubjOutputDir '/' masktype '_RawData.mat']);
    end
    if exist(Output,'file') && OverwriteMatrices==0
        disp('Correlation matrix already exists. Skip subject');
    else
        mkdir(SubjOutputDir);
        FullData=[];
        runs=0;
        root = [ '/data/nil-bluearc/corbetta/Studies/' Study ];
        if C{1,7}(i,1)=='R'
            for j=1:8;
                img = [ C{1,1}{i,1} '/bold' num2str(j) '/' C{1,1}{i,1} '_b' num2str(j) '_faln_dbnd_xr3d_atl_g7_bpss_resid' ];
                subimg = [ root '/Subjects/' img ];
                if exist([subimg '.4dfp.img'],'file')                    
                    system(['flip_4dfp -x ' subimg ' ' subimg '_flip'])
                    [datamat] = read_4dfpimg([subimg '_flip.4dfp.img']);
                    FullData=[FullData datamat];
                    group='Subjects';
                    runs=runs+1;
                end
                clear datamat
            end
        else
            for j=1:8;
                img = [ C{1,1}{i,1} '/bold' num2str(j) '/' C{1,1}{i,1} '_b' num2str(j) '_faln_dbnd_xr3d_atl_g7_bpss_resid.4dfp.img' ];
                subimg = [ root '/Subjects/' img ];
                if exist(subimg,'file')                    
                    [datamat] = read_4dfpimg(subimg);
                    FullData=[FullData datamat];
                    group='Subjects';
                    runs=runs+1;
                end
                clear datamat
            end
        end
        % Load DVAR and DDAT and scrub
        dvar=importdata(strcat(root,'/',group,'/',C{1,1}{i,1},'/FCmaps/resid_DVAR_THRESHOLD_4.6/',C{1,1}{i,1},'_faln_dbnd_xr3d_atl_g7_bpss_resid.dat'),' ');      
        if length(varargin)>0  
            ddat = importdata(strcat(root,'/',group,'/',C{1,1}{i,1},'/movement/',C{1,1}{i,1},'.dvals'));
            Scrub=(logical(ddat<DDATcut) .* logical(dvar(:,2)<4.6));
        else
            Scrub=(logical(dvar(:,2)<4.6)); 
        end
        for j=1:runs
            f=(j-1)*128+1;
            Scrub(f:(f+4))=0;
        end
        if length(Scrub)>1024
            Scrub=Scrub(1:1024);
        end
        % Scrub and mask full data
        ScrubbedFullData=FullData(:,logical(Scrub));
        ScrubbedMaskedData=ScrubbedFullData(logical(mask>=threshold),:)';
        
        % Count frames and skip sub if <5min remain
        frames=sum(Scrub);
        if frames<120
            disp('Not enough data');
            frames
            clear FullData
        else           
            switch masktype
                case 'wholebrain'
                    % Load ROI timecourses
                    SeedData = [ root '/Analysis/jssiegel/264ROIs/' C{1,1}{i,1} '/FCmaps/resid_DVAR_THRESHOLD_4.6_DDAT_THRESHOLD_0.5/' C{1,1}{i,1} '_seed_regressors.dat' ];
                    ROI=importdata(SeedData);
                    num_rois=size(ROI.data,2);
                    % Scrub ROI timecourses
                    ScrubbedROIData=ROI.data(logical(Scrub),:);                    
                    [Correl,~]=paircorr_mod(ScrubbedMaskedData,ScrubbedROIData);
                    save(Output,'Correl','frames','DDATcut','num_voxels','num_rois','Age','-v7.3');
                    clear FullData
                case 'basalganglia'
                    mask2 = read_4dfpimg('/data/nil-bluearc/corbetta/Hacker/ROIs/Cortex_Mask_20k/N21_aparc+aseg_GMctx_on_711-2V_333_avg.4dfp.img'); 
                    % Mask full data
                    ScrubbedMaskedData2=ScrubbedFullData(logical(mask2>0.5),:)';
                    [Correl,~]=paircorr_mod(ScrubbedMaskedData,ScrubbedMaskedData2);
                    save(Output,'Correl','frames','DDATcut','num_voxels','Age','-v7.3');
                    clear FullData
                otherwise
                    Correl=int8(corrcoef(ScrubbedMaskedData)*100);
                    CorVector=int8(ExtractDataAboveDiagonal(Correl));
                    save(Output,'CorVector','frames','DDATcut','num_voxels','Age','threshold','-v7.3');
                    clear FullData Correl CorVector                   
            end
        end
        toc
    end
end
end

