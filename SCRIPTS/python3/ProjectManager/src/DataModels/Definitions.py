from bson.objectid import ObjectId
import numpy
import os

MAXIMUM_SEARCH_DEPTH = 100


def compile_regex() -> dict:
    regex_patterns  = { 
        "patterns": {
            "ws"         :"([ \t]*)",
            "fnnq"       :"([/a-zA-Z0-9_\\.\\{\\}\\[\\]\\(\\)\\-:\\$\\*\\+]+)",
            "n"          :"(([1-9]\\d*))",
            "fn"         :"(${fnnq}|\"${fnnq}\")",
            "cm"         :"(${ws}#.*)",
            "fnlnp"      :"((${fn}${ws})*${fn})",
            "fnl"        :"((\\(${ws}?${fnlnp}?${ws}?\\))|${fn})"
        },
        "RULES": {
            "DCMROOT"   : "${ws}set${ws}dcmroot${ws}=${ws}${fn}?${ws}(${cm})?",
            "MB_FACTOR" : "${ws}set${ws}BOLD_MB_Factor${ws}=${ws}${n}${ws}(${cm})?"
        },
        "MODALITIES": {
            "TSE"     :"${ws}set${ws}tse${ws}=${ws}${fnl}?${ws}${cm}?",
            "FLAIR"   :"${ws}set${ws}flair${ws}=${ws}${fnl}?${ws}${cm}?",
            "MPRAGE"  :"${ws}set${ws}mprs${ws}=${ws}${fnl}?${ws}${cm}?",
            "DTI"     :"${ws}set${ws}DTI${ws}=${ws}${fnl}?${ws}${cm}?",
            "DWI"     :"${ws}set${ws}DWI${ws}=${ws}${fnl}?${ws}${cm}?",
            "ASL"     :"${ws}set${ws}ASL${ws}=${ws}${fnl}?${ws}${cm}?",
            "BOLD"    :"${ws}set${ws}BOLD${ws}=${ws}${fnl}?${ws}${cm}?",
            "FDG"     :"${ws}set${ws}FDG${ws}=${ws}${fnl}?${ws}${cm}?",
            "O2"      :"${ws}set${ws}O2${ws}=${ws}${fnl}?${ws}${cm}?",
            "CO"      :"${ws}set${ws}CO${ws}=${ws}${fnl}?${ws}${cm}?",
            "H2O"     :"${ws}set${ws}H2O${ws}=${ws}${fnl}?${ws}${cm}?",
            "PIB"     :"${ws}set${ws}PIB${ws}=${ws}${fnl}?${ws}${cm}?",
            "TAU"     :"${ws}set${ws}TAU${ws}=${ws}${fnl}?${ws}${cm}?"
        }
    }

    #Now lets compile the regex patterns for use anywhere in the program.
    tokens = []
    for tok in regex_patterns['patterns']:
        #Check to see if the current expression needs to be expanded with previous
        #expressions
        for previous in tokens:
            to_match = '${%s}' % previous
            regex_patterns['patterns'][tok] = regex_patterns['patterns'][tok].replace(to_match, regex_patterns['patterns'][previous])

        tokens.append(tok)

    #Now lets go through and expand and compile all the rules.
    regex = {
        "RULES"      : {},
        "MODALITIES" : {}
    }
    
    for key in regex:
        for rule in regex_patterns[key]:
            
            #expand out the rule
            expanded = regex_patterns[key][rule] 
            for pattern in regex_patterns['patterns']:
                expanded = expanded.replace('${%s}' % pattern, regex_patterns['patterns'][pattern])
            
            regex[key][rule] = expanded

    return regex

#Set the regex rules heregex.
REGEX_RULES = compile_regex()
        
COLORS = {
    'BLACK'     : "\033[30m",
    'RED'       : "\033[31m",
    'GREEN'     : "\033[32m",
    'YELLOW'    : "\033[33m",
    'BLUE'      : "\033[34m",
    'PURPLE'    : "\033[35m",
    'CYAN'      : "\033[36m",
    'WHITE'     : "\033[37m",
    'BOLD'      : "\033[01m",
    'UNDERLINE' : "\033[4m" ,
    'RESET'     : "\033[0m" 
}

def CLEAR_SCREEN() -> None:
    print("\033[2J\033[H", end="", flush=True)
       

MISSING_BY_TYPE = {
    str           : '',
    bool          : False,
    int           : 0,
    list          : [],
    dict          : {},
    ObjectId      : ObjectId(),
    numpy.float64 : 0
}

DICOM_TAGS = {
    'MODEL_NAME'       : ['ManufacturersModelName', 'ManufacturerModelName'],
    'ACQUISITION_TIME' : ['AcquisitionDateTime'],
    'SOFTWARE_VERSION' : ['SoftwareVersions'],
}

NIFTI_EXTENSIONS = ['nii','nii.gz']

