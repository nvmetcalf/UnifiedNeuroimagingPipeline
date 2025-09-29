
function [CBF CBF_by_Pair numPair Mo]=cbf_3d_pcasl(rawPcasl, Mo, PLD_json, T1b, FD_tmask, LC_CL, CBF_OutputFilename)

% Calculate CBF for 3D pCASL
% CBF data are calculated according to the formula from
% Wang et al. The value of arterial spin-labeled perfusion imaging in acute ischemic stroke: comparison with dynamic susceptibility contrast-enhanced MRI.
% Stroke 43.4 (2012): 1018-1024. formula [1]
% CBF_CASL (ml/100g/min) = 60*100*DeltaM*lambda*R1a/(2*alp*Mo*(exp(-w*R1a)-exp(-(t+w)*R1a))

% Input
% rawPcasl: 4D pCASL image. First Mo, second Dummy (skip), then Label/Control pairs (L first)
% brainMask: 3D brain mask
% w: post-labeling delay (sec), default: 2 (put 0 if use default)
% t1b: blood t1 value (sec), default (for 3T system): 1.490 (put 0 if use default)

% Output
% CBF: calculated CBF value

  
% Set parameters in the equation

% Default values for w and t1b

if T1b == 0
	disp('Use default blood T1...');
	disp('T1b = 1.490 sec');
	T1b = 1.490; % T1 of blood (sec)
end

JSON = load_json(PLD_json);

% The following parameters are hard coded using parameters from
% Wang et al. (2012)
t = 1.5; % label time (sec)
lambda = 0.9; % blood/tissue water partition coefficient (g/mL)
alp = 0.8; % label efficiency
R1a = 1/T1b; % blood R1

% Calculate deltaM
ASL = load_nifti(rawData)

Mo_image = load_nifti(Mo); % equilibrium magnetization of brain
Mo = squeeze(Mo_image.vol(:,:,:));

[xSize,ySize,zSize,tSize] = size(ASL.vol);

deltaM = zeros(xSize,ySize,zSize);

if(mod(tSize,2))
   error('Uneven number of frames.'); 
end
numPair = tSize/2;
    
CBF_by_Pair = zeros(xSize,ySize,zSize,numPair);

FD = importdata(FD_tmask);

Pair = 1;
for ii = 1:2:tSize

    if(~(FD(ii) & FD(ii+1)))
        continue;
    end
    
    if(LC_CL)   %0 = control then label, 1 = label then control
        control = squeeze(ASL.vol(:,:,:,ii+1));
        label = squeeze(ASL.vol(:,:,:,ii));
    else
        control = squeeze(ASL.vol(:,:,:,ii));
        label = squeeze(ASL.vol(:,:,:,ii+1));
    end
    
    deltaM = deltaM + control - label;
    
    %compute the cbf by pair - this is noisy... probably
    exp1 = exp(-JSON.PostLabelingDelay(ii)*R1a);
    exp2 = exp(-(t+JSON.PostLabelingDelay(ii))*R1a);
    CBF_by_Pair(:,:,:,Pair) = 60*100*lambda*(control - label)*R1a ./ (2*alp*Mo* (exp1 - exp2) + eps);
    Pair = Pair + 1;
end

deltaM = deltaM/Pair;
%deltaM(find(deltaM<0)) = 0;
deltaM = deltaM .* brainMask;

CBF_by_Pair(isnan(CBF_by_Pair) | isinf(CBF_by_Pair)) = 0;

% Now calculate CBF 
CBF = mean(CBF_by_Pair(:,:,:,1:Pair), 4);

Mo.vol = CBF;

save_nifti(Mo, CBF_OutputFilename);
end