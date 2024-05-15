function moh_run_ALI(job)
% routine: Automatic Lesion Identification (ALI)
% routine with several steps
% can alos be used to generate lesion overlap maps (LOM)
% -------------------------------------------------
% STEP 1:
%   segment in 4 classes all structural T1 images
%   all controls and patients
%   in two runs:
%   1- a rough estimate of the lesion localisation
%   2- use the result form run 1 as a prior (iterative segmentation)
% -------------------------------------------------
% STEP 2:
%   Outlier detection within GM and WM classes
%   Using Fuzzy clustering with fixed prototype (FCP)
%   in 2 parts:
%   1- outliers (positive and negative) in GM
%   2- outliers (positive and negative) in WM
% -------------------------------------------------
% STEP 4:
%   Grouping of outliers within GM and WM (negative values)
%   Generate three different images:
%   1- fuzzy definition of the lesion (continuous abnormality)
%   2- binary (1/0) image of the lesion (at a given threshold)
%   3- contours of the lesion
% ---------------------------------------------------
% Generate Lesion overlap maps LOM across patients
% and then explore LOM image + list of patients with lesions
%
% ---------------------------------------------------
% Mohamed Seghier, 30.05.2009 // updated 07.04.2014
% ======================================


clc ;
vs = '3.0' ;

disp(spm('time')) ;

% spm('ver', 'spm_spm.m') ;
% if ~ismember({spm('ver')}, {'SPM5','SPM8b', 'SPM8'}), ...
% error('The script needs SPM5 (or greater) to run correctly....!!!'); end
% if spm_matlab_version_chk('7') < 0, ...
%         error('The script needs MATLAB 7 or greater....!!!'); end
pushbutton_color = [0.3 0.3 0.3] ;

spm('Defaults','fMRI') ;
global defaults


disp([sprintf('\n\n'),...
    'Welcome to the Automatic Lesion Identification (ALI) toolbox',...
    sprintf('\n\n'),...
    ' - - - - - This is ALI, version ' vs ' - - - - - ',...
    sprintf('\n\n')]);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% -------------------------------------------------------------------------
% STEP 1: iterative unified segmentation-normalisation
% -------------------------------------------------------------------------


if isfield(job, 'step1prior')
    
    % segment in 4 classes all structural T1 images
    % (controls and patients)
    %=============================================================
    % in two steps:
    % 1- a rough estimate of the lesion localisation
    % 2- use the result form step 1 as a prior (iterative process)
    
    
    p_anat = char(job.step1data) ;
    p0_C4prior = char(job.step1prior) ;
    v0 = spm_vol(p0_C4prior) ;
    
    % default values
    % --------------
    n_iter = job.step1niti ; % number of iterations in the new segment
    clean_prob = job.step1thr_prob ; % lower prob value in the extra class
    clean_size = job.step1thr_size ; % size threshold in (cm3) the extra class
    do_coregister = job.step1coregister ; % if coregistration is necessary
    fwhm = job.step1fwhm ; % for spatial smoothing
    
    % check whether mask is specified
    p_mask = char(job.step1mask);
    
    im2write = zeros(n_iter,1) ;
    im2write(end) = 1 ;
    
    for n=1:size(p_anat, 1)
        
        voxsize = abs(v0.mat(1,1)) ; % voxel sizes [mm] isotropic
        % voxsize = job.step1vox ;
        if n_iter == 1
            voxsize = job.step1vox ;
        end
        
        
        % 1st guess
        % ======
        
        [pth,nam,ext,toto] = spm_fileparts(deblank(p_anat(n,:))) ;
        
        % to improve the segmentation (unified framework)
        % coregister the T1 image to the T1 template
        if do_coregister
            moh_coregister_job(deblank(p_anat(n,:))) ;
        end
        
        V_anat = spm_vol(deblank(p_anat(n,:))) ;
        
        % first segmentation in 4 classes (EXTRA1)
        disp(['/////////////////////// SUBJECT ' num2str(n), ...
            ' /// iteration 1 \\\\\\\\\\\\\\\\\\\\']) ;
        moh_unified_segmentation(V_anat.fname, p0_C4prior,...
            voxsize, p_mask, im2write(1)) ;
        
        
        for iti=1:(n_iter-1)
            
            % prepare the rough estimate of the lesion
            % prepare the prior (clean up)
            % pC4 = fullfile(pth , ['wc4' nam ext]) ;
            pC4 = spm_select('FPList',pth,['^wc4' nam]) ;
            vC4 = spm_vol(pC4) ;
            % covert size from cm3 into nb of voxels
            % clean_size = floor(1000 * clean_size / (abs(vC4.mat(1,1))^3)) ;
            
            im_prior = moh_cleanup_prior(vC4, clean_prob, clean_size, iti);
            
            
            % itirative segmentation
            % ======================
            disp(['////////////////////// SUBJECT ' num2str(n),...
                ' /// iteration ',num2str(iti+1),' \\\\\\\\\\\\\\\\\\\\']);
            
            if iti == (n_iter-1)
                voxsize = job.step1vox ;
            end
            
            moh_unified_segmentation(V_anat.fname, im_prior,...
                voxsize, p_mask, im2write(1+iti)) ;
            
        end
        
        
        % after segmentation, write a normalised anatomical volume
        % =========================================================
        moh_writenormalise_job(V_anat.fname, voxsize);
        disp('################# write a normalised structural volume ..OK')
        
        % smooth the segmented GM adn WM tissue images
        % ============================================
        moh_smooth_job(spm_select('FPList',pth,['^wc[12]' nam]), fwhm);
        disp('################# smooth GM and WM tissue images ..OK')
        
        
    end
