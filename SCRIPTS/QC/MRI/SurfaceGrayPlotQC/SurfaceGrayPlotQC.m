function SurfaceGrayPlotQC(sub,tmaskfile,resid_bpss_dtseries, resid_dtseries,dtseries,TR,fdfilename,dvarfilename,FigureFilenameRoot)
         
%sub = 'FCS_PILOT'
%FCdir = '/data/nil-bluearc/corbetta/Studies/SurfPipeTest/Subjects/FCS_PILOT/FCmaps_uwrp'
%tmaskfile ='tmask.txt'
%resid_dtseries = 'FCS_PILOT_faln_dbnd_xr3d_uwrp_atl_uout_sr_bpss.ctx.dtseries.nii'
%dtseries = 'FCS_PILOT_faln_dbnd_xr3d_uwrp_atl_uout.ctx.dtseries.nii'
%TR = 1;

%fdfilename=[ '/data/nil-bluearc/corbetta/Studies/SurfPipeTest/Subjects/FCS_PILOT/movement/' sub '.dvals'];

if(~exist('FigureFilenameRoot'))
    FigureFilenameRoot = [];
end

tmask = importdata(tmaskfile);

raw_cii = ft_read_cifti_mod([dtseries]);
if strcmp(raw_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
    cii = raw_cii.data;
else
    cii = raw_cii.data';
end

    %make grey plots
    %fdfilename=[ subdir '/' sub '/movement/' sub '.dvals'];

    fignewton=figure;
    set(gcf,'Color',[1 1 1])
    time = 1:length(cii(1,:));

    ax1 = subplot(5,1,1)
    
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
    
    title(sub,'interpreter','none')
    ax1 = subplot(5,1,2)
    set(gca,'YTick',[]);
    xlabel('Frame');
    title(sprintf('Temporal Masking'));
    imagesc(tmask,[0 1]);
    xlim([1 length(time)]);
    ax2 = subplot(5,1,3)
    %imagesc(raw_cii.data,[-(3*std(raw_cii.data(:))+0.001) (3*std(raw_cii.data(:))+0.001)]);
    scale = mean(std(cii))
    min_val = min(min(cii./scale));
    max_val = max(max(cii./scale));
    imagesc(cii/scale,[min_val max_val]);
    xlim([1 length(time)]);
    colormap('gray');
    title('Atlas Aligned BOLD')
    xlabel('Frame');
    ax3 = subplot(5,1,4)
    
    if(exist([resid_dtseries]))
        resid_cii = ft_read_cifti_mod([resid_dtseries]);
        resid_cii = resid_cii.data';
        % if strcmp(resid_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
        %     resid_cii = resid_cii.data;
        % else
        %     resid_cii = resid_cii.data';
        % end
    else
        resid_cii = zeros(size(raw_cii.data));
    end


    %imagesc(resid_cii,[-(3*std(resid_cii(:,1))+0.001) (3*std(resid_cii(:,1))+0.001)]);
    scale = mean(std(resid_cii))
    
    imagesc(resid_cii/scale,[-3 3]);
    xlim([1 length(time)]);
    xlabel('Frame');
    colormap('gray');
    title(['Detrend + Nuissance Regression (Movement, WB, WM, CSF, Vent)'])
    linkaxes([ax1,ax2],'x')
    
    %after bpss
    if 1
        ax4 = subplot(5,1,5)
        xlabel('Frame');
        
        if(exist([resid_bpss_dtseries]))
            resid_bpss_cii = ft_read_cifti_mod([resid_bpss_dtseries]);
            if strcmp(resid_bpss_cii.dimord,'pos_time') %JSS - take pos x time or time x pos
                resid_bpss_cii = resid_bpss_cii.data;
            else
                resid_bpss_cii = resid_bpss_cii.data';
            end
        else
            resid_bpss_cii = zeros(size(raw_cii.data));
        end
        
 %       imagesc(raw_cii.data,[min(resid_bpss_cii.data(:)) max(resid_bpss_cii.data(:))])
        %imagesc(resid_bpss_cii,[-(3*std(resid_bpss_cii(:))+0.001) (3*std(resid_bpss_cii(:))+0.001)])
        scale = mean(std(resid_bpss_cii))
        imagesc(resid_bpss_cii/scale,[-3 3])
        %imagesc(resid_bpss_cii,[min(min(resid_bpss_cii)) max(max(resid_bpss_cii))])
        %imagesc(resid_bpss_cii.data,[min(resid_bpss_cii.data(:)) max(resid_bpss_cii.data(:))]);
        colormap('gray');
        title(['Detrend + Nuissance Regression + Temporal Filtering (Band Pass)'])
        xlim([1 length(time)]);
        linkaxes([ax1,ax2,ax3],'x')

        disp('saving image');
        saveas(fignewton,[FigureFilenameRoot 'fc_surfproc_QCfig.png'],'png')

        % Look at power spectrum after filtering
        vox = size(cii,1);
        %tp = size(cii,2);
        Verts = randi(length(resid_bpss_cii(:,1)),1,500);
        
        for i = Verts
            [P,F]=pwelch(resid_bpss_cii(i,:),32,[],64,1/TR);
            P_runs(i,:)=P;
        end
        meanP=nanmean(P_runs);
        steP=std(P_runs)/sqrt(size(P_runs,1));
        figspect=figure
        boundedline(F,meanP,steP,'cmap',[0,0,0]); hold on
        xlim([0.001 0.5*(1/TR)]);   %set max frequency to 1/2 sampling frequency (TR)
        xlabel('Frequency');ylabel('Power')
        disp('saving image');
        saveas(figspect,[FigureFilenameRoot 'fc_surfproc_spectrum.png'],'png')
    
        %display the power spectra pre bandpass
         vox = size(cii,1);
         i = randi(length(resid_bpss_cii(:,1)),1,500);
        %tp = size(cii,2);
        for i = Verts
            [P,F]=pwelch(resid_cii(i,:),50,[],256,1/TR);
            P_runs(i,:)=P;
        end
        meanP=nanmean(P_runs);
        steP=std(P_runs)/sqrt(size(P_runs,1));
        figspect_prebpss=figure
        boundedline(F,meanP,steP,'cmap',[0,0,0]); hold on
        xlim([0.001 0.5*(1/TR)]);
        xlabel('Frequency');ylabel('Power')
        disp('saving image');
        saveas(figspect_prebpss,[FigureFilenameRoot 'fc_surfproc_spectrum_prebpss.png'],'png')
        save('grayplot_and_power.mat');
    end