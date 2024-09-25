
function [CBF CBF_by_Pair numPair Pairwise_FD Mo]=cbf_pasl(rawPcasl,brainMask, w, TI1, T1b, TR, FD, FD_Thresh)

% Calculate CBF for 3D pCASL
% CBF data are calculated according to the formula from

% Input
% rawPcasl: 4D pCASL image. First Mo, then Label/Control pairs (L first)
% brainMask: 3D brain mask
% w: post-labeling delay (sec) - ie TI
% t1b: blood t1 value (sec), default (for 3T system): 1.665 for ances black
% TI1 - labeling time (0.7s for ances black)
% TR - repitition time in seconds (2.6s for ances black). Needed to know if
% the Mo needs to be scaled
% FD - list of displacement values between all volumes. Used to throw out
% pairs if there is too much movement

% Output
% CBF: calculated CBF value


if T1b == 0
	disp('Use default blood T1...');
	disp('T1b = 1.490 sec');
	T1b = 1.490; % T1 of blood (sec)
end

% The following parameters are hard coded using parameters from
% https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5964483/

lambda = 0.9; % blood/tissue water partition coefficient (g/mL)
alp = 0.95; % label efficiency

% Calculate deltaM
rawPcasl = double(rawPcasl);
brainMask = double(brainMask);
Mo = squeeze(rawPcasl(:,:,:,1)); % equilibrium magnetization of brain
%Mo(brainMask == 0 | isnan(brainMask)) = 0;

if(TR < 5)
    %scale the Mo as the TR is less than 5s
    Mo = Mo * (1/(1 - exp(-TR/1.3)));
end

[xSize,ySize,zSize,tSize] = size(rawPcasl);
deltaM = zeros(xSize,ySize,zSize);
numPair = (tSize-1)/2;

CBF = zeros(xSize,ySize,zSize);
CBF_by_Pair = zeros(xSize,ySize,zSize,numPair);
control = zeros(xSize,ySize,zSize);
label = zeros(xSize,ySize,zSize);

SliceTime = (TR - TI1 - w)/zSize;
Pairwise_FD = [];

for ii = 2:2:tSize
    Pairwise_FD = vertcat(Pairwise_FD, FD(ii));
    if(FD(ii+1) > FD_Thresh)
        disp([num2str(ii+1) ' : ' num2str(FD(ii+1))]);
        numPair = numPair - 1;
        
        continue;
    end
    
    
    control = control + squeeze(rawPcasl(:,:,:,ii+1));
    label = label + squeeze(rawPcasl(:,:,:,ii));
    %deltaM = deltaM + control - label;
    
    c = squeeze(rawPcasl(:,:,:,ii+1));
    l = squeeze(rawPcasl(:,:,:,ii));
    %compute the cbf by pair - this is noisy... probably
    scale_factors = 6000*lambda;
    c_min_l = c - l;
    
    for j = 1:zSize
        exponent = exp((w + (j*SliceTime))/T1b);
    
        CBF_by_Pair(:,:,j,ii/2) =(scale_factors * c_min_l(:,:,j) * exponent)./(2*alp*TI1*Mo(:,:,j));
    end
end

deltaM = (control/numPair) - (label/numPair);
%deltaM(find(deltaM<0)) = 0;
deltaM(brainMask == 0 | isnan(brainMask)) = 0;

% Now calculate CBF- this is from the FSL group
for j = 1:zSize
    CBF(:,:,j) = (6000*lambda*deltaM(:,:,j)*exp((w + (j*SliceTime))/T1b))./(2*alp*Mo(:,:,j)*TI1);
end

CBF(isnan(CBF) | isinf(CBF)) = 0;
% a = (lambda*deltaM);
% b = (2*alp*Mo*0.700*exp(-1.800/1.664));
% CBF = a./b;



