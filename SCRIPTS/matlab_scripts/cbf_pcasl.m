
function [CBF CBF_by_Pair numPair Pairwise_FD Mo]=cbf_pcasl(rawPcasl, brainMask, PLD_Json, T1b, FD, FD_Thresh)

% Calculate CBF for 2D pCASL
% CBF data are calculated according to the formula from

% http://www.ncbi.nlm.nih.gov/pmc/articles/PMC5351809

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

t = 1; % bolus time (msec)

PLDs = load_json(PLD_json); %in ms

%scale PLDs to ms if necessary
if(PLDs.PostLabelingDelay(1) < 100)
   PLDs.PostLabelingDelay = PLDsPostLabelingDelay .* 1000; 
end
lambda = 0.9; % whole brain blood/tissue water partition coefficient (g/mL)
alp = 0.86; % label efficiency

% Calculate deltaM
[xSize,ySize,zSize,tSize] = size(rawPcasl);
rawPcasl = reshape(rawPcasl,[],tSize);
brainMask = reshape(brainMask,[],1);

%Find out if we have a real M0 or need to estimate
if(mod(tSize,2) == 1)
    %it's an odd length, assume first frame is M0
    Mo = rawPcasl(:,1);
    rawPcasl(:,1) = [];
    tSize = tSize - 1;
 else
    Mo = rawPcasl(:,1);
    rawPcasl(:,1:2) = [];
    tSize = tSize - 2;
end

deltaM = zeros(length(brainMask),1);
numPair = tSize-1/2;

CBF_by_Pair = zeros(length(brainMask),numPair);
Pairwise_FD = [];

for ii = 2:numPair
    Pairwise_FD = vertcat(Pairwise_FD, FD(ii));
    control = rawPcasl(:,2*ii);
    label = rawPcasl(:,2*ii-1);
    
    if(FD(2*ii) > FD_Thresh)
        disp([num2str(2*ii) ' : ' num2str(FD(2*ii))]);
        numPair = numPair - 1;
        
    else
        deltaM = deltaM + (control - label);
    end
    
    %compute the cbf by pair - this is noisy... probably
    %CBF_by_Pair(:,:,:,ii-1) = 60*100*lambda*(control - label)*R1a ./ (2*alp*Mo* (exp1 - exp2) + eps);
    CBF_by_Pair(:,ii) = (6000 * lambda * (control - label) * (exp(PLDs.PostLabelingDelay(ii)/T1b)))./(2 * alp * T1b * Mo * (1 - exp(-t/T1b)));
end
deltaM = deltaM ./ numPair;
%deltaM(find(deltaM<0)) = 0;
deltaM = deltaM .* brainMask;

CBF_by_Pair(CBF_by_Pair == 0) = NaN;

% Now calculate CBF 
CBF = (6000 * lambda * deltaM * exp(PLD/T1b))./(2 * alp * T1b * Mo * (1 - exp(-t/T1b)));

CBF = reshape(CBF, xSize, ySize, zSize);
CBF_by_Pair = reshape(CBF_by_Pair, xSize, ySize, zSize, tSize/2);

Mo = reshape(Mo, xSize, ySize, zSize);

%T2a = 50;
%p = 1.05;
%TE = 9;

%CBF = 60*100*lambda*deltaM*R1a ./ (2*alp*Mo* (exp1 - exp2) + eps);
%upper = (deltaM) * exp(w/T1b)*exp(TE/T2a);
%lower = p * Mo * 2 * alp * T1b;

%CBF = 6000 * (upper./lower);
