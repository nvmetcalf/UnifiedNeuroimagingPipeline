function copy_nifti_header(copy_from_nifti, copy_to_nifti)
    in = load_nifti(copy_from_nifti);
    out = load_nifti(copy_to_nifti);
    
    in.vol = out.vol;
    
    save_nifti(in, copy_to_nifti);
end