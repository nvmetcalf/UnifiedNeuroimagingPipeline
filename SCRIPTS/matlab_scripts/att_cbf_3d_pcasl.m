
function [MeanCBF WeightedDelay]=att_cbf_3d_pcasl(rawPcasl_CellArray,w,T1b, FD_in,FD_Thresh, LC_CL)

% Calculate ATT & CBF for 3D pCASL
% CBF data are calculated according to the formula from
% Wang et al. The value of arterial spin-labeled perfusion imaging in acute ischemic stroke: comparison with dynamic susceptibility contrast-enhanced MRI.
% Stroke 43.4 (2012): 1018-1024. formula [1]
% CBF_CASL (ml/100g/min) = 60*100*DeltaM*lambda*R1a/(2*alp*Mo*(exp(-w*R1a)-exp(-(t+w)*R1a))

% Input
% rawPcasl: 4D pCASL image. First Mo, second Dummy (skip), then
%           Label/Control pairs (L first). Cell Array in order of the post labeling
%           delays
% w: post-labeling delays (sec)
% t1b: blood t1 value (sec), default (for 3T system): 1.490 (put 0 if use default)
%FD : cell array with FD values for each sequence

% Output
% WeightedDelay: calculated ATT
% MeanCBF: calculated mean ATT corrected CBF value

  
% Set parameters in the equation

% Default values for w and t1b

if T1b == 0
	disp('Use default blood T1...');
	disp('T1b = 1.490 sec');
	T1b = 1.490; % T1 of blood (sec)
end

if(~exist('FD_Thresh'))
    FD_Thresh = 0.5
end

if(~exist('LC_CL'))
    LC_CL = 1;
end
% The following parameters are hard coded using parameters from
% Wang et al. (2012)
t = 1.5; % label time (sec)
lambda = 0.9; % blood/tissue water partition coefficient (g/mL)
alp = 0.8; % label efficiency
R1a = 1/T1b; % blood R1

%initialize the output

All_w_deltaM = [];
All_deltaM = [];
All_Mo = [];

%cycle through each ASL image and determine the optimal CBF and ATT
for i = 1:length(rawPcasl_CellArray)
    % Calculate deltaM
    disp(['Run: ' num2str(i)]);
    FD = FD_in{i};
    rawPcasl = double(rawPcasl_CellArray{i});
    
    Mo = squeeze(rawPcasl(:,:,:,1)); % equilibrium magnetization of brain
    %Mo = Mo .* brainMask;
    [xSize,ySize,zSize,tSize] = size(rawPcasl);
    fStart = 3 - mod(tSize,2);   %adjust the number of frames for IF the number is odd. If Odd, there is not a dummy. if Even, there must be a dummy M0 at frame 2.
    deltaM = zeros(xSize,ySize,zSize);
    numPair = (tSize - mod(tSize,2))/2;
    
    for ii = fStart:2:tSize
        
        if(FD(ii+1) > FD_Thresh)
            disp(['run ' num2str(i) '. ' num2str(ii+1) ' : ' num2str(FD(ii+1))]);
            numPair = numPair - 1;
            continue;
        end
        if(LC_CL)
            control = squeeze(rawPcasl(:,:,:,ii+1));
            label = squeeze(rawPcasl(:,:,:,ii));
        else
            control = squeeze(rawPcasl(:,:,:,ii));
            label = squeeze(rawPcasl(:,:,:,ii+1));
        end
        deltaM = deltaM + control - label;
    end
    %this is the mean difference image
    deltaM = deltaM / numPair;
    deltaM(deltaM<0) = 0;
    %deltaM = deltaM .* brainMask;

    %this is to comput weighted delay: sum(w(i) * deltaM(i))/sum(deltaM)
    All_w_deltaM = horzcat(All_deltaM,reshape(deltaM,[],1).*w(i)); % w(i) * deltaM(i)
    All_deltaM = horzcat(All_deltaM,reshape(deltaM,[],1)); % deltaM(i)
    All_Mo = horzcat(All_Mo, reshape(Mo,[],1));
end

WeightedDelay = sum(All_w_deltaM')./sum(All_deltaM');

%DefinedVoxels = find(reshape(brainMask,[],1) ~= 0);
DefinedVoxels = 1:length(reshape(Mo,[],1));
%compute the CBF of each PLD using the WeightedDelay
% Now calculate CBF 
All_CBF = All_deltaM .* 0;
for i = 1:length(rawPcasl_CellArray)
    exp2 = exp(-(t + w(i)) * R1a);
    for j = 1:length(DefinedVoxels)
        exp1 = exp((min(WeightedDelay(j) - w(i),0) - WeightedDelay(j)) * R1a);
        All_CBF(j,i) = (60*100* lambda * All_deltaM(j,i) * R1a) / (2 * alp * All_Mo(j,i) * (exp1 - exp2) + eps);
    end
end

MeanCBF = nanmean(All_CBF')';

