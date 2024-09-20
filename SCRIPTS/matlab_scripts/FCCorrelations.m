function FCCorrelations(SubjectList,masktype,varargin)
% FCCorrelations Functional connectivity correlation matrices.
% 
% FCCorrelations(SubjectList,masktype) loads preprocessed 4dfp data into matlab
% for a subjects in SubjectList, chooses voxels inside of a n-voxel mask
% (masktype), removes frames with DVARS>4.6, and then creates an n-by-n
% correlation matrix in the subjects scratch directory.
%
% FCCorrelations(SubjectList,masktype,DDATcut) Uses a threshold of DDAT>DDATcut
% to remove high motion frames. This requires that "P2 -D" was run.
%
% FCCorrelations(SubjectList,maskname) Uses a user specified mask instead of one
% the masks that are already included.
%
% Run inside study directory (eg /data/nil-bluearc/corbetta/Studies/MyStrokeStudy)
% 
% Prerequisites:
% 1) "P2 <sub_name> -D4.6 -c -f -i" must be run for all subjects
% 2) A mask (your own or 'graymatter', 'wholebrain', 'basalganglia', '0.3symmetric')
% 3) A SubjectList called *_List.txt saved them in the current directory. 
% 
% eg PutamenStroke_List.txt
% NAME	DOB	EDUCATION	AGE	HAND	GENDER
% FCS_043_A	04/19/1961	12	47	R	M
% FCS_048_A	05/13/1945	16	63	R	F
% FCS_068_A	04/30/1952	10	57	R	F
% 
% Example: FCCorrelations('Control_List.txt','0.3symmetric',0.5)
% Load 4dfp data for each person, remove high motion frames, and save
% a correlation matrix to /Study/MyStrokeStudy/PatientX/0.3symmetric_RawData.mat
% 
% After this is run, you can use the same SubjectLists (one for patients,
% one for controls) to run Map_DysFC.
% 
% Author: Josh Siegel (siegelj@wusm.wustl.edu) 8/8/2012
% Functions called: paircorr_mod.m, read_4dfpimg.m, endian_checker.m
% Help & code from Nick M, Gagan W.

tic

% OTHER IMPORTANT VARIABLES:
OverwriteMatrices = input('If correlation matrices exist, do you want to overwrite them? Y/N [Y]: ','s'); % set to 1 if you want to overwrite correl matrices for subjects that already have a RawData.mat file
[~,Study,~]=fileparts(pwd);
fid=fopen(SubjectList,'r');
C=textscan(fid,'%s %s %n %n %c %c','HeaderLines',1);
fclose(fid);
[mask,threshold]=savedmasks(masktype);
num_voxels=int32(sum(mask>=threshold));

for i=1:length(C{1,1}) % Load data, create correlation matrix, save to scratch
    C{1,1}{i,1}
    Age = C{1,4}(i,1);
    SubjOutputDir=[ '/scratch/' Study '/' C{1,1}{i,1}];
    Output = ([ SubjOutputDir '/' masktype '_RawData.mat']);
    if exist(Output,'file') && strcmp(OverwriteMatrices,'N')
        disp('Correlation matrix already exists. Skip subject');
    else
        mkdir(SubjOutputDir);
        FullData=[];
        runs=0;
        root = [ '/data/nil-bluearc/corbetta/Studies/' Study ];
        
        for j=1:8;
            img = [ C{1,1}{i,1} '/bold' num2str(j) '/' C{1,1}{i,1} '_b' num2str(j) '_faln_dbnd_xr3d_atl_g7_bpss_resid.4dfp.img' ];
            ctlimg = [ root '/Controls/' img ];
            subimg = [ root '/Subjects/' img ];
            if exist(ctlimg,'file')
                [datamat] = read_4dfpimg(ctlimg);
                FullData=[FullData datamat];
                group='Controls';
                runs=runs+1;
            elseif exist(subimg,'file')
                [datamat] = read_4dfpimg(subimg);
                FullData=[FullData datamat];
                group='Subjects';
                runs=runs+1;
            elseif j==1
                disp('Subject not found.');
            end
            clear datamat
        end
        % Load DVAR and DDAT and scrub
        dvar=importdata(strcat(root,'/',group,'/',C{1,1}{i,1},'/FCmaps/resid_DVAR_THRESHOLD_4.6/',C{1,1}{i,1},'_faln_dbnd_xr3d_atl_g7_bpss_resid.dat'),' ');      
        dvar=dvar(:,2);
        if ~isempty(varargin) && isnumeric(varargin{1})
            DDATcut=varargin{1};
            FD = importdata(strcat(root,'/',group,'/',C{1,1}{i,1},'/movement/',C{1,1}{i,1},'.dvals'));
            Scrub=(logical(FD<DDATcut) .* logical(dvar<4.6));
        else
            DDATcut='none';
            Scrub=(logical(dvar<4.6));
            FD=[];
            for r=1:runs
                ddat = importdata(strcat(root,'/',group,'/',C{1,1}{i,1},'/movement/',C{1,1}{i,1},'_b',num2str(r),'_faln_dbnd_xr3d.ddat'));
                runFD=sum(abs(ddat.data(:,2:7)),2)'; % THIS NEEDS TO INCLUDE ALL RUNS
                FD=[FD runFD];
            end
            FD=FD';
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
        dvarSD=std(dvar(Scrub==1));
        movementRMS=(mean(sqrt(FD(Scrub==1))).^2);           
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
                    [Correl,~]=int8(paircorr_mod(ScrubbedMaskedData,ScrubbedROIData)*100);
                    save(Output,'Correl','mask','frames','DDATcut','num_voxels','num_rois','Age','movementRMS','dvarSD','-v7.3');
                    clear FullData Correl
                case 'basalganglia'
                    maskmat2 = read_4dfpimg('/data/nil-bluearc/corbetta/Hacker/ROIs/Cortex_Mask_20k/N21_aparc+aseg_GMctx_on_711-2V_333_avg.4dfp.img'); 
                    % Mask full data
                    ScrubbedMaskedData2=ScrubbedFullData(logical(maskmat2>0.5),:)';
                    [Correl,~]=int8(paircorr_mod(ScrubbedMaskedData,ScrubbedMaskedData2)*100);
                    save(Output,'Correl','mask','frames','DDATcut','num_voxels','Age','movementRMS','dvarSD','-v7.3');
                    clear FullData Correl
                otherwise
                    Correl=int8(corrcoef(ScrubbedMaskedData)*100);
                    CorVector=int8(ExtractDataAboveDiagonal(Correl));
                    save(Output,'CorVector','mask','frames','DDATcut','num_voxels','Age','threshold','movementRMS','dvarSD','-v7.3');
                    clear FullData Correl CorVector                   
            end
        end
        toc
    end
end
end

