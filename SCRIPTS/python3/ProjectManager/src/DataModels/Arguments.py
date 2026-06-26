import src.DataModels.ColumnNames as ColumnNames

ARGS = {
    'SYNC' : {
        'UPDATE_ACCESSION_IDS': {
            'NAME': '--update_accession_ids',
            'DESC': 'Update accession IDs from XNAT server. Uses exact match when available.'
        },
        'GENERATE_XNAT_REPORT': {
            'NAME': '--generate_xnat_report',
            'DESC': 'Generate a report detailing up to date information from the XNAT server.'
        },
        'EXCLUDE_LOCAL': {
            'NAME': '--exclude_local',
            'DESC': 'Exclude data in generated reports that exists locally.'
        }
    },
    'RUN' : {
        'NUM_CORES': {
            'NAME': '--num_processes',
            'DESC': 'The amount of processes to use for processing.',
            'DEFAULT': 1
        },
        'RUN_PROCESSING_COMMAND': {
            'NAME': '--run_processing_command',
            'DESC': 'Specify what processing command to run'
        },
        'DATA_PATH_COL': {
            'NAME': '--data_path_col',
            'DESC': 'The name of the data paths column in the data file.',
            'DEFAULT': ColumnNames.DATA_PATH
        },
        'RUN_IN_DATA_PATHS': {
            'NAME': '--run_in_data_paths',
            'DESC': 'Run the current command at the location of every specified data path'
        },
        'RUN_IN_PROCESSING_DIR': {
            'NAME': '--run_in_processing_dir',
            'DESC': 'Run the current command at the location specified in the processing dir for this path. For instance, the path /A/B/C/sub-aaaa_ses-bbbbb would execute in the directory /A/B/C/.'
        },
        'LIST_VALID_COMMANDS': {
            'NAME': '--list_valid_commands',
            'DESC': 'Lists commands that can be executed.'
        },
        'FIND_SUB': {
            'NAME': '--find_sub',
            'DESC': 'Extract the subject ID (format: sub_xxxxx) from the file path and use it in place of this argument.'
        },
        'FIND_SES': {
            'NAME': '--find_ses',
            'DESC': 'Extract the session ID (format: -ses_yyyyy) from the file path and use it in place of this argument.'
        },
        'FIND_ALIAS': {
            'NAME': '--find_alias',
            'DESC': 'Find the project alias from the given file path and use it in place of this argument.'
        },
        'FIND_PARAMS': {
            'NAME': '--find_params',
            'DESC': 'Will replace this argument with the ".params" file found at the execution path for this command.'
        },
        'USE_BASENAME': {
            'NAME': '--use_basename',
            'DESC': 'Use the specified data path as a parameter for the execution command.'
        },
        'ARGS_IN_CSV': {
            'NAME': '--args_in_csv',
            'DESC': 'Look at data_file for execution arguments.'
        },
        'EXEC_ON_MATCH': {
            'NAME': '--exec_on_match',
            'DESC': 'Only process this row in the data file if the execution status matches this value.'
        }
    },
    'MANAGE': {
        'UPDATE': {
            'NAME': '--update',
            'DESC': 'Update a specific project individually.'
        },
        'UPDATE_PROJECT_ALIAS': {
            'NAME': '--update_project_alias',
            'DESC': 'Update a specific project alias individually.'
        },
        'UPDATE_ACCESSION_FROM_CSV': {
            'NAME': '--update_accession_from_csv',
            'DESC': 'Update a specific project alias individually.'
        },
        'CLEAN_PROJECT': {
            'NAME': '--clean_project',
            'DESC': 'Clean up all database entries relating to a project.'
        },
        'GENERATE_REPORT': {
            'NAME': '--generate_report',
            'DESC': 'Generate a report detailing all information pertaining to a specific project in the DB.'
        },
        'GENERATE_SESSION_REPORT_BY_SUB_SES_STRING': {
            'NAME': '--generate_session_report_by_sub_ses_strings',
            'DESC': ('Given a list of sub/ses strings (sub_xxxx-ses_yyyy). Generate a report about all information '
                     'pertaining to that subject and session in the DB.')
        },
        'GENERATE_DUPLICATE_SESSIONS_REPORT': {
            'NAME': '--generate_duplicate_sessions_report',
            'DESC': 'Generate a report detailing all duplicate sessions pertaining to a specific project in the DB.'
        },
        'GENERATE_SESSION_LINK_REPORT': {
            'NAME': '--generate_session_link_report',
            'DESC': 'Generate a report detailing all scan sources and their links in a project.'
        },
        'FIND_MULTIPLE_DATA_SOURCES': {
            'NAME': '--find_multiple_data_sources',
            'DESC': 'Generate a report detailing all data sources that have multiple locations.'
        },
        'EXPORT_ACCESSION_CSV': {
            'NAME': '--export_accession_csv',
            'DESC': 'Export the accession values from the database to a csv file.'
        },
        'EXTEND_REPORT': {
            'NAME': '--extend_report',
            'DESC': ('Include a list of all nifti files found for each session. Requires a search of every subject '
                     'included in the report.')
        },
        'JOIN_XNAT_DATA': {
            'NAME': '--join_xnat_data',
            'DESC': 'Join local reports with remote xnat data.'
        },
        'PROJECT_ALIAS': {
            'NAME': '--project_alias',
            'DESC': 'Specify the project alias of interest.'
        },
        'FILL_MISSING_INFO': {
            'NAME': '--fill_missing_info',
            'DESC': 'If any data cannot be automatically detected, fill it in manually.'
        },
        'FUZZY_MATCH_LEVEL': {
            'NAME': '--fuzzy_match_level',
            'DESC': 'Specify how closely session ids are required to match in order to fuzzy match.',
            'DEFAULT' : 0
        },
        'DEEP_SEARCH': {
            'NAME': '--deep_search',
            'DESC': ('Default behavior is to stop searching deeper directories when a session folder is found. This '
                     'option will recursively search everywhere.')
        },
        'SHOW_REMOTE_ID': {
            'NAME': '--show_remote_id',
            'DESC': 'Show the remote id columns pulled from xnat.'
        },
        'WIPE_METADATA': {
            'NAME': '--wipe_metadata',
            'DESC': 'Wipe metadata including: subject, session, and fs accession values from the DB.'
        },
        'INCLUDE_ANALYSIS': {
            'NAME': '--include_analysis',
            'DESC': 'Include analysis in generated reports.'
        }
    },
    'DOWNLOAD': {
        'TARGET_DOWNLOAD_PATH': {
            'NAME'    : '--target_download_path',
            'DESC' : 'Specify the target path to download data to. Default defined in ProjectManager database.',
            'DEFAULT' : ''
        },
        'DOWNLOAD': {
            'NAME': '--download',
            'DESC': ('Given a csv file specifying the: subject id, cnda session accession id, and the fs accession '
                     'id. Download the specified subjects and data files.')
        },
        'EXTRACT_AND_PROPAGATE_ALL': {
            'NAME': '--extract_and_propagate_all',
            'DESC': ('Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs '
                     'accession id. Extract downloaded files to Scans and propagate specified sessions into')
        },
        'DOWNLOAD_AND_PROPAGATE_MR': {
            'NAME': '--download_and_propagate_mr',
            'DESC': ('Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs '
                     'accession id. Download the specified subjects and data files.')
        },
        'DOWNLOAD_AND_PROPAGATE_ALL': {
            'NAME': '--download_and_propagate_all',
            'DESC': ('Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs '
                     'accession id. Download the specified subjects and data files.')
        },
        'DOWNLOAD_MR': {
            'NAME': '--download_mr',
            'DESC': ('Given a csv file specifying the: cnda session accession id, and the fs accession id. Download '
                     'the specified subjects and data files.')
        },
        'EXTRACT_AND_PROPAGATE_MR': {
            'NAME': '--extract_and_propagate_mr',
            'DESC': ('Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs '
                     'accession id. Extract downloaded files to Scans and propagate specified sessions into')
        },
        'DOWNLOAD_FS': {
            'NAME': '--download_fs',
            'DESC': ('Given a csv file specifying the: cnda session accession id, and the fs accession id. Download '
                     'the specified subjects and data files.')
        },
        'EXTRACT_FS': {
            'NAME': '--extract_fs',
            'DESC': ('Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs '
                     'accession id. Extract downloaded files to Scans and propagate specified sessions into')
        },
        'SCAN_SOURCE_DATA_COLUMN': {
            'NAME': '--scan_source_data_column',
            'DESC': 'Specify the data column to read scan source extraction locations from in the target_csv_file.'
        },
        'PROJECT_ALIAS_DATA_COLUMN': {
            'NAME': '--project_alias_data_column',
            'DESC': 'Specify the data column to read what project to propagate into in the target_csv_file.'
        },
        'ALIAS_IN_CSV': {
            'NAME': '--alias_in_csv',
            'DESC': 'Look at data_file for execution arguments.'
        },
        'GLOBAL_PROJECT_ALIAS': {
            'NAME': '--global_project_alias',
            'DESC': 'Specify the project of interest.'
        },
        'NO_CLEAN_UP': {
            'NAME': '--no_clean_up',
            'DESC': 'Dont remove successful propagations out of the download cache.'
        }
    },
    'ANALYZE': {
        'RUN_BOLD_SMOOTHING': {
            'NAME': '--run_bold_smoothing',
            'DESC': 'Run gaussian smoothing on all completed BOLD volumes in a project.'
        },
        'RUN_BOLD_SEED_CORR': {
            'NAME': '--run_bold_seed_corr',
            'DESC': 'Run volume seed correlation on all completed BOLD volumes in a project.'
        },
        'RUN_BOLD_POST_PROC': {
            'NAME': '--run_bold_post_proc',
            'DESC': 'Run smoothing and volume seed correlation on all completed BOLD volumes in a project.'
        },
        'RUN_SESSION_BOLD_SMOOTHING': {
            'NAME': '--run_session_bold_smoothing',
            'DESC': 'Run gaussian smoothing on specified sessions for completed BOLD volumes in a project.'
        },
        'RUN_SESSION_BOLD_SEED_CORR': {
            'NAME': '--run_session_bold_seed_corr',
            'DESC': 'Run volume seed correlation on specified sessions for completed BOLD volumes in a project.'
        },
        'RUN_SESSION_BOLD_POST_PROC': {
            'NAME': '--run_session_bold_post_proc',
            'DESC': 'Run smoothing and volume seed correlation specified sessions for completed BOLD volumes in a project.'
        },
        'CLEAN': {
            'NAME': '--clean',
            'DESC': 'Clear extracted information from analysis DB entries.'
        },
        'EXTRACT_BOLD_QC': {
            'NAME': '--extract_bold_qc',
            'DESC': 'Extract BOLD QC data from indexed files.'
        },
        'EXTRACT_BOLD_NETWORK_MEANS': {
            'NAME': '--extract_bold_means',
            'DESC': 'Extract BOLD average network means from indexed files.'
        },
        'SEED_CORR_OUTPUT_PATH': {
            'NAME': '--seed_corr_output_path',
            'DESC': 'Specify the path to output seed correlation matrices to. This is a relative path within a given project alias Analysis folder.'
        },
        'SMOOTHING_VALUE': {
            'NAME': '--smoothing_value',
            'DESC': 'Set the smoothing value to use.',
            'DEFAULT': 7.0
        },
        'EXCLUDE_NETWORKS': {
            'NAME': '--exclude_networks',
            'DESC': 'A list of networks to exclude when generating network means reports.',
            'DEFAULT': ['Unassigned']
        }
    },
    'COMMON': {
        'EXEC_PATH': {
            'NAME'    : '--execution_path',
            'DEFAULT' : ''
        },
        'ENTRY_POINT': {
            'NAME'    : '--entry_point', 
            'DESC'    : 'The database name to connect to.',
            'DEFAULT' : 'ProjectManagerDB'
        },
        'XNAT_SERVER': {
            'NAME'    : '--xnat_server', 
            'DESC'    : 'Specify the target xnat server to connect to. Must be in the form "https://<server_name>/".',
            'DEFAULT' : 'https://cnda.wustl.edu/'
        },
        'LOG' : {
            'NAME'    : '--log_file',
            'DESC'    : 'The file to log to.',
            'DEFAULT' : ''
        },
        'PROJECT': {
            'NAME': 'project',
            'DESC': 'The project to do operations on.'
        },
        'USER_NAME': {
            'NAME': '--user_name',
            'DESC': 'The user that is logging in to the xnat server.'
        },
        'REPORT_PATH': {
            'NAME': '--report_path',
            'DESC': 'Specify the path to generate reports to.'
        },
        'DATA_PATH': {
            'NAME'    : f'--{ColumnNames.DATA_PATH}', 
            'DESC'    : 'Specify the data column to extract data paths from.',
            'DEFAULT' : ColumnNames.DATA_PATH
        },
        'DATA_FILE': {
            'NAME': '--data_file',
            'DESC': 'Specify a CSV file which contains the data paths of interest.'
        },
        'EXEC_ARGS': {
            'NAME': f'--{ColumnNames.EXEC_ARGS}',
            'DESC': 'Specify the data column which contains specific command execution arguments.',
            'DEFAULT': ColumnNames.EXEC_ARGS
        },
        'EXEC_STATUS': {
            'NAME': f'--{ColumnNames.EXEC_STATUS}',
            'DESC': 'Specify the data column which contains the execution status.',
            'DEFAULT': ColumnNames.EXEC_STATUS
        },
        'PARTICIPANT_ID': {
            'NAME': f'--{ColumnNames.PARTICIPANT_ID}',
            'DESC': 'The column which stores subject IDs.',
            'DEFAULT': ColumnNames.PARTICIPANT_ID
        },
        'SUBJECT_ACCESSION': {
            'NAME': f'--{ColumnNames.SUBJECT_ACCESSION}',
            'DESC': 'The column which stores subject accession IDs.',
            'DEFAULT': ColumnNames.SUBJECT_ACCESSION
        },
        'SESSION_ID': {
            'NAME': f'--{ColumnNames.SESSION_ID}',
            'DESC': 'The column which stores session IDs.',
            'DEFAULT': ColumnNames.SESSION_ID
        },
        'SESSION_ACCESSION': {
            'NAME': f'--{ColumnNames.SESSION_ACCESSION}',
            'DESC': 'The column which stores session accession IDs.',
            'DEFAULT': ColumnNames.SESSION_ACCESSION
        },
        'FS_ACCESSION': {
            'NAME': f'--{ColumnNames.FS_ACCESSION}',
            'DESC': 'The column which stores fs accession IDs.',
            'DEFAULT': ColumnNames.FS_ACCESSION
        },
        'SEPARATE_SUBJECTS': {
            'NAME': '--separate_subjects',
            'DESC': 'Seperate subjects by an empty row in generated reports.'
        },
        'FORCE': {
            'NAME': '--force',
            'DESC': 'Force old data to be overwritten with incoming data when conflicts exist.'
        },
        'SUB_SES_STRINGS': {
            'NAME': '--sub_ses_strings',
            'DESC': 'Specify UNP sub_xxxx-ses_yyyyy strings to search for.'
        }
    }
}

def strip_flag(argument: str) -> str:
    if argument.startswith('--'):
        return argument[2:]

    return argument
