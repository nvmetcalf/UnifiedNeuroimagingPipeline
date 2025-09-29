
%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

function run_process_ase_3_smoothing_ase(name_dir_ase, nnn, numEcho, numFrame)

name_dir_mc_ase    = sprintf('%s/MC_ASE', name_dir_ase);
name_dir_smoothing = sprintf('%s/MC_ASE/smoothing', name_dir_ase);

if ~exist(name_dir_smoothing)
    mkdir(name_dir_smoothing);
end;


fwhm = 10;
half_width = 2;

fwhmx = fwhm;
fwhmy = fwhm;
fwhmz = fwhm;

half_widthx = half_width;
half_widthy = half_width;
half_widthz = half_width;

nnn_root = nnn;

for indEcho=1:numEcho
    name_in = sprintf('%s/%s_ase_%d.nii.gz',           name_dir_mc_ase,    nnn_root, indEcho);
    name_mk = sprintf('%s/%s_ase_0_brain_mask.nii.gz', name_dir_ase,       nnn_root);
    name_out = sprintf('%s/%s_ase_%d.nii.gz',          name_dir_smoothing, nnn_root, indEcho);

    if ~exist(name_in)
        continue;
    end;

    nii_im = load_untouch_nii(name_in);
    nii_mk = load_untouch_nii(name_mk);

    px = nii_im.hdr.dime.pixdim(2);
    py = nii_im.hdr.dime.pixdim(3);
    pz = nii_im.hdr.dime.pixdim(4);

    im = nii_im.img;
    mk = nii_mk.img;

    [dimx, dimy, dimz, dimt] = size(im);
    im_out = zeros(dimx, dimy, dimz, dimt);

    mk = double(mk);
    im = double(im);

    if dimt~= numFrame
        fprintf('check %s, %d frames!\n', name_in, dimt);
    end;

    xin_range = [0:dimx-1]*px;
    yin_range = [0:dimy-1]*py;
    zin_range = [0:dimz-1]*pz;

    xmax = ceil((dimx-1)*px);
    ymax = ceil((dimy-1)*py);
    zmax = ceil((dimz-1)*pz);

    xout_range = [0:1:xmax];
    yout_range = [0:1:ymax];
    zout_range = [0:1:zmax];

    mk111 = imresample(mk, xin_range, yin_range, zin_range, xout_range, yout_range, zout_range, 'nearest');

    for k=1:dimt,
        im_tmp = squeeze(im(:,:,:,k));
        im111 = imresample(im_tmp, xin_range, yin_range, zin_range, xout_range, yout_range, zout_range, 'linear');
        im111s = truncated_gaussian_smoothing_3d_with_mask_c(im111, mk111, fwhmx, fwhmy, fwhmz, half_widthx, half_widthy, half_widthz);
        im_out_tmp = imresample(im111s, xout_range, yout_range, zout_range, xin_range, yin_range, zin_range, 'linear');
        im_out(:,:,:,k) = im_out_tmp;
        % fprintf('\n k=%d, %f, %f,  %f %f\n\n', k, min(im_tmp(:)), max(im_tmp(:)), min(im_out_tmp(:)), max(im_out_tmp(:)));
        clear im_tmp im_out_tmp im111 im111s;
    end;

    %for k=1:dimt,
    %   im_tmp = squeeze(im(:,:,:,k));
    %   im_out_tmp = gaussian_smoothing_3d_with_mask_nomask_constrained_c(im_tmp, mk, fwhmx, fwhmy, fwhmz);
    %   im_out(:,:,:,k) = im_out_tmp;
    %   clear im_tmp im_out_tmp;
    %end;

    nii_im.img = im_out; 
    save_untouch_nii(nii_im, name_out);

    fsl = sprintf('fslcpgeom %s %s', name_in, name_out);
    system(fsl);
    
    clear name_in name_mk name_out fsl xin_range yin_range zin_range xout_range yout_range zout_range;
    clear nii_im nii_mk mk111 mk im im_out;
end;

