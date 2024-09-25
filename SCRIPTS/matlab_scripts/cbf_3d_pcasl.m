
function [CBF CBF_by_Pair numPair Pairwise_FD Mo]=cbf_3d_pcasl(rawPcasl, brainMask, w, T1b, FD, FD_Thresh)

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

if w == 0
	disp('Use default PLD...');
	disp('w = 1.2 sec');
	w = 1.2; % PLD (sec)
end

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

% Calculate deltaM
rawPcasl = double(rawPcasl);
brainMask = double(brainMask);
Mo = squeeze(rawPcasl(:,:,:,1)); % equilibrium magnetization of brain
%Mo = Mo .* brainMask;
[xSize,ySize,zSize,tSize] = size(rawPcasl);
deltaM = zeros(xSize,ySize,zSize);
numPair = tSize/2 - 1;

CBF_by_Pair = zeros(xSize,ySize,zSize,numPair);
Pairwise_FD = [];

exp1 = exp(-w*R1a);
exp2 = exp(-(t+w)*R1a);

for ii = 2:numPair+1
    Pairwise_FD = vertcat(Pairwise_FD, FD(ii));
    
    if(FD(2*ii) > FD_Thresh)
        disp([num2str(2*ii) ' : ' num2str(FD(2*ii))]);
        numPair = numPair - 1;
        
        continue;
    end
    
    control = squeeze(rawPcasl(:,:,:,2*ii));
    label = squeeze(rawPcasl(:,:,:,2*ii-1));
 
%    control = squeeze(rawPcasl(:,:,:,2*ii-1));
%    label = squeeze(rawPcasl(:,:,:,2*ii));
    
    deltaM = deltaM + control - label;
    
    %compute the cbf by pair - this is noisy... probably
    CBF_by_Pair(:,:,:,ii-1) = 60*100*lambda*(control - label)*R1a ./ (2*alp*Mo* (exp1 - exp2) + eps);
end
deltaM = deltaM / numPair;
%deltaM(find(deltaM<0)) = 0;
deltaM = deltaM .* brainMask;

CBF_by_Pair(CBF_by_Pair == 0) = NaN;

% Now calculate CBF 
CBF = 60*100*lambda*deltaM*R1a ./ (2*alp*Mo* (exp1 - exp2) + eps);

