function [Un, Gn, Up, Gp] = moh_FCP_outliers(XP, XC, Alpha, Lambda, write_positive)
% function for outliers detection
% based on FCP approach (Fuzzy Clustering with fixed Prototype)
% assess both negative (abnormaly low) and positive (abnormaly high) effects 
% input:
% -------
%   XP: data of a single patient
%   XC: data of all controls (matrix nvox x nsubj)
%   Alpha: parameter of sensitivity (i.e. how far is the outlier effect )
%   Lambda: degree of fuzziness
%   write_positive: write (Yes/No) FCP_positive images (not used for lesions)
% output:
% -------
%   Up: image for positive outliers (high effects), optional
%   Un: image for negative outliers (low effects)
%   Gp: Global positive outliers (high effects) (for illustration), optional
%   Gn: Global negative outliers (low effects) (for illustration)
%
% for more details see: Seghier et al. Neuroimage 2007
% ----------------------------
% Mohamed Seghier, 17.01.2008
%

% if ~isstruct(vp), vp = spm_vol(vp) ; end
% 
% 
% if isempty(Vol),
%     error('ERROR: Plesae check that your mask is not empty...!!') ;
%     return ;
% end

if not(size(XC,1) == size(XP,1)),
    error('ERROR: Plesae check that images have the same size...!!') ;
    return ;
end
    

Nvox = size(XC, 1) ;
c = size(XC, 2) + 1 ;

if nargin==2
    Lambda = -4 ; % default value of the fuzziness degree
    Alpha = 3*std(XC(:)) ; % approx of the variance of controls
    disp(['## Alpha is set to  = ', num2str(Alpha)]) ;
    write_positive = 0 ; % whether to write FCP_positive images 0/1
end


% centroid definition
V = Alpha*eye(c) ;

% distance calculation (TANH)
bet = ([XP, XC]' - repmat(sum([XP, XC]')/c, c,1))'*...
    (V' - repmat(sum(V')/c, c,1)) ./(c-1) ;
bet = bet ./ repmat(var(V'),Nvox ,1) ;
D = (1 - tanh(bet)) ;
D(D == 0) = eps ;

% membership degrees calculation for positive (high) effects
Up = []; 
Gp = [] ;
if write_positive
U = [] ;
U = ( power(D, Lambda) ./ repmat(sum(power(D, Lambda)'), c,1)')' ;

Gp = sum(U')/Nvox ;
Up = U(1,1:Nvox) ;

%disp('### abnormal high (positive) effects (Patient > Controls)..........OK')
end

% membership degrees calculation for negative (low) effects
U = [] ;
U = ( power(2-D, Lambda) ./ repmat(sum(power(2-D, Lambda)'), c,1)')' ;

Gn = sum(U')/Nvox ;


Un = U(1,1:Nvox) ;

%disp('### abnormal low (negative) effects (Patient < Controls)..........OK')


return ;

