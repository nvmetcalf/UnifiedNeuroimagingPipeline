import src.DataModels.Arguments as ARGS

import src.ProjectManager as ProjectManager
import src.Utils.Checks as Checks
import argparse
import sys

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=('A management System for UNP Processing Pipeline. Provides '
                                                  'functionality to manage data in the ProjectManager database.'),
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    
    #This is a hidden argument which is used by project manager to get relative paths to work.
    parser.add_argument(
        ARGS.ARGS['COMMON']['EXEC_PATH']['NAME'],
        required=False,
        help=argparse.SUPPRESS,
        type=str,
        default=ARGS.ARGS['COMMON']['EXEC_PATH']['DEFAULT'])
    
    parser.add_argument(
        ARGS.ARGS['COMMON']['ENTRY_POINT']['NAME'],
        required = False,
        help     = ARGS.ARGS['COMMON']['ENTRY_POINT']['DESC'],
        type     = str,
        default  = ARGS.ARGS['COMMON']['ENTRY_POINT']['DEFAULT'])

    parser.add_argument(
        ARGS.ARGS['COMMON']['LOG']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['LOG']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['LOG']['DEFAULT'])
    
    parser.add_argument(
        ARGS.ARGS['COMMON']['PROJECT']['NAME'],
        help     = ARGS.ARGS['COMMON']['PROJECT']['DESC'],
        type     = str) 

    #Now add the potential options that can be executed. 
    require_project_alias     = False
    require_map_ids           = False
    require_report_path       = False
    require_ses_id            = False
    require_id_csv            = False
    require_id_col            = False
    require_sub_ses_strings   = False
    default_fuzzy_match_level = 0
    
    update_and_build = parser.add_argument_group('Update operations')

    #Update Options
    update_and_build.add_argument(
        ARGS.ARGS['MANAGE']['UPDATE']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['UPDATE']['DESC'],
        action='store_true')
    
    update_and_build.add_argument(
        ARGS.ARGS['MANAGE']['UPDATE_PROJECT_ALIAS']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['UPDATE_PROJECT_ALIAS']['DESC'],
        action='store_true')
    
    update_and_build.add_argument(
        ARGS.ARGS['MANAGE']['UPDATE_ACCESSION_FROM_CSV']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['UPDATE_ACCESSION_FROM_CSV']['DESC'],
        action='store_true')
    
    update_and_build.add_argument(
        ARGS.ARGS['MANAGE']['CLEAN_PROJECT']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['CLEAN_PROJECT']['DESC'],
        action='store_true')
    
    update_and_build.add_argument(
        ARGS.ARGS['MANAGE']['WIPE_METADATA']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['WIPE_METADATA']['DESC'],
        action='store_true')

    if ARGS.ARGS['MANAGE']['UPDATE_ACCESSION_FROM_CSV']['NAME'] in sys.argv:
        require_id_csv        = True
        require_id_col        = True
    
    #Report arguments.
    reports = parser.add_argument_group('Queries')
    reports.add_argument(
        ARGS.ARGS['MANAGE']['GENERATE_REPORT']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['GENERATE_REPORT']['DESC'],
        action='store_true')
    
    reports.add_argument(
        ARGS.ARGS['MANAGE']['GENERATE_SESSION_REPORT_BY_SUB_SES_STRING']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['GENERATE_SESSION_REPORT_BY_SUB_SES_STRING']['DESC'],
        action='store_true')
    
    reports.add_argument(
        ARGS.ARGS['MANAGE']['GENERATE_DUPLICATE_SESSIONS_REPORT']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['GENERATE_DUPLICATE_SESSIONS_REPORT']['DESC'],
        action='store_true')
    
    reports.add_argument(
        ARGS.ARGS['MANAGE']['GENERATE_SESSION_LINK_REPORT']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['GENERATE_SESSION_LINK_REPORT']['DESC'],
        action='store_true')
    
    reports.add_argument(
        ARGS.ARGS['MANAGE']['FIND_MULTIPLE_DATA_SOURCES']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['FIND_MULTIPLE_DATA_SOURCES']['DESC'],
        action='store_true')
    
    reports.add_argument(
        ARGS.ARGS['MANAGE']['EXPORT_ACCESSION_CSV']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['EXPORT_ACCESSION_CSV']['DESC'],
        action='store_true')

    #Now set the required arguments based on what was specified.
    if ARGS.ARGS['MANAGE']['GENERATE_REPORT']['NAME'] in sys.argv:
        require_report_path = True
    
    if ARGS.ARGS['MANAGE']['GENERATE_SESSION_REPORT_BY_SUB_SES_STRING']['NAME'] in sys.argv:
        require_sub_ses_strings = True
        require_report_path     = True

    if ARGS.ARGS['MANAGE']['GENERATE_DUPLICATE_SESSIONS_REPORT']['NAME'] in sys.argv:
        require_report_path = True
        default_fuzzy_match_level = 1

    if ARGS.ARGS['MANAGE']['GENERATE_SESSION_LINK_REPORT']['NAME'] in sys.argv:
        require_report_path = True
    
    if ARGS.ARGS['MANAGE']['FIND_MULTIPLE_DATA_SOURCES']['NAME'] in sys.argv:
        require_report_path = True
    
    if ARGS.ARGS['MANAGE']['EXPORT_ACCESSION_CSV']['NAME'] in sys.argv:
        require_report_path = True

    accession_ids = parser.add_argument_group('CNDA ID mapping settings and options')
    accession_ids.add_argument(
        ARGS.ARGS['COMMON']['DATA_FILE']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['DATA_FILE']['DESC'],
        type=str)
    
    accession_ids.add_argument(
        ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['PARTICIPANT_ID']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['PARTICIPANT_ID']['DEFAULT'])
    
    accession_ids.add_argument(
        ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['PARTICIPANT_ID']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['DEFAULT'])
    
    accession_ids.add_argument(
        ARGS.ARGS['COMMON']['SESSION_ID']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['SESSION_ID']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['SESSION_ID']['DEFAULT'])
    
    accession_ids.add_argument(
        ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['SESSION_ACCESSION']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['SESSION_ACCESSION']['DEFAULT'])
    
    accession_ids.add_argument(
        ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['FS_ACCESSION']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['FS_ACCESSION']['DEFAULT'])
    
    #Report extension options.
    extension = parser.add_argument_group('Extended Report Options.')
    
    extension.add_argument(
        ARGS.ARGS['MANAGE']['EXTEND_REPORT']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['EXTEND_REPORT']['DESC'],
        action='store_true')
    
    extension.add_argument(
        ARGS.ARGS['MANAGE']['JOIN_XNAT_DATA']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['JOIN_XNAT_DATA']['DESC'],
        action='store_true')

    #General Settings
    settings = parser.add_argument_group('Settings')
    
    settings.add_argument(
        ARGS.ARGS['MANAGE']['PROJECT_ALIAS']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['PROJECT_ALIAS']['DESC'],
        type=str)

    settings.add_argument(
        ARGS.ARGS['COMMON']['SUB_SES_STRINGS']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['SUB_SES_STRINGS']['DESC'],
        type=str,
        nargs='+')
    
    settings.add_argument(
        ARGS.ARGS['COMMON']['REPORT_PATH']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['REPORT_PATH']['DESC'],
        type=str)
    
    settings.add_argument(
        ARGS.ARGS['MANAGE']['INCLUDE_ANALYSIS']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['INCLUDE_ANALYSIS']['DESC'],
        action='store_true')
    
    settings.add_argument(
        ARGS.ARGS['MANAGE']['FILL_MISSING_INFO']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['FILL_MISSING_INFO']['DESC'],
        action='store_true')
    
    settings.add_argument(
        ARGS.ARGS['COMMON']['SEPARATE_SUBJECTS']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['SEPARATE_SUBJECTS']['DESC'],
        action='store_true')

    settings.add_argument(
        ARGS.ARGS['COMMON']['FORCE']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['FORCE']['DESC'],
        action='store_true')
    
    settings.add_argument(
        ARGS.ARGS['MANAGE']['FUZZY_MATCH_LEVEL']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['FUZZY_MATCH_LEVEL']['DESC'],
        type=int,
        default=ARGS.ARGS['MANAGE']['FUZZY_MATCH_LEVEL']['DEFAULT'])

    settings.add_argument(
        ARGS.ARGS['MANAGE']['DEEP_SEARCH']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['DEEP_SEARCH']['DESC'],
        action='store_true')
    
    settings.add_argument(
            ARGS.ARGS['COMMON']['XNAT_SERVER']['NAME'],
            required = False,
            help     = ARGS.ARGS['COMMON']['XNAT_SERVER']['DESC'],
            type     = str,
            default  = ARGS.ARGS['COMMON']['XNAT_SERVER']['DEFAULT'])     
    
    settings.add_argument(
        ARGS.ARGS['MANAGE']['SHOW_REMOTE_ID']['NAME'],
        required=False,
        help=ARGS.ARGS['MANAGE']['SHOW_REMOTE_ID']['DESC'],
        action='store_true')

    args = parser.parse_args() 

    log_file = ''
    if getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['LOG']['NAME'])) != '':
        log_file = Checks.expand_data_path(args.log_file, args.execution_path)

    #Create the ProjectManager instance.
    with ProjectManager.ProjectManager(
        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['ENTRY_POINT']['NAME'])),
        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PROJECT']['NAME'])),
        log_file,
        getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['DEEP_SEARCH']['NAME'])),
        getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['EXTEND_REPORT']['NAME'])),
        getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['JOIN_XNAT_DATA']['NAME'])),
        getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['SHOW_REMOTE_ID']['NAME'])),
        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['XNAT_SERVER']['NAME']))
    ) as project_manager:

        report_path = ''
        if require_report_path:
            report_path = Checks.expand_data_path(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['REPORT_PATH']['NAME'])), 
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME']))
            )

        accession_csv_path = ''
        if ARGS.ARGS['COMMON']['DATA_FILE']['NAME'] in sys.argv:
            accession_csv_path = Checks.expand_data_path(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['DATA_FILE']['NAME'])), 
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME']))
            )

        #Perform update operations.
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['UPDATE']['NAME'])):
            project_manager.update_project(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['FILL_MISSING_INFO']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME']))
            )

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['UPDATE_PROJECT_ALIAS']['NAME'])):
            project_manager.update_project_alias(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['PROJECT_ALIAS']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['FILL_MISSING_INFO']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME']))
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['UPDATE_ACCESSION_FROM_CSV']['NAME'])):
            project_manager.update_accession_values_from_csv(
                accession_csv_path,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME']))
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['CLEAN_PROJECT']['NAME'])):
            project_manager.clean_database()
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['WIPE_METADATA']['NAME'])):
            project_manager.wipe_metadata()
        
        #Perform report options.
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['GENERATE_REPORT']['NAME'])):
            project_manager.get_project_wide_report(
                report_path,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['INCLUDE_ANALYSIS']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SEPARATE_SUBJECTS']['NAME']))
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['GENERATE_SESSION_REPORT_BY_SUB_SES_STRING']['NAME'])):
            project_manager.get_session_report_by_sub_ses_string(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUB_SES_STRINGS']['NAME'])),
                report_path,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['INCLUDE_ANALYSIS']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SEPARATE_SUBJECTS']['NAME']))
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['GENERATE_DUPLICATE_SESSIONS_REPORT']['NAME'])):
            project_manager.get_duplicate_sessions_report_by_project(
                report_path,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['INCLUDE_ANALYSIS']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SEPARATE_SUBJECTS']['NAME']))
            )

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['GENERATE_SESSION_LINK_REPORT']['NAME'])):
            project_manager.get_session_link_mapping(
                report_path
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['FIND_MULTIPLE_DATA_SOURCES']['NAME'])):
            project_manager.find_multiple_definitions(
                report_path
            )

        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['MANAGE']['EXPORT_ACCESSION_CSV']['NAME'])):
            project_manager.export_accession_values(
                report_path,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME']))
            )
