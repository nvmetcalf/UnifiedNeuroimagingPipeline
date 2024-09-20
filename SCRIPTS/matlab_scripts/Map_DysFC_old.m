function Map_DysFC(Analysis,Controls,masktype,AgeRange,ImageOutputDir)
% Map_DysFC Maps dysfunctional connectivity results.
% 
% Map_DysFC(Analysis,Controls,masktype,AgeRange,ImageOutputDir) compares
% subject(s) in [Analysis]_List.txt to all controls in [Controls]_List.txt 
% age within AgeRange years of subject and saves the results to
% ImageOutputDir/SubjectX/DysFC_S_SubjectX_18Controls_graymatter.4dfp.img
% 
% 
% masktype: 'graymatter' 'wholebrain' '0.3symmetric' or the name of the
% unique mask that you used in FCCorrelations.m w/o path or extension.
%
% Run inside study directory (eg /data/nil-bluearc/corbetta/Studies/MyStrokeStudy)
% after running FCCorrelations.m
%
% Example: Map_DysFC('PutamenStroke','Controls','wholebrain',10,Analysis/jssiegel/PutamenStroke)
% 1) FC data from all controls in Controls_List.txt are compared to measure
% inter-control variability. (if this has already been done, you can skip it)
% 2) for each subj in PutamenStroke_List.txt, FC data is compared all
% qualifying controls.
% 3) for every voxel in the mask, a t-test is run comparing
% patient-control similarity to control-control similarity. 
% 4) save results as .mat and write them to a 4dfp image of t-scores,
% creating a map of regions which have abnormal connectivity. 
%
% Author: Josh Siegel (siegelj@wusm.wustl.edu) 8/8/2012

% ImageOutputDir = ['/data/nil-bluearc/corbetta/Studies/' Study '/Analysis/jssiegel/' Analysis ];

[~,Study,~]=fileparts(pwd);
CtlOutput = ['/scratch/' Study '/' Controls '_' masktype '_Correl.mat'];

sub_list = [ Analysis '_List.txt' ];
fid=fopen(sub_list,'r');
P=textscan(fid,'%s %s %n %n %c %c %c','HeaderLines',1);
fclose(fid);

ctl_list = [ Controls '_List.txt' ];
fid=fopen(ctl_list,'r');
C=textscan(fid,'%s %s %n %n %c %c %c','HeaderLines',1);
fclose(fid);
controls=C{1,1};
matlabpool(8);
tic
skip='N';
if exist(CtlOutput,'file')
skip = input('Control matrix exists, do you want to use it? Y/N [Y]: ','s');
end
if strcmp(skip,'Y') % Load Matrix for Controls
    load(CtlOutput);
else %  Make ctl-by-ctl-by-voxels Matrix for Controls
    ControlCorrel=zeros(length(C{1,1}),length(C{1,1}),38070);
    parfor i=1:length(C{1,1})
        ControlCorrel(i,:,:)=GroupCorrelations(Study,C,masktype,i);    
    end
    save(CtlOutput,'ControlCorrel','controls','-v7.3')
    disp('Control correlations have been calculated')
    toc
end
%% Now run DisFC for each individual in the Patients file against matched controls


