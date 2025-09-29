
function [DTE, TE1, TE2, TE3, ZMoment1, ZMoment2, ZMoment3, B0] = getASEParameters_2echoes(varargin)

%path(path, '/hongyu/yyang/ASE_nico/ASE/Dicom');

%name_dir1 = '../Dicom_CNDA/0831_007/scans/14/DICOM/';
%name_dir2 = '../Dicom_CNDA/0831_007/scans/15/DICOM/';

DTE = [];
TE1 = [];
TE2 = [];
TE3 = [];
ZMoment1 = [];
ZMoment2 = [];
ZMoment3 = [];
B0 = [];

% if(isempty(DicomDir))
%    [a sym_path] = system(['readlink -f ' varargin{length(varargin)/2+1}]); %get the real path of the first nifti
%    [sym_path b c] = fileparts(sym_path);    %pull the whole path to the first nifti
%    [DicomDir b c] = fileparts(sym_path);    %strip off the top most folder (BIDS folder)
%    
% end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% 112: Very old version
%% 98: Most used version: 2/3 Echo, w/  zshimming
%% 90: Most used version: 2/3 Echo, w/o zshimming
%% 82: WU-Vanderbilt, MaxDTE=40, w/o zshimming, 2 Repetition
%% 41: WU-Vanderbilt, MaxDTE=40, w/o zshimming, 1 Repetition

NumSlices = [];
%do a sanity check on the images
%first half of varargin are the nifti image files
for i = 1:length(varargin)/2
    image = load_nifti(varargin{i});
    
    if(isempty(NumSlices))
        NumSlices = image.dim(5);
    end
    
    if(NumSlices ~= image.dim(5))
       error(['Number of slices differs in ' vararging{i} ' from the first in the list ' varargin{1}]); 
    end
    
    if(image.dim(5) ~= 112 & image.dim(5) ~= 98 & image.dim(5) ~= 90 & image.dim(5) ~= 82 & image.dim(5) ~= 41)
        fprintf('the numbers are %d, num1, please check %s\n', image.dim(5), varargin{i});
        return;
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%5
% grab the sequence parameters from the json
%second half of the varargin are the jsons
Echo_Jsons = [];
for i = length(varargin)/2+1:length(varargin)
    json = load_json(varargin{i});
    if(isempty(Echo_Jsons))
        Echo_Jsons = json;
        Echo_Jsons.EchoNumber = 1;
    else
        Echo_Jsons = vertcat(Echo_Jsons, json);
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
TE = [];
b0 = [];

for(k=1:length(varargin)/2)
    
%     Found_Echo_Dicoms = subdir([DicomDir '/*' Echo_Jsons(k).StudyInstanceUID '-' num2str(Echo_Jsons(k).SeriesNumber) '-*.dcm']);
%     %%%%%fprintf('echo %d  %d  %s\n', k, i, name_in);
%     %convert the subdir struct to a cell array.
%     
%     %data must have been double exported... should probably make this
%     %better so it can cast triples or more...
%     if(length(Found_Echo_Dicoms) > 98)
%         Found_Echo_Dicoms(length(Found_Echo_Dicoms)/2+1:end) = [];
%     end
%     
%     Echo_Dicoms_Unsorted = {};
%     
%     for j = 1:length(Found_Echo_Dicoms)
%        Echo_Dicoms_Unsorted = horzcat(Echo_Dicoms_Unsorted, Found_Echo_Dicoms(j).name);
%     end
%     
%     [Echo_Dicoms, index1] = sort_nat(Echo_Dicoms_Unsorted, 'ascend');
    for i = 1:length(Echo_Jsons(k).ImageComments)
        info = Echo_Jsons(k);
        % b0(k,i) = info.MagneticFieldStrength;
        
        if(isfield(info, 'SoftwareVersion'))
            SoftwareVersion = info.SoftwareVersion;
        elseif(isfield(info, 'SoftwareVersions'))
            SoftwareVersion = info.SoftwareVersions;
        else
            error('dicom header does not contain the software version of the scanner.');
        end
        
        imagecomments = info.ImageComments{i,1};
        a = strread(imagecomments,'%s', 'delimiter', ',');
        
        if strfind(SoftwareVersion,'syngo MR XA')
            TE(k,i) = str2num(info.EffectiveEchoTime);
            b0(k,i) = str2num(info.TransmitterFrequency)/42.576;
            
        else
            TE(k,i) = str2num(info.EchoTime);
            b0(k,i) = str2num(info.ImagingFrequency)/42.576;
        end
        
        if(~isempty(strfind(SoftwareVersion,'syngo MR XA')) && length(a) == 8)
            a2=char(a(3));
            a3=char(a(4));
            a7=char(a(8));
        else
            a2=char(a(2));
            a3=char(a(3));
            a7=char(a(7));
        end
        
        [b1,b2,b3] = strread(a2, '%s%s%d', 'delimiter', ' ');
        DTEArr(k, i) = b3;
        clear b1 b2 b3;
        
        [b1,b2,b3] = strread(a3, '%s%s%d', 'delimiter', ' ');
        zmoment(k, i) = b3;
        clear b1 b2 b3;
        
        [b1,b2,b3] = strread(a7, '%s%s%d', 'delimiter', ' ');
        dTE(k, i) = b3;
        clear b1 b2 b3;
    end
end

%%%%%%%%%check the results to make things are correct
te1 = squeeze(TE(1,:));

for k = 2:length(Echo_Jsons)
    te2 = squeeze(TE(k,:));

    if max(te1)~=min(te1) | max(te2)~=min(te2)
        error(['TE of ' num2str(varargin{k}) ' different from ' varargin{1}]);
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for i=1:NumSlices
    buffer = [];
    if DTEArr(1,i)~=DTEArr(2,i)
        for k = 1:length(varargin)
            if(~isempty(buffer))
                buffer = sprintf('%s %f', buffer, DTEarr(k,i));
            else
                buffer = sprintf('%f', DTEarr(k,i));
            end
        end
    end
    fprintf('DTIArr %d %s\n', i, buffer);
end

for i=1:NumSlices-8
    buffer = [];
    if zmoment(1,i)~=0 | zmoment(2,i)~=0
        for k = 1:length(varargin)
            if(~isempty(buffer))
                buffer = sprintf('%s %f', buffer, zmoment(k,i));
            else
                buffer = sprintf('%f', zmoment(k,i));
            end
        end
    end
    fprintf('zmoment %d %s\n', i, buffer);
end

if max(b0(:)) ~= min(b0(:))
   fprintf('field strength %f %f\n', min(b0(:)), max(b0(:)));
end;

DTE = squeeze(DTEArr(1,:));
TE1 = TE(1,1);
TE2 = TE(2,1);
if(length(varargin)/2 > 2)
    TE3 = TE(3,1);
else
    TE3 = TE2;
end

ZMoment1 = squeeze(zmoment(1,:));
ZMoment2 = squeeze(zmoment(2,:));
if(length(varargin)/2 > 2)
    ZMoment3 = zmoment(3,1);
else
    ZMoment3 = ZMoment2;
end

B0 = b0(1,1);

