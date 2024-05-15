function [ figure1 ] = make_stacked_histogram( FigureTitle, CollumnVector1, Name1, CollumnVector2, Name2, XAxisLabel, YAxisLabel, Normalize, BinSize, Print, MinValue, MaxValue)
%function [ Success ] = make_stacked_histogram( FigureTitle, CollumnVector1, Name1, CollumnVector2, Name2, XAxisLabel, YAxisLabel, Normalize, BinSize, Print, MinValue, MaxValue)
%Created a superimposed histogram based on the histograms of the Collumn
%Vectors supplied. If the Collumne Vectors are actuall matrices, then the
%columns will be concatonated to form a collumn vector for each input.

    SourceMatrix1 = CollumnVector1;
    SourceMatrix1_Name = Name1;
    SourceMatrix2 = CollumnVector2;
    SourceMatrix2_Name = Name2;
    
    BinSize = abs(BinSize);
    
    if(~exist('MaxValue'))
        %find the biggest max and lowest min
        if min(SourceMatrix1(:,1)) < min(SourceMatrix2(:,1)) 
            MinValue = min(SourceMatrix1(:,1));
        else
            MinValue = min(SourceMatrix2(:,1));
        end
    end
    
    if(~exist('MinValue'))
        if max(SourceMatrix1(:,1)) > max(SourceMatrix2(:,1)) 
            MaxValue = ceil(max(SourceMatrix1(:,1)));
        else
            MaxValue = ceil(max(SourceMatrix2(:,1)));
        end
    end
    
    disp(sprintf('Min: %f \tMax: %f',MinValue,MaxValue));
    
    %make our list of bins
    xvector1 = MinValue-BinSize:BinSize:MaxValue+BinSize;
    %xvector1 = MinValue-BinSize:BinSize:MaxValue+BinSize;
    %this gets the number of values in each bin
    Vector1_Bins = histc(SourceMatrix1,xvector1);
    Vector2_Bins = histc(SourceMatrix2,xvector1);

    %percent normalize
    if Normalize
        Vector1_Bins = PercentNormalize(Vector1_Bins);
        Vector2_Bins = PercentNormalize(Vector2_Bins);
        YLabel = 'Percent per Bin';
    end

    if(isempty(Vector1_Bins))
        Vector1_Bins = zeros(1,length(xvector1));
    end
    
    ymatrix1(:,1) = Vector1_Bins';
    
    if(isempty(Vector2_Bins))
        Vector2_Bins = zeros(1,length(xvector1));
    end
    ymatrix1(:,2) = Vector2_Bins';

    %make the labels for the XAxis
    clear XLabels

    disp('Making Labels');
    XLabels = [];
    %i = round(MinValue)-1:1:round(MaxValue)+1;
    %i = MinValue-BinSize:BinSize:MaxValue+BinSize;
    
    PadLength = 0;
    for j = 1:length(xvector1)
        temp = num2str(xvector1(j));
        if(length(temp) > PadLength)
            PadLength = length(temp);        
        end
    end
    
    %need to figure out what the longest value is
%     if(length(num2str(i(1))) > length(num2str(i(length(i)))))
%         PadLength = length(num2str(i(1)));
%     else
%         PadLength = length(num2str(i(length(i))));
%     end
    
    for j = 1:length(xvector1)
        temp = num2str(xvector1(j));
        %pad the string
        while(length(temp) < PadLength)
            temp = [' ' temp];
        end
        disp(sprintf('Bin: %s \t NameLen: %i PadLen: %i', temp, length(temp), PadLength));
        XLabels = vertcat(XLabels, temp);
    end

    %set up data for "superimposed" bar graphs
    for i=1:length(ymatrix1(:,1))
        if ymatrix1(i,2) < ymatrix1(i,1)
            ymatrix1(i,3) = ymatrix1(i,2);
            ymatrix1(i,4) = ymatrix1(i,1) - ymatrix1(i,2);
            ymatrix1(i,5) = 0;
        else
            ymatrix1(i,3) = ymatrix1(i,1);
            ymatrix1(i,4) = 0;
            ymatrix1(i,5) = ymatrix1(i,2) - ymatrix1(i,1);
        end
    end

    %make the graph
    figure1 = figure('PaperSize',[11 8.5],'PaperOrientation','landscape',...
        'Name',FigureTitle);
    colormap('copper');

    % Create axes
    %axes1 = axes('Parent',figure1,'YGrid','on',...
    %    'XTickLabel',{XLabels},...
    %    'XTick',[round(MinValue)-1:1:round(MaxValue)+1],...
    %    'XMinorTick','on',...
    %    'XGrid','on',...
    %    'Position',[0.126981891348089 0.0810144927536231 0.775000000000002 0.846521739130435]);
    axes1 = axes('Parent',figure1,'YGrid','on',...
        'XTickLabel',{XLabels},...
        'XTick',[MinValue-BinSize:BinSize:MaxValue+BinSize],...
        'XMinorTick','on',...
        'XGrid','on',...
        'Position',[0.126981891348089 0.0810144927536231 0.775000000000002 0.846521739130435]);
    
    % Uncomment the following line to preserve the X-limits of the axes
    %xlim(axes1,[round(MinValue)-1 round(MaxValue)+1]);
    xlim(axes1,[xvector1(1) xvector1(length(xvector1))]);
    
    box(axes1,'on');
    hold(axes1,'all');

    % Create multiple lines using matrix input to bar
    bar1 = bar(xvector1,ymatrix1(:,3:5),'EdgeColor','none','BarLayout','stacked',...
        'Parent',axes1);
    set(bar1(1),'DisplayName','Overlap');
    set(bar1(2),'FaceColor',[0 0.498039215803146 0],'DisplayName',SourceMatrix1_Name);
    set(bar1(3),'FaceColor',[0.600000023841858 0.200000002980232 0],'DisplayName',SourceMatrix2_Name);

    % Create xlabel
    xlabel(XAxisLabel);

    % Create ylabel
    ylabel(YAxisLabel);

    % Create title
    title({FigureTitle},'FontSize',14);

    % Create legend
    legend(axes1,'show');

    if Print
        %set the stylesheet we want and print
        pt = printtemplate;
        pt.StyleSheet = 'histogram';
        pt.VersionNumber = 2;
        pt.DriverColor = 1;
        pt.PrintUI = 0;
        set(figure1,'PaperPositionMode','manual','PaperPosition',[-1.00 0.38 12.85 7.75],'PaperSize',[11.00 8.50],'PaperType','USLetter')
        setprinttemplate(figure1,pt)
        handles.output = figure1;
        guidata(figure1, handles)
        print(['-P' Print],figure1)
    end
end

