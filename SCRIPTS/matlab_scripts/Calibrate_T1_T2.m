%load the template anatomy images and masks
%load the subject anatomy images and masks
%compute mode of all masks for template and the subject

function Calibrate_T1_T2(template_filename, template_eyemask_filename, template_musclemask_filename, subject_filename)
%     template_filename = ['/data/nil-bluearc/corbetta/ATLAS/mni_icbm152_nlin_asym_09c_t88/mni_icbm152_t2_tal_nlin_asym_09c_t88_111.nii.gz'];
% 
%     template_eyemask_filename = ['/data/nil-bluearc/corbetta/ATLAS/mni_icbm152_nlin_asym_09c_t88/templates/eyemask_t88.nii.gz'];
%     template_musclemask_filename = ['/data/nil-bluearc/corbetta/ATLAS/mni_icbm152_nlin_asym_09c_t88/templates/tempmask_t88.nii.gz'];
% 
%     subject_filename = ['FCS_040_AMC_r33_t2wT_t88_111_bc.nii.gz'];


    %==========================================================================

    %load the template and masks
    template_data = load_nifti(template_filename);

    template_eyemask = load_nifti(template_eyemask_filename);
    template_musclemask = load_nifti(template_musclemask_filename);

    %compute mode for template regions
    Yr = mode(reshape(template_data.vol(template_eyemask.vol > 0),1,[]));
    Xr = mode(reshape(template_data.vol(template_musclemask.vol > 0),1,[]));

    clear template_data;

    %load the subject and masks
    subject_data = load_nifti(subject_filename);

    %compute mode for template regions
    Ys = mode(reshape(subject_data.vol(template_eyemask.vol > 0),1,[]));
    Xs = mode(reshape(subject_data.vol(template_musclemask.vol > 0),1,[]));

    %linearly scale the input subject image

    % Xr = mode of template muscle 
    % Xs = mode of template eyes
    % Yr = mode of subject muscle
    % Ys = mode of subject eyes

    %Ic = ((Xr-Yr)/(Xs-Ys)) * I + ((Xs*Yr-Xr*Ys)/(Xs-Ys))
    I = subject_data.vol;
    Ic = ((Xr-Yr)/(Xs-Ys)) * I + ((Xs*Yr-Xr*Ys)/(Xs-Ys));

    %subject_data.vol = Ic;

    save_nifti(subject_data, [strip_extension(strip_extension(subject_filename)) '_calibrated.nii.gz']);

end