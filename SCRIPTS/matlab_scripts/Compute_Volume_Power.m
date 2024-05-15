function [Volume_Power F] = Compute_Volume_Power(BOLD_in, TR, TemporalMask, Run_Boundaries)
    timeseries = load_nifti(BOLD_in);
    
    timeseries_dims = timeseries.dim;
    
    Run_Boundaries_tmask = importdata(Run_Boundaries);
    Run_Boundaries_tmask(1) = [];
    tmask = importdata(TemporalMask);
    
    timeseries.vol = reshape(timeseries.vol, timeseries.dim(2) * timeseries.dim(3) * timeseries.dim(4),timeseries.dim(5));
      
    Volume_Power(1).Frequences = [];
    Volume_Power(1).Power = [];
        
    %interpolate over censored frames for each run
    RunBoundariesIndices = find(Run_Boundaries_tmask == 0);
    if(length(RunBoundariesIndices) > 1)
        RunBoundariesIndices = vertcat(RunBoundariesIndices, [RunBoundariesIndices(2:end)-1 timeseries_dims(5)]);
    else
        RunBoundariesIndices = vertcat(RunBoundariesIndices, timeseries_dims(5));
    end
    
    disp('Interpolating over censored frames...');
    
    for i = 1:length(RunBoundariesIndices(1,:))
        run = timeseries.vol(:, [RunBoundariesIndices(1,i):RunBoundariesIndices(2,i)]);
        run_tmask = tmask(RunBoundariesIndices(1,i):RunBoundariesIndices(2,i));
        
        j = 1;
        while(j <= length(run_tmask))
            
            if(run_tmask(j) == 0)
                if(j == 1)
                    %first sample, set it to 0
                    StartVolume = zeros(length(run(:,1)), 1);
                    interp_start = 1;
                elseif(j > 1)
                    interp_start = j-1;
                    StartVolume = run(:, interp_start);
                end
            
                %find the end of the censoring
                found_end = false;
                while(run_tmask(j) == 0 && j <= length(run_tmask))
                    j = j + 1;
                end
                                    
                interp_end = j;
                EndVolume = run(:,interp_end);
                                
                for k = 1:length(run(:,1))
                  
                    try
                        run(k, interp_start:interp_end) = interp1([interp_start interp_end], [StartVolume(k) EndVolume(k)], [interp_start:interp_end], 'linear');
                    catch
                        disp('error');
                    end
                end
            end   
            j = j + 1;
        end
        timeseries.vol(:, [RunBoundariesIndices(1,i):RunBoundariesIndices(2,i)]) = run;
    end
    
    disp('Computing defined voxel power by run...');
   
    run = 1;
    
    for i = 1:length(RunBoundariesIndices(1,:))
        run = timeseries.vol(:, [RunBoundariesIndices(1,i):RunBoundariesIndices(2,i)]);
        run_tmask = tmask(RunBoundariesIndices(1,i):RunBoundariesIndices(2,i));
          
        L = length(run_tmask);
    
        NFFT = 2^nextpow2(length(run_tmask));
        F = (1/TR)/2*linspace(0,1,NFFT/2+1);   %frequencies we will compute power for
    
        Volume_Power(i).Frequences = F;
        Volume_Power(i).Power = zeros(length(timeseries.vol(:,1)),length(F));
        Volume_Power(i).Timeseries_Dims = timeseries_dims;
        
        for j = 1:length(run(:,1))
            %compute entire power
            P = fft(run(j,:),NFFT)/L;    %power complex
            P = 2*abs(P(1:NFFT/2+1));   %power one sided
            
            %add the power to our output
            try
                Volume_Power(i).Power(j,:) = P;
            catch
                disp('oops');
            end
        end
    end
end