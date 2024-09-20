from bson.objectid import ObjectId
import os

def compile_regex() -> dict:
    regex_patterns  = { 
        "patterns": {
            "ws"         :"([ \t]*)",
            "fnnq"       :"([/a-zA-Z0-9_\\.\\{\\}\\[\\]\\(\\)\\-:\\$\\*\\+]+)",
            "fn"         :"(${fnnq}|\"${fnnq}\")",
            "cm"         :"(${ws}#.*)",
            "fnlnp"      :"((${fn}${ws})*${fn})",
            "fnl"        :"((\\(${ws}?${fnlnp}?${ws}?\\))|${fn})"
        },
        "RULES": {
            "DCMROOT" :"${ws}set${ws}dcmroot${ws}=${ws}${fn}?${ws}${cm}?"
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
    str      : '',
    list     : [],
    ObjectId : ObjectId()            
}

DICOM_TAGS = {
    'MODEL_NAME'       : ['ManufacturersModelName', 'ManufacturerModelName'],
    'ACQUISITION_TIME' : ['AcquisitionDateTime'],
    'SOFTWARE_VERSION' : ['SoftwareVersions'],
}
DICOM_EXTENSION  = 'dcm'
PARAMS_EXTENSION = 'params'

PIPELINE_VERSION_TAG = '#Working Copy Root Path:'

#The following are regex patterns which will get compiled when this file is imported. These are used to detect what modalities are being used by session.
#These are global datamodel definitions which are used in ProjectManager.
#Database definitions
PROJECTS_INFO         = 'ProjectsInfo'
SESSIONS              = 'Sessions'
PROJECTS              = 'Projects'
SCAN_LOCATIONS        = 'Scan_Locations'
PROJECT_ALIASES       = 'Project_Aliases'
NAMING_CONVENTIONS    = 'Naming_Conventions'
ALLOWED_PROC_STATUSES = 'Processing_Status'
ALLOWED_MODALITIES    = 'Modalities_Collected'
SCANNER_NAMES         = 'Scanner_Names'
FS_VERSION_TAGS       = 'Freesurfer_Version_Tags'

#Subject specific definitions
MAP_ID                = 'participant_id'
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
PROJ_ALIAS            = 'project_alias'
MODS_COLLECTED        = 'modalities_collected'
SCAN_SOURCE           = 'scan_source'

#File structure definitions
RAW_DATA     = 'rawdata'
IN_PROCESS   = 'InProcess'
FS_PATH_NAME = 'Freesurfer'

#UNP related variables.
SCRATCH_DIR          = os.environ.get('SCRATCH')
PROJECTS_HOME        = os.environ.get('PROJECTS_HOME')
PROJECTS_DIR         = os.environ.get('PROJECTS_DIR')
SCANS_DIR            = 'Scans'
DEFAULT_DOWNLOAD_DIR = 'download_cache'
