%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

%%%ZMoment, DTEArr1 has to read from dicom files
%%%%try to load as many values as possible from dicom

%%%%TE1, TE2, TE3 are in seconds

%%if fitting_method == 1, conventional linear regression
%%if fitting_method == 2, matlab robust fitting
%%if fitting_method == 3, TheilSen robust fitting

function [imOEF, imLambda, imC, imR2, imR2P, imError] = computeOEF_3e_WithoutDB_mc(imASE1, imASE2, imASE3, maskArray, sign_motion1, sign_motion2, sign_motion3, Hct, TE1, TE2, TE3, B0, DTEArr1, ZMoment, echo_numbers_tobe_used, fitting_method, DB, maxDTE,dteThresh1,dteThresh2)

   % tic
   % disp('CY: Set up')
   %%%%turn off all the warnings
   warning('OFF', 'all');

   %%%%%%% deltaX0 = 0.18; %% OLD historical values
   deltaX0 = 0.19; %% Start to use from 2022.11

   DTE1 = TE2 - TE1;
   DTE2 = TE3 - TE2;

   %// Since we will work without DB correction, we select the data for which ZMoment = 0;
   %// In addition, we will also discard the motion points. So we check for inputs as well.

   nZeroZMoment = 0;
   for k=1:length(ZMoment),
      if ZMoment(k)==0 
         nZeroZMoment = nZeroZMoment+1;
      end;
   end;     
         
   DTEArr1_Trimmed = zeros(nZeroZMoment, 1);
   selectedIndices = zeros(nZeroZMoment, 1);

   ind = 1;
   for k=1:length(ZMoment),
      if ZMoment(k)==0 
         DTEArr1_Trimmed(ind) = DTEArr1(k);
         selectedIndices(ind) = k;
         ind=ind+1;
      end;
   end;

   DTEArr1 = DTEArr1_Trimmed;
   clear DTEArr1_Trimmed;

   % size(selectedIndices)
   % nZeroZMoment

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   %// Get from the user how many echoes to use.
   for k=1:nZeroZMoment,
      T1(k) = DTEArr1(k);
      T2(k) = T1(k)+DTE1;
      T3(k) = T2(k)+DTE2;
   end;

   ind=1;
   for k=1:nZeroZMoment
      T_ve(ind) = T1(k);
      ind = ind+1;
   end;

   for k=1:nZeroZMoment
      T_ve(ind) = T2(k);
      ind = ind+1;
   end;
   
   for k=1:nZeroZMoment
      T_ve(ind) = T3(k);
      ind = ind+1;
   end;

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   %// Get TEi_ve=TEi*ones(Num,1) for i = 1,2,3
   TE1_ve = ones(length(T1), 1)*TE1;
   TE2_ve = ones(length(T1), 1)*TE2;
   TE3_ve = ones(length(T1), 1)*TE3;   

   ind=1;
   for k=1:nZeroZMoment,
      TE_ve(ind) = TE1_ve(k);
      ind = ind+1;
   end;

   for k=1:nZeroZMoment,
      TE_ve(ind) = TE2_ve(k);
      ind = ind+1;
   end;
   
   for k=1:nZeroZMoment,
      TE_ve(ind) = TE3_ve(k);
      ind = ind+1;
   end;

   switch echo_numbers_tobe_used
      case 1
         T_ve = T_ve(1:length(T1));
         TE_ve = TE_ve(1:length(T1));
     case 2
         T_ve = T_ve(1:2*length(T1));
         TE_ve = TE_ve(1:2*length(T1));
     case 3
         T_ve = T_ve(1:3*length(T1));
         TE_ve = TE_ve(1:3*length(T1));
   end;

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   gamma = 267.5;
   Y_coef = (4.0/3.0*pi*gamma*deltaX0*Hct*B0);

   Tc1 = dteThresh1;
   L_short = 0;

   for k=1:length(T_ve),
      if abs(T_ve(k))<=Tc1
         L_short = L_short+1;
      end;
   end;

   ind = 1; 
   for k=1:length(T_ve),
      if abs(T_ve(k))<=Tc1
         T_short(ind) = T_ve(k);
         shortterm_Pts(ind) = k;
         ind=ind+1;
      end;
   end;

   fprintf('- Short Term: %s Frames\n',num2str(ind-1));

   %// M_short = T_short.^2; But with the column of 1's, it becomes a 2-column matrix.
   %// Please note that matlab's robustfit uses the 1-column version and then prepends a column of 1's for the intercept
   %// So here, we start by a matrix of 1's that is of size Nx2. Then we modify the 2nd column.
   
   %// Long term
   Tc2 = dteThresh2;
   L_long = 0;


   for k=1:length(T_ve),
      if abs(T_ve(k))>=Tc2 && abs(T_ve(k)) <= maxDTE
         L_long = L_long+1;
      end;
   end; 

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   ind = 1;
   for k=1:length(T_ve),
      if abs(T_ve(k))>=Tc2  && abs(T_ve(k)) <= maxDTE
         T_long(ind) = T_ve(k);
         abs_T_long(ind) = abs(T_ve(k));
         TE_long(ind) = TE_ve(k);
         longterm_Pts(ind) = k;
         ind=ind+1;
      end;
   end;

   fprintf('- Long Term: %s Frames\n',num2str(ind-1));
        
   %// M_long = [-TE_long -abs(T_long)]; <-- A two-column matrix! But with the column of 1's, it becomes a 3-column matrix.
   %// Please note that matlab's robustfit uses the 2-column version and then prepends a column of 1's for the intercept
   %// So here, we start by a matrix of 1's that is of size Nx3. Then we modify the 2nd and the 3rd columns.

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   numOfSlices = size(imASE1, 3);
   Width = size(imASE1, 1);
   Height = size(imASE1, 2);

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   imOEF = zeros(Width, Height, numOfSlices);
   imLambda = zeros(Width, Height, numOfSlices);
   imC = zeros(Width, Height, numOfSlices);   
   imR2 = zeros(Width, Height, numOfSlices);
   imR2P =  zeros(Width, Height, numOfSlices);
   imError = zeros(Width, Height, numOfSlices);
   
   if echo_numbers_tobe_used == 1
      sign_motion = sign_motion1;
   end;

   if echo_numbers_tobe_used == 2
      sign_motion = [sign_motion1' sign_motion2']';
   end;

   if echo_numbers_tobe_used == 3
      sign_motion = [sign_motion1' sign_motion2' sign_motion3']';
   end;
   fprintf('Excluded frames due to motion: %d\n',sum(sign_motion(:)));

   % toc
   % disp('CY: Fitting')
   % tic;
   if sum(T_short)==0
      disp('- All short term frames are Spin Echo')
   end
   for x=1:Width

      for y=1:Height
         for z = 1:numOfSlices
         %for z=round(numOfSlices/2):round(numOfSlices/2)
            if maskArray(x,y,z) == 0
               continue;
            end;
            

            S = zeros(3*nZeroZMoment, 1);

            for k=1:nZeroZMoment,
               SINC1(k) = sinc(0.5*gamma*DB(x,y,z)*T1(k)/pi/pi);
               SINC2(k) = sinc(0.5*gamma*DB(x,y,z)*T2(k)/pi/pi);
               SINC3(k) = sinc(0.5*gamma*DB(x,y,z)*T3(k)/pi/pi);
               S(k) = imASE1(x,y,z,selectedIndices(k))/(SINC1(k)+eps);
               S(nZeroZMoment+k) = imASE2(x,y,z,selectedIndices(k))/(SINC2(k)+eps);
               S(2*nZeroZMoment+k) = imASE3(x,y,z,selectedIndices(k))/(SINC3(k)+eps);
            end;

            switch echo_numbers_tobe_used
               case 1,
                  S = S(1:length(T1));
               case 2,
                  S = S(1:2*length(T1));
               case 3,
                  S = S(1:3*length(T1));                  
            end;

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            S_long = S(longterm_Pts);
            sign_motion_long = sign_motion(longterm_Pts);

            positiveIndices = find(S_long>0 &sign_motion_long == 0);

            if(length(positiveIndices)==0)
               clear S SINC1 SINC2 SINC3 S_long sign_motion_long positiveIndices;
               continue;
            end;
            
            for k=1:length(positiveIndices),
               S_L(k) = S_long(positiveIndices(k));

               switch echo_numbers_tobe_used
                  case 1
                     M_L(k) = -abs(T_long(positiveIndices(k)));
                     M_L_with1(k,1) = 1;
                     M_L_with1(k,2) = M_L(k);

                     TS_L(k, 1) = M_L_with1(k,1);
                     TS_L(k, 2) = M_L_with1(k,2);
                     TS_L(k, 3) = log(S_L(k));
                  case 2
                     M_L(k, 1) = -TE_long(positiveIndices(k));
                     M_L(k, 2) = -abs(T_long(positiveIndices(k)));

                     M_L_with1(k, 1) = 1;
                     M_L_with1(k, 2) = -TE_long(positiveIndices(k));
                     M_L_with1(k, 3) = -abs(T_long(positiveIndices(k)));

                     TS_L(k, 1) = M_L_with1(k,1);
                     TS_L(k, 2) = M_L_with1(k,2);
                     TS_L(k, 3) = M_L_with1(k,3);
                     TS_L(k, 4) = log(S_L(k));
                  case 3
                     M_L(k, 1) = -TE_long(positiveIndices(k));
                     M_L(k, 2) = -abs(T_long(positiveIndices(k)));

                     M_L_with1(k, 1) = 1;
                     M_L_with1(k, 2) = -TE_long(positiveIndices(k));
                     M_L_with1(k, 3) = -abs(T_long(positiveIndices(k)));

                     TS_L(k, 1) = M_L_with1(k,1);
                     TS_L(k, 2) = M_L_with1(k,2);
                     TS_L(k, 3) = M_L_with1(k,3);
                     TS_L(k, 4) = log(S_L(k));
               end;
            end;

            LnS_L = log(S_L);

            %%%%CBIrobust fit
            %B1 = CBIrobustfit(M_L, LnS_L');

            switch fitting_method,
               case 1
                  B1 = regress(LnS_L', M_L_with1);
               case 2
                  try 
                     B1 = robustfit(M_L, LnS_L');
                  catch ME
                     B1 = regress(LnS_L', M_L_with1);
                  end;
               case 3
                  %B1 = TheilSen(TS_L);
                   B1 = CBIrobustfit(M_L_with1, LnS_L');
            end;

            switch echo_numbers_tobe_used,
               case 1,
                 imR2(x,y,z) = 0;
                 imR2P(x,y,z) = B1(2);
               case 2,
                 imR2(x,y,z) = B1(2);
                 imR2P(x,y,z) = B1(3);
               case 3,
                 imR2(x,y,z) = B1(2);
                 imR2P(x,y,z) = B1(3);
            end;

            clear S_L LnS_L M_L M_L_with1 S_long sign_motion_long positiveIndices TS_L;
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            S_short = S(shortterm_Pts);
            sign_motion_short = sign_motion(shortterm_Pts);
            positiveIndices = find(S_short>0 & sign_motion_short == 0);

            if(length(positiveIndices)==0)
               clear S SINC1 SINC2 SINC3 S_short sign_motion_short positiveIndices;               
               continue;
            end;

            for k=1:length(positiveIndices),
               S_S(k) = S_short(positiveIndices(k));
               M_S(k) = T_short(positiveIndices(k))*T_short(positiveIndices(k));
               M_S_with1(k,1) = 1;
               M_S_with1(k,2) = M_S(k);

               TS_S(k,1) = 1;
               TS_S(k,2) = M_S(k);
            end;

            LnS_S = log(S_S);

            for k=1:length(positiveIndices),
               YY(k) = LnS_S(k)+imR2(x,y,z)*TE1;
               TS_S(k,3) = YY(k);
            end;

            %%%%CBIrobust fit
            %%B2 = CBIrobustfit(M_S, YY');       
            switch fitting_method
               case 1 
                  B2 = regress(YY', M_S_with1);
               case 2
                  try
                      B2 = robustfit(M_S, YY');
                  catch
                     B2 = regress(YY', M_S_with1);
                  end;
               case 3
                  %B2 = TheilSen(TS_S);
                  B2 = CBIrobustfit(M_S_with1, YY');
            end;

            if sum(T_short)==0
               imLambda(x,y,z) = B1(1)-median(YY); %% use median of YY instead of fitting
            else
               imLambda(x,y,z) = B1(1)-B2(1);
            end

            if(imR2P(x,y,z)/(imLambda(x,y,z)*Y_coef)<1)
               imOEF(x,y,z) = imR2P(x,y,z)/(imLambda(x,y,z)*Y_coef);
            else
               imOEF(x,y,z) = 1;
            end;

            imC(x,y,z) = exp(B2(1));

            if imOEF(x,y,z)<0 | imLambda(x,y,z)<0.005
               imOEF(x,y,z)=0.05;
               imLambda(x,y,z)=0.005;
            end;

            if imOEF(x,y,z)>1
               imOEF(x,y,z)= 1;
            end;
            
            clear S_S M_S M_S_with1 LnS_S YY B1 B2 S_short sign_motion_short positiveIndices TS_S;

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            clear S SINC1 SINC2 SINC3;

         end;
      end;   
   end;
   
   % toc
   % tic;
   % disp('CY: Error')
   %%%%%%calculate fit error
   num_intervals = 1000;
   delta_interval = 1/num_intervals;
   u = zeros(num_intervals, 1);

   for i=1:num_intervals,
      u(i) = (i-1)*delta_interval;
   end;

   uu = u.*u;
   sqrtu = sqrt(1-u);

   % tic;

   %%%15, 12, 18 erros

   for x=1:Width,
      for y=1:Height,
         for z = 1:numOfSlices,
         %for z=round(numOfSlices/2):round(numOfSlices/2), %for z = 1:numOfSlices,
            if maskArray(x,y,z) == 0
               continue;
            end;

            S = zeros(3*nZeroZMoment, 1);

            for k=1:nZeroZMoment,
               %SINC1(k) = sinc(0.5*gamma*DB(x,y,z)*T1(k)/pi/pi);
               %SINC2(k) = sinc(0.5*gamma*DB(x,y,z)*T2(k)/pi/pi);
               %SINC3(k) = sinc(0.5*gamma*DB(x,y,z)*T3(k)/pi/pi);
               %S(k) = imASE1(x,y,z,selectedIndices(k))/(SINC1(k)+eps);
               %S(nZeroZMoment+k) = imASE2(x,y,z,selectedIndices(k))/(SINC2(k)+eps);
               %S(2*nZeroZMoment+k) = imASE3(x,y,z,selectedIndices(k))/(SINC3(k)+eps);

               SINC(k) = sinc(0.5*gamma*DB(x,y,z)*T1(k)/pi/pi);
               SINC(nZeroZMoment+k) = sinc(0.5*gamma*DB(x,y,z)*T2(k)/pi/pi);
               SINC(2*nZeroZMoment+k) = sinc(0.5*gamma*DB(x,y,z)*T3(k)/pi/pi);

               S(k) = imASE1(x,y,z,selectedIndices(k));
               S(nZeroZMoment+k) = imASE2(x,y,z,selectedIndices(k));
               S(2*nZeroZMoment+k) = imASE3(x,y,z,selectedIndices(k));
            end;

            switch echo_numbers_tobe_used
               case 1,
                  S = S(1:length(T1));
                  SINC = SINC(1:length(T1));
               case 2,
                  S = S(1:2*length(T1));
                  SINC = SINC(1:2*length(T1));
               case 3,
                  S = S(1:3*length(T1));                  
                  SINC = SINC(1:3*length(T1));
            end;

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

            I = find(S>0 & sign_motion==0);

            %if length(I) < 3*nZeroZMoment
            %   continue;
            %end;
             
            delta_w = Y_coef * imOEF(x,y,z);

            tempf = delta_w*T_ve(I);                   %disp('1'); size(tempf)
            tempu = (2+u).*sqrtu./(uu+eps);            %disp('2'); size(tempu)
            tempf1 = 1-besselj(0, 1.5*tempf'*u');      %disp('3'); size(tempf1)
            tempf2 = tempf1 * tempu;                   %disp('4'); size(tempf2)
            temps = sum(tempf2, 2) * delta_interval/3; %disp('5'); size(temps)

            tempf1 = -imR2(x,y,z)*TE_ve(I);            %disp('6'); size(tempf1)
            tempf2 = -imLambda(x,y,z)*temps;           %disp('7'); size(tempf2)

            s_fitted = imC(x,y,z)*exp(tempf1+tempf2').*SINC(I);

            %for i=1:length(I),
            %   tempf = delta_w*T_ve(I(i));
            %   tempf_int = (2+u).*sqrtu.*(1-besselj(0, 1.5*tempf*u))./(uu+eps);
            %   tempf_int_sum = sum(tempf_int)*delta_interval/3;

            %   s_fitted(i) = imC(x,y,z)*exp(-imR2(x,y,z)*TE_ve(I(i))-imLambda(x,y,z)*tempf_int_sum)*SINC(I(i));
            %end;

            %a=abs(s_fitted1-s_fitted);
            %max(a)
            %min(a)

            s_fitted = s_fitted - S(I)';
            s_fitted = s_fitted.*s_fitted;
            imError(x,y,z) = sqrt(sum(s_fitted)/length(I));
            
            clear S SINC S_fitted I tempf tempf1 tempf2 tempu;

         end;
      end;   
   end;
   % toc

