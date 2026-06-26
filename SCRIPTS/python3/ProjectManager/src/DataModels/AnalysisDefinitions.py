#Analysis Definitions.
ANALYSIS       = 'Analysis'
QC_DIR         = 'QC'
ANALYSIS_TYPE  = 'type'

LAST_MODIFIED  = 'last_modified'
OWNER          = 'owner'

#BOLD
BOLD = 'BOLD'
BOLD_SEED_CORR_ANALYSIS  = 'BOLD_seed_corr_analysis'
BOLD_SEED_CORR_PATH  = 'BOLD_seed_corr_path'
BOLD_BPASS_SMOOTHING = 'BOLD_bpass_smoothing'
BOLD_RESID_SMOOTHING = 'BOLD_resid_smoothing'

#Column/Variable names
BOLD_MB_LEVEL        = 'BOLD_MB_level'
BOLD_ATLAS_ALIGNED   = 'BOLD_atlas_aligned'
BOLD_DENOISING       = 'BOLD_denoising'
BOLD_VAR_RATIO       = 'BOLD_var_ratio'
BOLD_TIME_REMAINING  = 'BOLD_time_remaining'
BOLD_TOTAL_FRAMES    = 'BOLD_total_frames'
BOLD_USABLE_FRAMES   = 'BOLD_usable_frames'
BOLD_FD              = 'BOLD_median_FD'

BOLD_TR              = 'BOLD_TR'
BOLD_TE              = 'BOLD_TE'

#BOLD metadata mapping.
BOLD_METADATA_KEYS = {
    BOLD_TR         : 'RepetitionTime',
    BOLD_TE         : 'EchoTime'
}

#BOLD UNP directory info.
BOLD_DIR = 'Functional'
BOLD_MOVEMENT_DIR = 'Movement'

#File paths and names.
BOLD_RUN_LIST_FILE            = 'movement_reg_images.lst'
BOLD_VARIANCE_FILE            = 'fMRI_denoising.txt'
BOLD_FD_EXTENSION             = 'ddat.fd'
BOLD_FRAME_MASK_EXTENSION     = 'ddat.tmask'
BOLD_TIME_REMAINING_EXTENSION = '_BOLD_frame_count_by_run.txt'
BOLD_BANDPASS                 = '_rsfMRI_uout_bpss_resid'
BOLD_RESID                    = '_rsfMRI_uout_resid_bpss'

BOLD_SECONDS_REMAINING_COL = 'SecondsRemaining'

BOLD_MEANS = 'BOLD_network_means'
BOLD_EXCLUDE_FIRST_FRAMES = 4
BOLD_MEAN_NETWORKS = {
    'Unassigned' : range(0, 25),
    'SM'         : range(25, 55),
    'SM_lat'     : range(55, 60),
    'CO'         : range(60, 74),
    'AUD'        : range(74, 87),
    'DMN'        : range(87, 144),
    'MEM'        : range(144, 149),
    'VIS'        : range(149, 180),
    'FP'         : range(180, 205),
    'SAL'        : range(205, 223),
    'SUBCort'    : range(223, 251),
    'VAN'        : range(251, 260),
    'DAN'        : range(260, 271),
    'CEREB'      : range(271, 298)
}

#General analysis type identification information.

#A central variable storing the locations where all analysis files are stored in the analysis document.

ANALYSIS_TYPES = {
    BOLD : {
        BOLD_SEED_CORR_ANALYSIS : {
            'FILE_TYPE' : ['seed_corr'],
            'FILE_EXTENSIONS' : ['mat']
        }
    }
}

