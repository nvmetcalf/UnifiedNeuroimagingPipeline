DB_QUERY_COLLECTION = 'XNATQueryInfo'
NAME = 'query_name'
ELEMENTS = 'query_elemens'
ROOT = 'root_element'

#These are the default sessions which are loaded.
#Should match the names in associated query json files.
SUBJECT_ACCESSION_QUERY = 'subject_accession'
MR_ACCESSION_QUERY      = 'mr_accession'
PET_ACCESSION_QUERY     = 'pet_accession'

DEFAULT_QUERIES = {
    SUBJECT_ACCESSION_QUERY : {
        "subject_accession" : "subject_id",
        "subject_id"        : "subject_label"
    },
    MR_ACCESSION_QUERY : {
        "subject_accession" : "subject_id",
        "subject_id"        : "subject_label",
        "session_accession" : "session_id",
        "session_id"        : "label",
        "fs_accession"      : "fs_fsdata_expt_id"
    },
    PET_ACCESSION_QUERY : {
        "subject_accession" : "subject_id",
        "subject_id"        : "subject_label",
        "session_accession" : "session_id",
        "session_id"        : "label",
        "fs_accession"      : "fs_fsdata_expt_id"
    }
}

ROOT2QUERY = {
    'xnat:subjectData'    : SUBJECT_ACCESSION_QUERY,
    'xnat:mrSessionData'  : MR_ACCESSION_QUERY,
    'xnat:petSessionData' : PET_ACCESSION_QUERY
}