for patient=1:length(P{1,1})
    P{1,1}{patient,1}
    % Include controls are within AgeRange yrs of subject
    controls=zeros(length(C{1,1}),1);
    controls(abs(C{1,4}-P{1,4}(patient))<=AgeRange)=1;
    % Exclude self from controls
    for i=1:length(controls)
        if strcmp(P{1,1}(patient),C{1,1}{i,1})
            controls(i)=0;
        end
    end
    
    controlsmat=controls*controls';
    controlsmat=ExtractDataAboveDiagonal(controlsmat);
    controls=C{1,1}(logical(controls));
    %Loading a full correl mat for a patient
    RawData = [ '/scratch/' Study '/' P{1,1}{patient,1} '/' masktype '_RawData.mat' ];
    S=load(RawData);
    if ~isfield(S,'Correl')
        S.Correl=single(VectorToMatrix(S.CorVector,S.num_voxels));
    end
    num_voxels=length(S.Correl);
    PatientCorrel=zeros(length(controls),num_voxels);
    parfor i=1:length(controls)
        % Then load correl mat for everyone else one by one
        RawData = [ '/scratch/' Study '/' char(controls(i)) '/' masktype '_RawData.mat' ];
        Ref=load(RawData);
        if ~isfield(Ref,'Correl')
        Ref.Correl=single(VectorToMatrix(Ref.CorVector,Ref.num_voxels));
        end
        % And find corrcoef for each voxels FC map
        PairCorrel=zeros(Ref.num_voxels,1);
        
        for k=1:num_voxels
            x=corrcoef(S.Correl(k,:),Ref.Correl(k,:));
            PairCorrel(k)=x(2);           
        end
        PatientCorrel(i,:)=PairCorrel;
    end
    tstat=zeros(num_voxels,1);
    % ctl_kstest=zeros(num_voxels,1);
    % sub_kstest=zeros(num_voxels,1);
    parfor k=1:num_voxels
        m=ExtractDataAboveDiagonal(squeeze(ControlCorrel(:,:,k)));
        m=m(logical(controlsmat));
        [~,~,~,stats]=ttest2(m,PatientCorrel(:,k));
        tstat(k)=stats.tstat;
%         g=PatientCorrel(:,k);
%         [~,sub_kstest(k)]=lillietest(((g-mean(g)).*1/std(g-mean(g))));
%         [~,ctl_kstest(k)]=kstest(((m-mean(m)).*1/std(m-mean(m))));        
    end
    OutputDir = [ ImageOutputDir '/' P{1,1}{patient,1} ];   
    mkdir(OutputDir);
    OutputFile= [OutputDir '/DysFC_' P{1,1}{patient,1} '_'  Controls '_' masktype '.mat'];
    save(OutputFile,'tstat','controls','PatientCorrel')
    OutputImage=[OutputDir '/DysFC_' P{1,1}{patient,1} '_' num2str(length(controls)) Controls '_' masktype '.4dfp.img'];
    write_back(tstat,OutputImage,mask,num_voxels)
    Cluster = [ 'cluster_4dfp ' OutputImage ' -n10 -t3'];
    system(Cluster)
    toc
end

matlabpool close

end

function PairCorrel = GroupCorrelations(Study,C,masktype,i)
C{1,1}{i,1}
% Then load correl mat for everyone else one by one
RawData = [ '/scratch/' Study '/' C{1,1}{i,1} '/' masktype '_RawData.mat' ];
A=load(RawData);
if ~isfield(A,'Correl')
    A.Correl=single(VectorToMatrix(A.CorVector,A.num_voxels));
end
PairCorrel=zeros(length(C{1,1}),A.num_voxels);
% And find corrcoef for each voxels FC map
for j=i+1:length(C{1,1})
    RawData = [ '/scratch/' Study '/' C{1,1}{j,1} '/' masktype '_RawData.mat' ];
    B=load(RawData);
    if ~isfield(B,'Correl')
        B.Correl=single(VectorToMatrix(B.CorVector,B.num_voxels));
    end
    for k=1:B.num_voxels
        x=corrcoef(A.Correl(k,:),B.Correl(k,:));
        PairCorrel(j,k)=x(2);
    end
end    
end

function write_back(tstat,imgname,mask,voxels)

maskmat = read_4dfpimg(mask);
tstat_img=single(zeros(length(maskmat),1));
maskmat=find(maskmat>=1);
for i=1:voxels
    tstat_img(maskmat(i))=tstat(i);
end
write_4dfpimg(tstat_img,imgname,'littleendian')
write_4dfpifh(imgname,1,'littleendian')

end