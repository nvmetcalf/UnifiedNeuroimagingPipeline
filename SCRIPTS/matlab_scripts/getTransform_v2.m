function [H,f,s,c,tau,w] = getTransform_v2(t,h,TH,ofac,hifac)

%Input t is a column vector listing the time points for which observations
%are present.  Input h is a matrix with observations in columns and the
%number of rows equals the number the time points.  For our purposes number
%of voxels = number of columns.  Ofac = oversampling frequency (generally
%>=4), hifac = highest frequency allowed.  hifac = 1 means 1*nyquist limit
%is highest frequency sampled.  
%Lasted edited:  Anish Mitra, October 25 2012

%Edited by Nicholas Metcalf for efficient use of memory. 
%   about 40GB peak on FCS_083_C to about 13GB peak on FCS_083_C

% T is vector of frames at which you have good data
% h is the raw timecourses t x voxels
% TH is the time steps (frame*TR)
% generally want to set ofac=4 and hifac=1

N = size(h,1); %Number of time points
T = max(t) - min(t); %Total time span

%calculate sampling frequencies
f = (1/(T*ofac):1/(T*ofac):hifac*N/(2*T)).';

clear T;

%angular frequencies and constant offsets
w = 2*pi*f;

tau = atan2(sum(sin(2*w*t.'),2),sum(cos(2*w*t.'),2))./(2*w);

%spectral power sin and cosine terms
cterm = cast(cos(w*t.' - repmat(w.*tau,1,length(t))),'single');
sterm = cast(sin(w*t.' - repmat(w.*tau,1,length(t))),'single');

num_tseries = int32(size(h,2)); %Number of time series

% D = bsxfun(@minus,h,mean(h));  %This line involved in normalization
%D = h;
D = reshape(h,1,N,num_tseries);

clear N num_tseries;
%% C_final = (sum(Cmult,2).^2)./sum(Cterm.^2,2);
% This calculation is done by separately for the numerator, denominator,
% and the division

%rewrite the above line with bsxfun to optimize further?
%bsxfun(@power,sum(Cmult,2),2) = sum(Cmult.^2,2) = numerator
% numerator = bsxfun(@power,sum(Cmult,2),2);
%numerator = sum(bsxfun(@times, cterm,D),2); %Modify the numerator to get the cw term

%sum(bsxfun(@power,Cterm,2),2) = sum(Cterm.^2,2) = denominator
%denominator = sum(bsxfun(@power,cterm,2),2); %use Cterm in place of cterm to make it exactly the denominator in the original expression
c = bsxfun(@rdivide,sum(bsxfun(@times, cterm,D),2),sum(bsxfun(@power,cterm,2),2));
%c = C_final_new;
clear numerator denominator cterm Cmult C_final_new

%% Repeat the above for Sine term
%Smult = bsxfun(@times, sterm,D); - moved higher in the code for efficiency
% S_final = (sum(Smult,2).^2)./sum(Sterm.^2,2);
% numerator = bsxfun(@power,sum(Smult,2),2);
%numerator = sum(bsxfun(@times, sterm,D),2); %Modify the numerator to get the sw term
%denominator = sum(bsxfun(@power,sterm,2),2);
s = bsxfun(@rdivide,sum(bsxfun(@times, sterm,D),2),sum(bsxfun(@power,sterm,2),2));
%s = S_final_new;
clear numerator denominator sterm Smult S_final_new D

% %% Power = C_final + S_final; 
% Power = C_final_new + S_final_new;
% Power_reshaped = reshape(Power,size(Power,1),num_tseries);
% Power_final = bsxfun(@rdivide,Power_reshaped,2*var(h)); %Normalize the power
% clearvars -except Power_final f


% The inverse function to re-construct the original time series
%Time = TH';
%T_rep = repmat(TH',[size(f,1),1,size(h,2)]);
% T_rep = bsxfun(@minus,T_rep,tau);
% s(200) = s(199);
%w = 2*pi*f;
%prod = bsxfun(@times,repmat(TH',[size(f,1),1,size(h,2)]),w);
% sin_t = sin(prod);
% cos_t = cos(prod);

S = sum(bsxfun(@times,sin(bsxfun(@times,repmat(TH',[size(f,1),1,size(h,2)]),w)),s));
C = sum(bsxfun(@times,cos(bsxfun(@times,repmat(TH',[size(f,1),1,size(h,2)]),w)),c));
clear prod

% S = sum(sw_p);
% clear sw_p 
% 
% C = sum(cw_p);
% clear cw_p 

H = C + S;

clear C S

H = reshape(H,size(TH',2),size(h,2));

%Normalize the reconstructed spectrum, needed when ofac > 1
Std_H = std(H);
Std_h = std(h);

clear h

norm_fac = Std_H./Std_h;
H = bsxfun(@rdivide,H,norm_fac);
end