end



% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%
% % -------------------------------------------------------------------------
% % STEP 2: spatial smoothing of segmented GM/WM classes
% % -------------------------------------------------------------------------
%
%
% if isfield(job, 'step2fwhm')
%
%     P = job.step2data ;
%
%     fwhm = job.step2fwhm ;
%
%     % Spatial smoothing of GM and WM images
%     % (controls and patients)
%     %=============================================================
%     disp(sprintf('##### smoothing of the segmented tissue images...... '))
%     moh_smooth_job(P,fwhm) ;
% end
%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% -------------------------------------------------------------------------
% STEP 2: outliers detection (detection of abnormality in GM and WM)
% -------------------------------------------------------------------------


if isfield(job, 'step3mask')        % Outlier detection within GM and WM
    % (Fuzzy clustering)
    %=============================================================
    % folder_results = char(job.step3directory) ;
    
    pm = char(job.step3mask) ;
    mask_threshold = job.step3mask_thr  ; % or use threshold 2 for F masks
    
    N_tissue = length(job.step3tissue) ;
    
    
    % parameters for binarisation
    thr_size = job.step3binary_size ; % lesion more than 0.8cm3 in volume
    thr_U = job.step3binary_thr ; % threshold on U values
    
    % load of the mask (mask.img) (meaningful voxels)
    vm = spm_vol(pm) ;
    mask = spm_read_vols(vm) > mask_threshold ;
    Vol = find(mask) ;
    %[voxx voxy voxz] = ind2sub(size(mask), Vol) ;
    
    % c = size(pCG,1) + 1 ; % number of classes = N controls + 1 patient
    
    % convert size from cm3 to nb voxels
    thr_size = floor(1000 * thr_size / (abs(vm.mat(1,1))^3)) ;
    
    % Structure FCP creation
    FCP.version.SPM = spm('ver') ;
    FCP.version.toolbox = vs ;
    for ts=1:N_tissue
        FCP.files.patients{ts} = char(job.step3tissue(ts).step3patients) ;
        FCP.files.controls{ts} = char(job.step3tissue(ts).step3controls) ;
        FCP.lambda(ts) = job.step3tissue(ts).step3Lambda ;
        FCP.alpha(ts) = job.step3tissue(ts).step3Alpha ;
    end
    FCP.mask.file = pm ;
    FCP.mask.threshold = mask_threshold ;
    
    FCP.size.nvoxels = nnz(mask) ;
    FCP.size.nclasses = size(job.step3tissue(1).step3controls,1) + 1 ;
    
    write_fcp_pos = 0 ; % No need to write out FCP_positive images
    
    NB_chunks = 6 ; %to split the data into multiple chunks
    % use multiple chunks of data (total = "NB_chunks-1")
    zz = uint32(linspace(1,length(Vol),NB_chunks));
    
    Loop_steps = (NB_chunks-1)*N_tissue*size(char(job.step3tissue(1).step3patients) ,1) ;
    spm_progress_bar('Init',Loop_steps,...
        'Outliers detection [all patients and classes]','Chunks');
    Nstep = 0 ;
    
    for ts=1:N_tissue
        
        % default parameters
        Lambda = job.step3tissue(ts).step3Lambda ; % equivalent to "m" in FCM (m=1-2/lambda)
        Alpha = job.step3tissue(ts).step3Alpha ; % factor of sensitivity (tunning factor)
        
        
        % Outliers detection for GM images
        % ============================================================
        disp(['############## Outlier detection .............. Tissue class ',...
            num2str(ts)]) ;
        
        % prepare control data
        pC = char(job.step3tissue(ts).step3controls) ;
        vC = spm_vol(pC) ;
        %         if not(isequal(vm.dim, vC(:).dim))
        %             error('Ooops: Data must have the same size....!!!!!!!') ;
        %         end
        
        pP = char(job.step3tissue(ts).step3patients) ;
        vP = spm_vol(pP) ;
        
        if not(isequal(vm.dim, vC(:).dim, vP(:).dim))
            error('Ooops: Data must have the same size....!!!!!!!') ;
        end
        
        % create volumes of interest (outlier images)
        for n=1:size(pP,1)
            [pth nam ext toto] = spm_fileparts(vP(n).fname) ;
            % prepare output for positive (high) effects
            if write_fcp_pos
                vo = struct('fname',   fullfile(pth, ['Outliers_high_',nam, '.nii']),...
                    'dim',     vP(n).dim(1:3),...
                    'dt',      [16 spm_platform('bigend')],...
                    'mat',     vP(n).mat,...
                    'descrip', 'FCP: outliers (above mean) within the tissue class');
                vo = spm_create_vol(vo) ;
                FCP.U(ts).positive{n} = vo.fname ;
                spm_write_vol(vo, zeros(vo.dim)) ;
                
            end
            
            % prepare output for negative (low) effects
            vo = struct('fname',   fullfile(pth, ['Outliers_low_',nam, '.nii']),...
                'dim',     vP(n).dim(1:3),...
                'dt',      [16 spm_platform('bigend')],...
                'mat',     vP(n).mat,...
                'descrip', 'FCP: outliers (below mean) within the tissue class');
            vo = spm_create_vol(vo) ;
            FCP.U(ts).negative{n} = vo.fname ;
            spm_write_vol(vo, zeros(vo.dim)) ;
            
        end
        
        GGn = zeros(0) ;
        GGp = zeros(0) ;
        for ch=1:NB_chunks-1
            
            XC = [] ;
            [voxx voxy voxz] = ind2sub(size(mask), Vol(zz(ch):zz(ch+1))) ;
            XC = spm_get_data(vC,[voxx voxy voxz]')' ;
            
            
            for n=1:size(pP,1)
                
                clear U* Gn
                XP = [] ;
                XP = spm_get_data(vP(n),[voxx voxy voxz]')' ;
                                
                
                % detection of outlier voxels
                [Un, Gn, Up, Gp] = moh_FCP_outliers(XP, XC,...
                    Alpha, Lambda, write_fcp_pos);
                
                
                % prepare output for negative (low) effects
                vo = spm_vol(FCP.U(ts).negative{n}) ;
                spm_data_write(vo,Un,Vol(zz(ch):zz(ch+1)));
                GGn = [GGn; Gn*length(voxx)];
                
                % prepare output for positive (high) effects
                if write_fcp_pos
                    vo = spm_vol(FCP.U(ts).positive{n}) ;
                    spm_data_write(vo,Up,Vol(zz(ch):zz(ch+1)));
                    GGp = [GGp; Gp*length(voxx)];
                end
                
                Nstep = Nstep + 1 ;
                spm_progress_bar('Set',Nstep);
            end
        end
        
        % save global measure G [optional]
        for n=1:size(pP,1)
            if write_fcp_pos
                FCP.G(ts).positive(n,:) = sum(GGp(n:size(pP,1):size(GGp,1),:),1) / length(Vol) ;
            end
            FCP.G(ts).negative(n,:) = -sum(GGn(n:size(pP,1):size(GGn,1),:),1) / length(Vol) ;
        end
    end
    pause(1) ;
    spm_progress_bar('Clear');

    
    %         XC = [] ;
    %         XC = spm_get_data(vC,[voxx voxy voxz]')' ;
    
    %         pP = char(job.step3tissue(ts).step3patients) ;
    %         for n=1:size(pP,1)
    %
    %             clear U* G*
    %
    %             vP = spm_vol(deblank(pP(n,:))) ;
    %
    %             [pth nam ext toto] = spm_fileparts(vP.fname) ;
    %             disp(['=========== patient number ',...
    %                 num2str(n), ' , name: ', nam]) ;
    %
    %             if not(isequal(vm.dim, vP.dim))
    %                 error('Ooops: patient data and mask must have the same size....!!!!!!!') ;
    %             end
    %
    %             % detection of outlier voxels
    %             [Un, Gn, Up, Gp] = moh_FCP_outliers(vP, XC, Vol,...
    %                 Alpha, Lambda, write_fcp_pos);
    %
    %             % prepare outlput for positive (high) effects
    %             if write_fcp_pos
    %                 vo = struct('fname',   fullfile(pth, ['Outliers_high_',nam, '.nii']),...
    %                     'dim',     vP.dim(1:3),...
    %                     'dt',      [16 spm_platform('bigend')],...
    %                     'mat',     vP.mat,...
    %                     'descrip', 'FCP: outliers (above mean) within the tissue class');
    %                 spm_write_vol(vo,Up) ;
    %                 FCP.U(ts).positive{n} = vo.fname ;
    %                 FCP.G(ts).positive(n,:) = Gp ;
    %             end
    %
    %             % prepare outlput for negative (low) effects
    %             vo = struct('fname',   fullfile(pth, ['Outliers_low_',nam, '.nii']),...
    %                 'dim',     vP.dim(1:3),...
    %                 'dt',      [16 spm_platform('bigend')],...
    %                 'mat',     vP.mat,...
    %                 'descrip', 'FCP: outliers (below mean) within the tissue class');
    %             spm_write_vol(vo,Un) ;
    %             FCP.U(ts).negative{n} = vo.fname ;
    %             FCP.G(ts).negative(n,:) = -Gn ;
    %
    %         end
    %
    %     end
    
    
    
    save(fullfile(pth, ['FCP_' lower(date) '.mat']), 'FCP') ;
    
    
    
    % lesion definition by grouping outliers (fuzzy, binary, contour)
    % ---------------------------------------------------------------
    
    % structure for volumetric information (e.g. lesions + size + location)
    Volume.version.SPM = spm('ver') ;
    Volume.version.toolbox = vs ;
    Volume.subjects = char(job.step3tissue(1).step3patients) ;
    Volume.threshold_U = thr_U ;
    Volume.threshold_extent = thr_size ;
    
    
    % read all images
    pP = char(job.step3tissue(1).step3patients) ;
    for i=1:size(pP,1)
        
        disp(['######## 3D-lesion image (fuzzy and binary) for patient number:  ', num2str(i)]) ;
        
        Outliers_images = FCP.U(1).negative{i} ;
        if N_tissue >1
            for ts=1+1:N_tissue
                Outliers_images = char(Outliers_images,FCP.U(ts).negative{i}) ;
            end
        end
        
        % Group lesion, binary + contour, calculate size and location
        [FuzzyLesion,BinaryLesion,ContourLesion,sizeFuzzy,SizeBinary] = ...
            moh_group_lesion(Outliers_images, thr_U, thr_size) ;
        
        v1=spm_vol(FCP.U(1).negative{i});
        [pth nam ext toto] =  spm_fileparts(v1.fname) ;
        ind = find(ismember(nam, '_')) ;
        
        vo = struct('fname',   fullfile(pth,['Lesion_binary_' nam(ind(2)+1:end), '.nii']),...
            'dim',     v1.dim(1:3),...
            'dt',      [2 spm_platform('bigend')],...
            'mat',     v1.mat,...
            'descrip', ['Binary: thresholded 3D-lesion image at U = ' num2str(thr_U) ' and k = ' num2str(thr_size)]);
        spm_write_vol(vo, BinaryLesion) ;
        
        vo = struct('fname',   fullfile(pth,['Lesion_fuzzy_' nam(ind(2)+1:end), '.nii']),...
            'dim',     v1.dim(1:3),...
            'dt',      [16 spm_platform('bigend')],...
            'mat',     v1.mat,...
            'descrip', 'Fuzzy set of abnormal voxels (3D-lesion image)');
        spm_write_vol(vo, FuzzyLesion) ;
        
        vo = struct('fname',   fullfile(pth,['Lesion_contour_' nam(ind(2)+1:end), '.nii']),...
            'dim',     v1.dim(1:3),...
            'dt',      [2 spm_platform('bigend')],...
            'mat',     v1.mat,...
            'descrip', ['Lesion contours defined at U = ' num2str(thr_U) ' and k = ' num2str(thr_size)]);
        spm_write_vol(vo, ContourLesion) ;
        
        Volume.Fcardinality(i) = sizeFuzzy ;
        Volume.binary(i) = SizeBinary ;
        
        
    end
    
    
    save(fullfile(pth,['Volume_' lower(date) '.mat']),'Volume');
    
    
    
end



% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% % -------------------------------------------------------------------------
% % STEP 4: lesion definition by grouping outliers (fuzzy, binary, contour)
% % -------------------------------------------------------------------------
%
%
% if isfield(job, 'step4fcpGM')     % Grouping of outliers within GM and WM
%     % Contour detection
%     %=============================================================
%     folder_results = char(job.step4directory) ;
%
%     % select the GM U images
%     pG = char(job.step4fcpGM) ;
%
%     % select the WM U images
%     pW = char(job.step4fcpWM) ;
%
%     % default parameters
%     % ------------------
%     thr_size = job.step4binary_size ; % lesion more than 1cm3 in volume
%     thr_U = job.step4binary_thr ; % threshold on U values
%
%
%     % Critical: check that the selected files have the same order
%     % ===========================================================
%     for i=1:size(pG,1)
%         [pth namG ext toto] =  spm_fileparts(deblank(pG(i,:))) ;
%         [pth namW ext toto] =  spm_fileparts(deblank(pW(i,:))) ;
%         and_names = ~(namG == namW) ;
%         if nnz(and_names)>1
%             disp(['==== proble starting at subject number ' num2str(i)]) ;
%             error('### Please check the names/order of your files....!!!');
%         end
%     end
%
%     % structure for volumetric information (e.g. lesions + size + location)
%     Volume.version.SPM = spm('ver') ;
%     Volume.version.toolbox = vs ;
%     Volume.subjects = pG ;
%     Volume.threshold_U = thr_U ;
%     Volume.threshold_extent = thr_size ;
%
%
%     vG = spm_vol(pG) ;
%     vW = spm_vol(pW) ;
%
%
%
%     % read all images
%     for i=1:size(pG,1)
%
%         disp(['######## Lesion mask for patient number:  ', num2str(i)]) ;
%
%         % Group lesion, binary + contour, calculate size and location
%         [FuzzyLesion,BinaryLesion,ContourLesion,sizeFuzzy,SizeBinary] = ...
%             moh_group_lesion(vG(i), vW(i), thr_U, thr_size) ;
%
%         vo = vG(i) ; % V structure for the output file
%
%         [pth nam ext toto] =  spm_fileparts(deblank(pG(i,:))) ;
%         ind = find(ismember(nam, '_')) ;
%         vo.fname = fullfile(folder_results,...
%             ['Lesion_binary_' nam(ind(2)+1:end), ext]) ;
%         spm_write_vol(vo, BinaryLesion) ;
%
%         vo.fname = fullfile(folder_results,...
%             ['Lesion_fuzzy_' nam(ind(2)+1:end), ext]) ;
%         spm_write_vol(vo, FuzzyLesion) ;
%
%         vo.fname = fullfile(folder_results,...
%             ['Lesion_contour_' nam(ind(2)+1:end), ext]) ;
%         spm_write_vol(vo, ContourLesion) ;
%
%         Volume.Fcardinality(i) = sizeFuzzy ;
%         Volume.binary(i) = SizeBinary ;
%
%
%     end
%
%
%     save(fullfile(folder_results,['Volume_' lower(date) '.mat']),'Volume');
%
% end
%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% -------------------------------------------------------------------------
% generate lesion overlap maps (LOM): useful for group analysis
% -------------------------------------------------------------------------


if isfield(job, 'lom')     % Generate Lesion overlap across patients
    %=============================================================
    
    clear LOM ;
    
    if isfield(job.lom, 'step5')
        job = job.lom.step5 ;
        
        % create a LOM
        % --------------
        folder_results = char(job.step5directory) ;
        min_display = job.step5thr_nb ; % default =1; all lesioned voxs are shown
        
        % load the binary lesion images
        pG = char(job.step5LOM) ;
        
        vG = spm_vol(pG) ;
        [pth,nam,ext,toto] = spm_fileparts(vG(1).fname) ;
        
        if not(isequal(vG(:).dim))
            error('Ooops: Binary lesion images must have the same size....!!!!!!!') ;
        end
        
        %
        %     % anatomical (canonical) image
        %     pp = fullfile(spm('Dir'),...
        %         'canonical', 'single_subj_T1.nii') ;
        %     vv = spm_vol_nifti(pp);
        %     [anat, XYZ] = spm_read_vols(vv) ;
        
        im_overlap = uint16(zeros(vG(1).dim)) ; % init of the overlap image
        vo = vG(1) ; % Vol structure for the output file
        vo.pinfo(1) = 1 ;
        vo.dt = [spm_type('uint16') spm_platform('bigend')] ;
        
        % index of patients of interest
        index_lesion = repmat(uint8(zeros(vG(1).dim)), [1 1 1 size(pG,1)]) ;
        
        % read all images
        for i=1:size(pG,1)
            
            % LOM assessment
            lesion_bin = uint16(spm_read_vols(vG(i))) ;
            im_overlap = im_overlap + lesion_bin ;
            [x y z] = ind2sub(vG(1).dim, find(lesion_bin > 0)) ;
            ind_xyz = sub2ind(size(index_lesion), x,y,z,i*ones(length(x),1)) ;
            index_lesion(ind_xyz) = 1 ;
            
        end
        
        % write LOM image
        vo.fname = fullfile(folder_results,...
            ['LOM_nb', num2str(size(pG,1), '%.3d'), 'patients' ext]) ;
        spm_write_vol(vo, im_overlap) ;
        
        
        % display LOM maps
        % ==================
        %     % with montage multi-slice display
        %     figure(2) ;
        %     colormapp = colormap([gray(256) ; jet(size(pG,1))]) ;
        %     mask =  im_overlap >= threshold_mask ;
        %     map = 256 * anat / max(anat(:));
        %     map(mask) = double(im_overlap(mask)) + 256  ;
        %     mont(:,:,1,:) = imrotate(map(:,:,4:end-9),90) ;
        %     mont = flipdim(mont, 2); % flip L/R
        %     montage (mont, colormapp);
        
        
        % wrtite the structure of the group analysis
        ss = reshape(index_lesion, [prod(vG(1).dim) size(pG,1)]);
        voxels_of_interest = find(sum(ss,2) > 0);
        occurrence = squeeze(ss(voxels_of_interest, :)) ;
        LOM.image = ['LOM_nb', num2str(size(pG,1), '%.3d'), 'patients' ext] ;
        LOM.subjects = pG ;
        LOM.index.voxels = voxels_of_interest ;
        LOM.index.occurence = occurrence ;
        LOM.version.SPM = spm('ver') ;
        LOM.version.toolbox = vs ;
        
        pL = fullfile(folder_results,...
            ['LOM_nb',num2str(size(pG,1), '%.3d'),'patients_info.mat']) ;
        
        save(pL,'LOM');
        
    elseif isfield(job.lom, 'step6')
        % explore the LOM
        % ---------------
        % Explore and examen Lesion overlap maps
        % list patients having lesions at a gievn location
        %====================================================================
        
        % select the LOM structure
        
        job = job.lom.step6 ;
        
        min_display = job.step6thr_nb ; % default: all lesioned voxs are shown
        
        
        % load of the structure and the map
        pL = char(job.step6LOM_file) ;
        LOM = load(pL) ; LOM = LOM.LOM ;
        
    end
    
    assignin('base', 'LOM', LOM);
    [pth nm ext toto]= spm_fileparts(pL) ;
    v = spm_vol(fullfile(pth, LOM.image)) ;
    assignin('base', 'v', v);
    
    
    % within SPM (3-views)
    Fgraph = spm_figure('GetWin','Graphics');
    figure(Fgraph) ;
    
    moh_display_blobs(v, min_display) ;
    
    %     if min_display == 1
    %         moh_display_blobs(v, 1) ;
    %     else
    %         % anatomical (canonical) image
    %         pp = fullfile(spm('Dir'),...
    %             'canonical', 'single_subj_T1.nii') ;
    %         im_overlap = spm_read_vols(v) ;
    %
    %         % Display the image within SPM (3-views)
    %         spm_check_registration(pp) ;
    %         [X,Y,Z] = ind2sub(v.dim, LOM.index.voxels) ;
    %         Zblob = double(im_overlap(LOM.index.voxels)); % blob voxel intens.
    %         Zblob(Zblob < min_display) = NaN ;
    %
    %         spm_orthviews('AddBlobs',1,[X';Y';Z'],Zblob,v.mat) ;
    %
    %     end
    
    
    %     Fgraph = spm_figure('GetWin','Graphics');
    %     figure(Fgraph) ;
    spm_figure('Colormap','gray-jet') ;
    
    fsz=get(Fgraph, 'Position') ;
    
    
    bout2 = uicontrol('BackgroundColor', pushbutton_color, ...
        'Style','pushbutton', ...
        'string', ' List of lesions at the voxel', ...
        'Units', 'Pixels', ...
        'Position', [0.1*fsz(3) 0.05*fsz(4) 300 30], ...
        'FontAngle','italic',...
        'FontWeight','bold',...
        'FontUnits','points',...
        'FontSize', 12, ...
        'ForegroundColor','w',...
        'HorizontalAlignment', 'center',...
        'Visible', 'On', ...
        'Selected','off',...
        'SelectionHighlight','on', ...
        'Callback',...
        'moh_LOM_explore(LOM, v, ''list_only'')');
    
    bout3 = uicontrol('BackgroundColor', pushbutton_color, ...
        'Style','pushbutton', ...
        'string', ' List of lesions within a VOI', ...
        'Units', 'Pixels', ...
        'Position', [0.1*fsz(3) (0.05*fsz(4))-35 300 30], ...
        'FontAngle','italic',...
        'FontWeight','bold',...
        'FontUnits','points',...
        'FontSize', 12, ...
        'ForegroundColor','w',...
        'HorizontalAlignment', 'center',...
        'Visible', 'On', ...
        'Selected','off',...
        'SelectionHighlight','on', ...
        'Callback',...
        'moh_LOM_explore(LOM, v, ''list_only_voi'')');
    
    bout4 = uicontrol('BackgroundColor', pushbutton_color, ...
        'Style','pushbutton', ...
        'string', ' Lesion: size and centre', ...
        'Units', 'Pixels', ...
        'Position', [(0.1*fsz(3))+340 0.05*fsz(4) 250 30], ...
        'FontAngle','italic',...
        'FontWeight','bold',...
        'FontUnits','points',...
        'FontSize', 12, ...
        'ForegroundColor','w',...
        'HorizontalAlignment', 'center',...
        'Visible', 'On', ...
        'Selected','off',...
        'SelectionHighlight','on', ...
        'Callback',...
        'moh_LOM_explore(LOM, v, ''list_size'')');
    
    
end



% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% % -------------------------------------------------------------------------
% % explore the LOM maps: useful for group analysis
% % -------------------------------------------------------------------------
%
%
%
% if isfield(job, 'step6thr_nb')
%
%
%
%     % Explore and examen Lesion overlap maps
%     % list patients having lesions at a gievn location
%     %====================================================================
%
%     % select the LOM structure
%     pL = char(job.step6LOM_file) ;
%
%     min_display = job.step6thr_nb ; % default: all lesioned voxs are shown
%
%
%     % load of the structure and the map
%     LOM = load(pL) ; LOM = LOM.LOM ;
%     assignin('base', 'LOM', LOM);
%     [pth nm ext toto]= spm_fileparts(pL) ;
%     v = spm_vol(fullfile(pth, LOM.image)) ;
%     assignin('base', 'v', v);
%
%     if min_display == 1
%         moh_display_blobs(v, 1) ;
%     else
%         % anatomical (canonical) image
%         pp = fullfile(spm('Dir'),...
%             'canonical', 'single_subj_T1.nii') ;
%         im_overlap = spm_read_vols(v) ;
%
%         % Display the image within SPM (3-views)
%         spm_check_registration(pp) ;
%         [X,Y,Z] = ind2sub(v.dim, LOM.index.voxels) ;
%         Zblob = double(im_overlap(LOM.index.voxels)); % blob voxel intens.
%         Zblob(Zblob < min_display) = NaN ;
%
%         spm_orthviews('AddBlobs',1,[X';Y';Z'],Zblob,v.mat) ;
%
%     end
%
%
%     Fgraph = spm_figure('GetWin','Graphics');
%     figure(Fgraph) ;
%     spm_figure('Colormap','gray-jet') ;
%
%     fsz=get(Fgraph, 'Position') ;
%
%
%     bout2 = uicontrol('BackgroundColor', pushbutton_color, ...
%         'Style','pushbutton', ...
%         'string', ' List of lesions at the voxel', ...
%         'Units', 'Pixels', ...
%         'Position', [0.1*fsz(3) 0.05*fsz(4) 300 30], ...
%         'FontAngle','italic',...
%         'FontWeight','bold',...
%         'FontUnits','points',...
%         'FontSize', 12, ...
%         'ForegroundColor','w',...
%         'HorizontalAlignment', 'center',...
%         'Visible', 'On', ...
%         'Selected','off',...
%         'SelectionHighlight','on', ...
%         'Callback',...
%         'moh_LOM_explore(LOM, v, ''list_only'')');
%
%     bout3 = uicontrol('BackgroundColor', pushbutton_color, ...
%         'Style','pushbutton', ...
%         'string', ' List of lesions within a VOI', ...
%         'Units', 'Pixels', ...
%         'Position', [0.1*fsz(3) (0.05*fsz(4))-35 300 30], ...
%         'FontAngle','italic',...
%         'FontWeight','bold',...
%         'FontUnits','points',...
%         'FontSize', 12, ...
%         'ForegroundColor','w',...
%         'HorizontalAlignment', 'center',...
%         'Visible', 'On', ...
%         'Selected','off',...
%         'SelectionHighlight','on', ...
%         'Callback',...
%         'moh_LOM_explore(LOM, v, ''list_only_voi'')');
%
%     bout4 = uicontrol('BackgroundColor', pushbutton_color, ...
%         'Style','pushbutton', ...
%         'string', ' Lesion: size and centre', ...
%         'Units', 'Pixels', ...
%         'Position', [(0.1*fsz(3))+340 0.05*fsz(4) 250 30], ...
%         'FontAngle','italic',...
%         'FontWeight','bold',...
%         'FontUnits','points',...
%         'FontSize', 12, ...
%         'ForegroundColor','w',...
%         'HorizontalAlignment', 'center',...
%         'Visible', 'On', ...
%         'Selected','off',...
%         'SelectionHighlight','on', ...
%         'Callback',...
%         'moh_LOM_explore(LOM, v, ''list_size'')');
%
% end


return ;
