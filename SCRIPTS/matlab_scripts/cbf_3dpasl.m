
function [CBF CBF_by_Pair numPair Mo]=cbf_3dpasl(rawData, Mo_Filename, PLD_json, T1b, TR, FD_tmask, LC_CL, CBF_OutfileName)

% Calculate CBF for 3D pCASL
% CBF data are calculated according to the formula from

% Input
% rawPcasl: 4D pCASL image. Only label/control images
% Mo - M0 image
% w: post-labeling delay (sec) - ie TI
% t1b: blood t1 value (sec), default (for 3T system): 1.665 for ances black
% TI1 - labeling time (0.7s for ances black)
% TR - repitition time in seconds (2.6s for ances black). Needed to know if
% the Mo needs to be scaled
% FD_tmask - file containing encoding the frames to use. 
% CBF_OutfileName - Filename of the mean CBF output

% Output
% CBF: calculated CBF value


if T1b == 0
	disp('Use default blood T1...');
	disp('T1b = 1.6 sec');
	T1b = 1.6; % T1 of blood (sec)
end

% The following parameters are hard coded using parameters from
% https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5964483/

lambda = 0.9; % blood/tissue water partition coefficient (mL/g)
alp = 0.85; % label efficiency

ASL = load_nifti(rawData)

Mo_image = load_nifti(Mo_Filename); % equilibrium magnetization of brain
Mo = Mo_image.vol;

FD = importdata(FD_tmask);

JSON = load_json(PLD_json);

[xSize,ySize,zSize,tSize] = size(ASL.vol);

if(mod(tSize,2))
   error('Uneven number of frames.'); 
end

deltaM = zeros(xSize,ySize,zSize);
numPair = tSize/2;

CBF = zeros(xSize,ySize,zSize);
CBF_by_Pair = zeros(xSize,ySize,zSize,numPair);
control = zeros(xSize,ySize,zSize);
label = zeros(xSize,ySize,zSize);

UsedPairs = 0;

TI = JSON.InversionTime;
TI1 = JSON.BolusDuration;

CBF_by_Pair = [];
for ii = 1:2:tSize-1
    
     if(~(FD(ii) & FD(ii+1)))
        continue;
     end
    
    
    k = alp * lambda;
    
    %compute the cbf by pair - this is noisy... probably
  
    if(LC_CL)   %0 = control then label, 1 = label then control
        control = squeeze(ASL.vol(:,:,:,ii+1));
        label = squeeze(ASL.vol(:,:,:,ii));
    else
        control = squeeze(ASL.vol(:,:,:,ii));
        label = squeeze(ASL.vol(:,:,:,ii+1));
    end
    
    delM = control - label;
    
    % Now calculate CBF
    %CBF_by_Pair = cat(4, CBF_by_Pair, (k * delM * 6000 * 0.8) ./ (Mo * T1b * PLD));
    CBF_by_Pair = cat(4, CBF_by_Pair, ((lambda .* delM) ./ (2 * Mo * alp * TI1 .* exp(-TI/T1b))));
    
%     for j = 1:zSize
%         exponent = exp((JSON.PostLabelingDelay(ii) + (j*SliceTime))/T1b);
%     
%         CBF_by_Pair(:,:,j,UsedPairs) =(scale_factors * c_min_l(:,:,j) * exponent)./(2*alp*TI1*Mo(:,:,j));
%     end
end

CBF(isnan(CBF_by_Pair) | isinf(CBF_by_Pair)) = 0;
% a = (lambda*deltaM);
% b = (2*alp*Mo*0.700*exp(-1.800/1.664));
% CBF = a./b;

Mo_image.vol = mean(CBF_by_Pair,4);
save_nifti(Mo_image, CBF_OutfileName);

end
