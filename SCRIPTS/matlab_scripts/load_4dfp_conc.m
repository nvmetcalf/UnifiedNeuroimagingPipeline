function [ img_4dfp_stack NumberOfRuns RunLengths] = load_4dfp_conc( ConcFile, OutputMethod, FramesPerScanToLoad )
%load_4dfp_conc reads a 4dfp conc file (avi or fidl format) and returns
%that 4dfp images declared with the conc file as either a 4dfp img struct
%or 4dfp img matrix (voxels = rows, frames = columns). If OutputMethod is 1 
%then data is output as a struct. If set to 2, then the runs will be output
%as a 4dfp matrix.

    img_4dfp_stack = [];

    if(~exist(ConcFile))
        disp([ConcFile ' does not exist!']);
        return;
    end

    if(OutputMethod > 2 || OutputMethod < 1)
        disp('Invalid output method!')
        return;
    end
    
    if(~exist('FramesPerScanToLoad'))
        FramesPerScan = 0;
        FramesPerScanToLoad = 0;
    else
        FramesPerScan = FramesPerScanToLoad;
    end
        
    switch(OutputMethod)
        case 1
            disp('Creating 4dfp struct...');
            img_4dfp_stack = struct('Run',[],'ifh_info',[]);
        case 2
            disp('Creating 4dfp matrix...'); % already been created
            img_4dfp_stack = struct('voxel_data',[],'ifh_info',[]);
    end
       
    % Import the file
    newData1 = importdata(ConcFile);
    ConcData = newData1(2:length(newData1));
    
    %determine if it is an Avi conc or fIDL conc
    if(isempty(find(ConcData{1} == ':')))
        disp('fIDL conc format!');
    else
        disp('Avi conc format!');
        %strip off the file: so that we are left with just a path
        for i = 1:length(ConcData)
            Path = ConcData{i};
            ColonIndex = find(Path == ':');
            Path(1:ColonIndex) = [];
            ConcData{i} = Path;
        end
    end

    NumberOfRuns = length(ConcData);
    RunLengths = [];
    
    %start reading the 4dfp files
    for i = 1:NumberOfRuns
        disp(['Reading ' ConcData{i}]);
        img_file = read_4dfp_img(ConcData{i});
        
        if(FramesPerScanToLoad == 0)
            FramesPerScan = length(img_file.voxel_data(1,:));
        end
        
        RunLengths = horzcat(RunLengths, FramesPerScan);
        
        if(~isempty(img_file))
            switch(OutputMethod)
                case 1
                    img_4dfp_stack(i).Run = img_file.voxel_data;
                    img_4dfp_stack(i).ifh_info = img_file.ifh_info;
                case 2
                    img_4dfp_stack.voxel_data = horzcat(img_4dfp_stack.voxel_data, img_file.voxel_data(:,1:FramesPerScan));
                    img_4dfp_stack.ifh_info = img_file.ifh_info;
            end
        end
    end
end

