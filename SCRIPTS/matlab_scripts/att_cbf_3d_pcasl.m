
function [MeanCBF WeightedDelay]=att_cbf_3d_pcasl(rawPcasl_CellArray,brainMask,w,T1b, FD_in)

% Calculate ATT & CBF for 3D pCASL
% CBF data are calculated according to the formula from
% Wang et al. The value of arterial spin-labeled perfusion imaging in acute ischemic stroke: comparison with dynamic susceptibility contrast-enhanced MRI.
% Stroke 43.4 (2012): 1018-1024. formula [1]
% CBF_CASL (ml/100g/min) = 60*100*DeltaM*lambda*R1a/(2*alp*Mo*(exp(-w*R1a)-exp(-(t+w)*R1a))

% Input
% rawPcasl: 4D pCASL image. First Mo, second Dummy (skip), then
%           Label/Control pairs (L first). Cell Array in order of the post labeling
%           delays
% brainMask: 3D brain mask
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

% The following parameters are hard coded using parameters from
% Wang et al. (2012)
t = 1.5; % label time (sec)
lambda = 0.9; % blood/tissue water partition coefficient (g/mL)
alp = 0.8; % label efficiency
R1a = 1/T1b; % blood R1

%initialize the output

brainMask = double(brainMask);

All_w_deltaM = [];
All_deltaM = [];
All_Mo = [];
%cycle through each ASL image and determine the optimal CBF and ATT
for i = 1:length(rawPcasl_CellArray)
    % Calculate deltaM
    
    FD = FD_in{i};
    rawPcasl = double(rawPcasl_CellArray{i});
    
    Mo = squeeze(rawPcasl(:,:,:,1)); % equilibrium magnetization of brain
    Mo = Mo .* brainMask;
    [xSize,ySize,zSize,tSize] = size(rawPcasl);
    deltaM = zeros(xSize,ySize,zSize);
    numPair = tSize/2 - 1;
    
    for ii = 2:numPair+1
        
        if(FD(ii*2) > 0.5)
            disp(['run ' num2str(i) '. ' num2str(ii*2) ' : ' num2str(FD(ii*2))]);
            numPair = numPair - 1;
            continue;
        end
        
        control = squeeze(rawPcasl(:,:,:,2*ii));
        label = squeeze(rawPcasl(:,:,:,2*ii-1));
        deltaM = deltaM + control - label;
    end
    %this is the mean difference image
    deltaM = deltaM / numPair;
    deltaM(deltaM<0) = 0;
    deltaM = deltaM .* brainMask;

    %this is to comput weighted delay: sum(w(i) * deltaM(i))/sum(deltaM)
    All_w_deltaM = horzcat(All_deltaM,reshape(deltaM,[],1).*w(i)); % w(i) * deltaM(i)
    All_deltaM = horzcat(All_deltaM,reshape(deltaM,[],1)); % deltaM(i)
    All_Mo = horzcat(All_Mo, reshape(Mo,[],1));
end

WeightedDelay = sum(All_w_deltaM')./sum(All_deltaM');

DefinedVoxels = find(reshape(brainMask,[],1) ~= 0);

%compute the CBF of each PLD using the WeightedDelay
% Now calculate CBF 
All_CBF = All_deltaM .* 0;
for i = 1:length(rawPcasl_CellArray)
    exp2 = exp(-(t + w(i)) * R1a);
    for j = 1:length(DefinedVoxels)
        v = DefinedVoxels(j);
        exp1 = exp((min(WeightedDelay(v) - w(i),0) - WeightedDelay(v)) * R1a);
        All_CBF(v,i) = (60*100* lambda * All_deltaM(v,i) * R1a) / (2 * alp * All_Mo(v,i) * (exp1 - exp2));
    end
end

MeanCBF = mean(All_CBF')';

