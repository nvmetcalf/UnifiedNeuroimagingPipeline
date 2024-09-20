function VolumeGrayPlotQC_v2(sub, tmaskfile, run_boundaries_filename, resid_bpss_nifti, aligned_nifti, volume_ribbon_mask, TR, fdfilename, dvarfilename, FigureFilenameRoot)

    if(~exist('FigureFilenameRoot'))
        FigureFilenameRoot = [];
    end

    tmask = importdata(tmaskfile);
    
    run_boundaries = importdata(run_boundaries_filename);
    run_boundaries(isnan(run_boundaries)) = [];
    
    run_start_frames = find(run_boundaries == 0);
    
    disp('Loading aligned time series...');
    raw_nifti = load_nifti(aligned_nifti);
    raw_nifti = reshape(raw_nifti.vol, raw_nifti.dim(2) * raw_nifti.dim(3) * raw_nifti.dim(4), []);

    disp('Loading cortical ribbon mask...');
    mask = load_nifti(volume_ribbon_mask);
    mask = reshape(mask.vol, mask.dim(2) * mask.dim(3) * mask.dim(4),[]);

    %remove voxels that are outside of the brain
    disp('Masking aligned timeseries by ribbon...');
    raw_nifti = raw_nifti(mask > 0,:);

    if(exist([resid_bpss_nifti]))
        disp('Loading denoised timeseries...');
        resid_nifti = load_nifti(resid_bpss_nifti);
        resid_nifti = reshape(resid_nifti.vol, resid_nifti.dim(2) * resid_nifti.dim(3) * resid_nifti.dim(4), []);
        
        disp('Masking denoised timeseries by ribbon...');
        resid_nifti = resid_nifti(mask > 0 ,:);
    else
        disp('No denoised timeseries specified or does not exist. Using zeroes as timeseries...');
        resid_nifti = zeros(size(raw_nifti));
    end

    clear mask;

    %make grey plots
    fignewton=figure;
    set(gcf,'Color',[1 1 1])
    time = 1:length(raw_nifti(1,:));

    ax1 = subplot(4,1,1)
    
    if(~isempty(fdfilename))
        data1 = importdata(fdfilename,' ');
        line(time,data1');
    end
    
    title('FD (blue) / DVAR (red) Timecourses');
    xlabel('Frame');
    ylim([0 1]);
    xlim([1 length(time)]);
    
    hold on
    ax1_sub1 = gca;
    set(gca,'XTick',[])
    set(ax1_sub1,'YColor','b')
    ax1_sub1_pos = get(ax1_sub1,'Position')
    ax1_sub2 = axes('Position',ax1_sub1_pos,'XAxisLocation','bottom','YAxisLocation','right','Color','none')
    
    if(~isempty(dvarfilename))
        DV = importdata(dvarfilename,' ');
        DV(DV>9)=1;
        line(time,DV,'Parent',ax1_sub2,'Color','r')
    end
    
    xlim([1 length(time)]);
    set(ax1_sub2,'YColor','r')
    
    ax1 = subplot(5,1,2)
    set(gca,'YTick',[]);
    xlabel('Frame');
    title(sprintf('Temporal Masking'));
    imagesc(tmask,[0 1]);
    xlim([1 length(time)]);
    ax2 = subplot(5,1,3)

    scale = std(raw_nifti')';
%     min_val = min(min(raw_nifti./scale));
%     max_val = max(max(raw_nifti./scale));
%     a = [];
%     for k = 1:length(raw_nifti(1,:))
%         a = horzcat(a, raw_nifti(:,k)./scale);
%     end
    imagesc(raw_nifti);
    xlim([1 length(time)]);
    colormap('gray');
    title('Atlas Aligned BOLD')
    xlabel('Frame');
    ax3 = subplot(5,1,4)
    

    scale = mean(std(resid_nifti'));
    
    imagesc(resid_nifti./scale,[-3 3]);
    xlim([1 length(time)]);
    xlabel('Frame');
    colormap('gray');
    title(['Detrend + Nuissance Regression (Movement, WB, WM, CSF, Vent) + Bandpass'])
    linkaxes([ax1,ax2],'x')
   
	disp('saving image');
	saveas(fignewton,[FigureFilenameRoot 'fc_QCfig.png'],'png')
    close(fignewton);
    %======================================================================
	% Look at power spectrum after filtering
    
    disp('Computing power for each run by voxel...');
    P_voxels = [];
    
    for j = 1:length(run_start_frames)
        
        run_start = run_start_frames(j);
        
        if(j == length(run_start_frames))
            run_end = length(resid_nifti(1,:));            
        else
            run_end = run_start_frames(j+1)-1;
        end
        
        run = resid_nifti(Voxels(i),run_start:run_end);
        run_tmask = tmask(run_start:run_end);
        
        NFFT = 2^nextpow2(length(run_tmask));
        F = (1/TR)/2*linspace(0,1,NFFT/2+1);   %frequencies
    
        L = length(run_tmask);
        
        Voxels = randi(length(run(:,1)),500,1);
        for k = 1:length(Voxels)
            P = fft(run(k,:),NFFT)/L;    %power complex
            P = 2*abs(P(1:NFFT/2+1));   %power one sided
            P_voxels = vertcat(P_voxels, P');
        end
        
    end
    
    meanP=nanmean(P_voxels);
    steP=std(P_voxels)/sqrt(size(P_voxels,1));
    
    figspect=figure
    boundedline(F,meanP,steP,'cmap',[0,0,0]); hold on
    title('rsfMRI Power Spectrum After Denoising');
    xlim([0.001 0.5*(1/TR)]);   %set max frequency to 1/2 sampling frequency (TR)
    xlabel('Frequency');ylabel('Power');
    disp('saving image');
    saveas(figspect,[FigureFilenameRoot 'fc_spectrum_denoised.pdf'],'pdf');

    save([FigureFilenameRoot 'fc_spectrum_denoised.mat'],'meanP','steP','F','P_voxels');
    
    close(figspect);
    %display the power spectra pre denoising
    P_voxels = [];
    for j = 1:length(run_start_frames)
        
        run_start = run_start_frames(j);
        
        if(j == length(run_start_frames))
            run_end = length(raw_nifti(1,:));            
        else
            run_end = run_start_frames(j+1)-1;
        end
        
        run = raw_nifti(Voxels(i),run_start:run_end);
        run_tmask = tmask(run_start:run_end);
        
        NFFT = 2^nextpow2(length(run_tmask));
        F = (1/TR)/2*linspace(0,1,NFFT/2+1);   %frequencies
    
        L = length(run_tmask);
        
        Voxels = randi(length(run(:,1)),500,1);
        for k = 1:length(Voxels)
            P = fft(run(k,:),NFFT)/L;    %power complex
            P = 2*abs(P(1:NFFT/2+1));   %power one sided
            P_voxels = vertcat(P_voxels, P');
        end
        
    end
        
    meanP=nanmean(P_voxels);
    steP=std(P_voxels)/sqrt(size(P_voxels,1));
    
    figspect=figure
    boundedline(F,meanP,steP,'cmap',[0,0,0]); hold on
    title('rsfMRI Power Spectrum Before Denoising');
    xlim([0.001 0.5*(1/TR)]);   %set max frequency to 1/2 sampling frequency (TR)
    xlabel('Frequency');ylabel('Power');
    disp('saving image');
    saveas(figspect,[FigureFilenameRoot 'fc_spectrum_raw.pdf'],'pdf');

    save([FigureFilenameRoot 'fc_spectrum_raw.mat'],'meanP','steP','F','P_voxels');
    close(figspect);
end