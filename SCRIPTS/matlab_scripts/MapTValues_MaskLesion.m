function h = MapTValues_MaskLesion(Analysis,Controls,Study,masktype,AgeRange)
% 1) Load correl matrices and produce a big control mat
% 2) Run ttest for every voxel Pt vs Ctrls
%
% Input Variables:
% Analysis: eg 'PutamenStroke' (PutamenStroke_List.txt must exist)
% Controls: list of control subjects (name DOB edu age hand gender)
% Study: name your current directory
% masktype: 'graymatter' 'wholebrain'
% AgeRange: Include subjects within n years of patient
%
% MapTValues_MaskLesion('PutamenStroke','StrokeControls','DysFC','graymatter',40)

CtlOutput = ['/scratch/' Study '/' Controls '_' masktype '_Correl.mat'];
ImageOutputDir = ['/data/nil-bluearc/corbetta/Studies/' Study '/Analysis/jssiegel/LesionMask' ];
UseN27 = 1;

sub_list = [ Analysis '_List.txt' ];
fid=fopen(sub_list,'r');
P=textscan(fid,'%s %s %n %n %c %c','HeaderLines',1);
fclose(fid);

ctl_list = [ Controls '_List.txt' ];
fid=fopen(ctl_list,'r');
C=textscan(fid,'%s %s %n %n %c %c','HeaderLines',1);
fclose(fid);

matlabpool(6);
tic

mask = read_4dfpimg('/data/nil-bluearc/corbetta/Hacker/Process/MATLAB/FCTB/Reference_Images/N21_aparc+aseg_GMctx_on_711-2V_333_avg_zlt0.5_gAAmask_v1.4dfp.img');
Image=struct('Correlmask',{},'tstat',{},'OutputDir',{},'Fullmask',{},'controls',{});
for patient=1:length(P{1,1})
    %  Make Matrix for Controls
    [~,lesionfile] = system([ 'ls /data/nil-bluearc/corbetta/Studies/' Study '/Subjects/' P{1,1}{patient,1} '/atlas/*lesion.4dfp.img']);
    Lesion = read_4dfpimg(strcat(lesionfile));
    
    Fullmask = zeros(length(mask),1);
    Correlmask=zeros(sum(mask),1);    
    p=1;
    for i=1:length(mask)
        if mask(i) && ~Lesion(i)
            Fullmask(i)=1;
            Correlmask(p)=1;
            p=p+1;
        elseif mask(i) && Lesion(i)
            p=p+1;
        end
    end
    Image(patient).Fullmask=Fullmask;
    Image(patient).Correlmask=Correlmask;
end
parfor patient=1:length(P{1,1})

    RawData = [ '/scratch/' Study '/' P{1,1}{patient,1} '/' masktype '_RawData.mat' ];
    S=load(RawData);
    CorVectormask=Image(patient).Correlmask*Image(patient).Correlmask';
    CorVectormask=ExtractDataAboveDiagonal(CorVectormask);
    num_voxels=sum(Image(patient).Correlmask);
    
    % Include controls are within AgeRange yrs of subject
    controls=zeros(length(C{1,1}),1);
    controls(abs(C{1,4}-P{1,4}(patient))<=AgeRange)=1; 
    controlsmat=controls*controls';
    controlsmat=ExtractDataAboveDiagonal(controlsmat);
    controls=C{1,1}(logical(controls));    
    S.Correl=VectorToMatrix(S.CorVector(logical(CorVectormask)),num_voxels);
    
    PatientCorrel=zeros(length(controls),num_voxels);   
    ControlCorrel=zeros(length(C{1,1}),length(C{1,1}),num_voxels); 
    for i=1:length(controls)
        % Then load correl mat for everyone else one by one
        RawData = [ '/scratch/' Study '/' char(controls(i)) '/' masktype '_RawData.mat' ];
        A=load(RawData);
        A.Correl=single(VectorToMatrix(A.CorVector(logical(CorVectormask)),num_voxels));
        
        PairCorrel=zeros(num_voxels,1);
        for k=1:num_voxels
            x=corrcoef(S.Correl(k,:),A.Correl(k,:));
            PatientCorrel(i,k)=x(2);
        end
        
        % And find corrcoef for each voxels FC map
        for j=i+1:length(C{1,1})
            RawData = [ '/scratch/' Study '/' C{1,1}{j,1} '/' masktype '_RawData.mat' ];
            B=load(RawData);
            B.Correl=single(VectorToMatrix(B.CorVector(logical(CorVectormask)),num_voxels));
            for k=1:num_voxels
                x=corrcoef(A.Correl(k,:),B.Correl(k,:));
                ControlCorrel(i,j,k)=x(2);
            end
        end
    end
    
    tstat=zeros(num_voxels,1);
    for k=1:num_voxels
        m=ExtractDataAboveDiagonal(squeeze(ControlCorrel(:,:,k)));
        m=m(logical(controlsmat));
        [~,~,~,stats]=ttest2(m,PatientCorrel(:,k));
        tstat(k)=stats.tstat;
     
    end
    OutputDir = [ ImageOutputDir '/' Analysis '-' Controls ];
    Image(patient).tstat=tstat;
    Image(patient).OutputDir=OutputDir;
    Image(patient).controls=controls;
end
for patient=1:length(P{1,1})
    mkdir(Image(patient).OutputDir);    
    OutputFile= [Image(patient).OutputDir '/DysFC_' date '.mat'];    
    OutputImage = ([ Image(patient).OutputDir '/' P{1,1}{patient,1} '_' Analysis '-' Controls '_' masktype '_lesionmask.4dfp.img']);   
    write_back(Image(patient).tstat,OutputImage,Image(patient).Fullmask)
    Cluster = [ 'cluster_4dfp ' OutputImage ' -n10 -t3'];
    system(Cluster)
end

matlabpool close
toc
end


function write_back(tstat,imgname,mask)

tstat_img=single(zeros(length(mask),1));
mask=find(mask==1);
for i=1:length(mask)
    tstat_img(mask(i))=tstat(i);
end
write_4dfpimg(tstat_img,imgname,'littleendian')
write_4dfpifh(imgname,1,'littleendian')

end