DICOM_EXTENSION  = 'dcm'
PARAMS_EXTENSION = 'params'

PIPELINE_VERSION_TAG = '#Working Copy Root Path:'

#The following are regex patterns which will get compiled when this file is imported. These are used to detect what modalities are being used by session.
#These are global datamodel definitions which are used in ProjectManager.
#Database definitions
PROJECTS_INFO         = 'ProjectsInfo'
SESSIONS              = 'Sessions'
PET_SESSIONS          = 'Pet_Sessions'
FS_SESSION            = 'FS_SESSION'
PROJECTS              = 'Projects'
SCAN_LOCATIONS        = 'Scan_Locations'
PROJECT_ALIASES       = 'Project_Aliases'
NAMING_CONVENTIONS    = 'Naming_Conventions'
ALLOWED_PROC_STATUSES = 'Processing_Status'
ALLOWED_MODALITIES    = 'Modalities_Collected'
SCANNER_NAMES         = 'Scanner_Names'
FS_VERSION_TAGS       = 'Freesurfer_Version_Tags'
PROJECT_ID            = 'XNAT_ID'

#Subject specific definitions
MAP_ID                = 'participant_id'
SUBJECT_ACCESSION     = 'subject_accession'
SESSION_ACCESSION     = 'session_accession'
FS_ACCESSION          = 'fs_accession'
LONGITUDINAL          = 'Longitudinal'
DUPLICATES            = 'Duplicates'
SESSION_DATA          = 'Session_Data'
EXPANDED_SESSIONS     = 'Expanded_Sessions'

#Session specific definitions
SESSION_ID            = 'session_id'
FS_VERSION            = 'fs_version'
SCANNER               = 'scanner'
PIPELINE_VERSION      = 'pipeline'
SOFTWARE_VERSION      = 'software_version'
DATE_COLLECTED        = 'aquisition_date'
PROC_STATUS           = 'processing_status'
DATA_PATH             = 'data_path'
EXEC_ARGS             = 'execution_arguments'
EXEC_STATUS           = 'status'
PROJ_ALIAS            = 'project_alias'
MODS_COLLECTED        = 'modalities_collected'
SCAN_SOURCE           = 'scan_source'
DICOM_LIST            = 'dicom_list'
UNLINKED_DICOM_LIST   = 'unlinked_source_files'
PET_ID                = 'pet_id'
PET_ACCESSION         = 'pet_accession'

#File structure definitions
RAW_DATA     = 'rawdata'
IN_PROCESS   = 'InProcess'
PARTICIPANTS = 'Participants'
FS_PATH_NAME = 'Freesurfer'

#Session Linking variables
SOURCE_DIR   = 'source_dir'
LINKED       = 'is_linked'

#UNP related variables.
SCRATCH_DIR          = os.environ.get('SCRATCH')
PROJECTS_HOME        = os.environ.get('PROJECTS_HOME')
PROJECTS_DIR         = os.environ.get('PROJECTS_DIR')
SCANS_DIR            = 'Scans'
DEFAULT_DOWNLOAD_DIR = 'download_cache'

#XNAT Data mappings.
XNAT_UNIFICATION_MAPPINGS = {
    'SUBJECT_MAPPINGS' : {
        MAP_ID            : ['subject_label'],
        SUBJECT_ACCESSION : ['subjectid']
    },
    'MR_MAPPINGS' : {
        MAP_ID            : ['xnat_subjectdata_subject_label', 'label'],
        SUBJECT_ACCESSION : ['xnat_subjectdata_subjectid', 'subject_id'],
        SESSION_ID        : ['label'],
        SESSION_ACCESSION : ['session_id']
    },
    'FS_MAPPINGS' : {
        SUBJECT_ACCESSION : ['subject_id'],
        SESSION_ACCESSION : ['session_id'],
        FS_ACCESSION      : ['label', 'expt_id']
    },
    'PET_MAPPINGS' : {
        MAP_ID            : ['xnat_subjectdata_subject_label'],
        SUBJECT_ACCESSION : ['xnat_subjectdata_subjectid', 'subject_id'],
        PET_ID            : ['label'],
        PET_ACCESSION     : ['session_id']
    }
}

#Analysis Definitions.
ANALYSIS = 'Analysis'
BOLD_BPASS_SMOOTHING = 'BOLD_bpass_smoothing'
BOLD_RESID_SMOOTHING = 'BOLD_resid_smoothing'
BOLD_MEANS           = 'BOLD_network_means'
BOLD_MB_FACTOR = 'bold_multiband_factor'

ANALYSIS_FILE_TYPES = {
    'BOLD' : ['seed_corr']
}
ANALYSIS_FILE_EXTENSIONS = {
    'BOLD' : ['.mat']
}
MEAN_NETWORKS = {
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
NETWORK_MEANS = 'Network_Means'
