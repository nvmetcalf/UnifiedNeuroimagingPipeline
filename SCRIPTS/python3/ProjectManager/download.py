import src.DataModels.Arguments as ARGS

import argparse
import sys
import src.DownloadManager as DownloadManager
import src.Utils.Checks as Checks

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=('A management System for the Ances MR Processing Pipeline. Provides '
                                                  'functionality for downloading and managing new data.'),
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    #This is a hidden argument which is used by project manager to get relative paths to work.
    parser.add_argument(
        ARGS.ARGS['COMMON']['EXEC_PATH']['NAME'],
        required=False,
        help=argparse.SUPPRESS,
        type=str,
        default=ARGS.ARGS['COMMON']['EXEC_PATH']['DEFAULT'])
    
    parser.add_argument(
        ARGS.ARGS['COMMON']['LOG']['NAME'],
        required = False,
        help     = ARGS.ARGS['COMMON']['LOG']['DESC'],
        type     = str,
        default  = ARGS.ARGS['COMMON']['LOG']['DEFAULT'])
    
    parser.add_argument(
        ARGS.ARGS['COMMON']['ENTRY_POINT']['NAME'],
        required = False,
        help     = ARGS.ARGS['COMMON']['ENTRY_POINT']['DESC'],
        type     = str,
        default  = ARGS.ARGS['COMMON']['ENTRY_POINT']['DEFAULT'])

    parser.add_argument(
        ARGS.ARGS['COMMON']['XNAT_SERVER']['NAME'],
        required = False,
        help     = ARGS.ARGS['COMMON']['XNAT_SERVER']['DESC'],
        type     = str,
        default  = ARGS.ARGS['COMMON']['XNAT_SERVER']['DEFAULT'])     
    
    parser.add_argument(
        ARGS.ARGS['DOWNLOAD']['TARGET_DOWNLOAD_PATH']['NAME'],
        required = False,
        help     = ARGS.ARGS['DOWNLOAD']['TARGET_DOWNLOAD_PATH']['DESC'],
        type     = str,
        default  = ARGS.ARGS['DOWNLOAD']['TARGET_DOWNLOAD_PATH']['DEFAULT'])     
   
    parser.add_argument(
        ARGS.ARGS['COMMON']['DATA_FILE']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['DATA_FILE']['DESC'],
        type=str)
    
    parser.add_argument(
        ARGS.ARGS['COMMON']['PROJECT']['NAME'],
        help     = ARGS.ARGS['COMMON']['PROJECT']['DESC'],
        type     = str) 

    require_user_name                 = False
    
    download_actions = parser.add_argument_group('Download operations')
    
    download_actions.add_argument(
        ARGS.ARGS['DOWNLOAD']['DOWNLOAD']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['DOWNLOAD']['DESC'],
        action='store_true')
    
    download_actions.add_argument(
        ARGS.ARGS['DOWNLOAD']['EXTRACT_AND_PROPAGATE_ALL']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['EXTRACT_AND_PROPAGATE_ALL']['DESC'],
        action='store_true')

    download_actions.add_argument(
        ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_ALL']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_ALL']['DESC'],
        action='store_true')
    
    download_actions.add_argument(
        ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_MR']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_MR']['DESC'],
        action='store_true')
    
    download_actions.add_argument(
        ARGS.ARGS['DOWNLOAD']['DOWNLOAD_MR']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['DOWNLOAD_MR']['DESC'],
        action='store_true')
    
    download_actions.add_argument(
        ARGS.ARGS['DOWNLOAD']['EXTRACT_AND_PROPAGATE_MR']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['EXTRACT_AND_PROPAGATE_MR']['DESC'],
        action='store_true')
    
    download_actions.add_argument(
        ARGS.ARGS['DOWNLOAD']['EXTRACT_FS']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['EXTRACT_FS']['DESC'],
        action='store_true')
    
    sync_actions = parser.add_argument_group('Sync operations')
    #Require either data_paths or a source csv file to run.
    if ARGS.ARGS['DOWNLOAD']['DOWNLOAD']['NAME'] in sys.argv:
        require_user_name  = True
    
    if ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_ALL']['NAME'] in sys.argv:
        require_user_name  = True
    
    if ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_MR']['NAME'] in sys.argv:
        require_user_name  = True
    
    if ARGS.ARGS['DOWNLOAD']['DOWNLOAD_MR']['NAME'] in sys.argv:
        require_user_name  = True

    if '--project_alias_data_column' in sys.argv and '--global_project_alias' in sys.argv:
        print('You cannot specify both a global propagation alias and a project alias propagation data column.')
        print('Specify one or the other.')
        print()
        parser.print_help()
        sys.exit(1)
    
    #General Settings
    settings = parser.add_argument_group('Settings')

    settings.add_argument(
        ARGS.ARGS['COMMON']['USER_NAME']['NAME'],
        required=require_user_name,
        help=ARGS.ARGS['COMMON']['USER_NAME']['DESC'],
        type=str)

    settings.add_argument(
        ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['PARTICIPANT_ID']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['PARTICIPANT_ID']['DEFAULT'])
    
    settings.add_argument(
        ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['PARTICIPANT_ID']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['DEFAULT'])
    
    settings.add_argument(
        ARGS.ARGS['COMMON']['SESSION_ID']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['SESSION_ID']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['SESSION_ID']['DEFAULT'])
    
    settings.add_argument(
        ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['SESSION_ACCESSION']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['SESSION_ACCESSION']['DEFAULT'])
    
    settings.add_argument(
        ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['FS_ACCESSION']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['FS_ACCESSION']['DEFAULT'])

    settings.add_argument(
        ARGS.ARGS['DOWNLOAD']['SCAN_SOURCE_DATA_COLUMN']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['SCAN_SOURCE_DATA_COLUMN']['DESC'],
        type=str)

    settings.add_argument(
        ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['DESC'],
        type=str)
    
    settings.add_argument(
        ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['DESC'],
        action='store_true')
    
    settings.add_argument(
        ARGS.ARGS['DOWNLOAD']['GLOBAL_PROJECT_ALIAS']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['GLOBAL_PROJECT_ALIAS']['DESC'],
        type=str,
        default=None)
    
    settings.add_argument(
        ARGS.ARGS['DOWNLOAD']['NO_CLEAN_UP']['NAME'],
        required=False,
        help=ARGS.ARGS['DOWNLOAD']['NO_CLEAN_UP']['DESC'],
        action='store_true')

    args = parser.parse_args() 
    
    #Process the paths.
    target_csv_file = Checks.expand_data_path(
        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['DATA_FILE']['NAME'])), 
        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME']))
    )

    log_file = ''
    if getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['LOG']['NAME'])) != '':
        log_file = Checks.expand_data_path(args.log_file, args.execution_path)
    
    target_download_path = None
    if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['TARGET_DOWNLOAD_PATH']['NAME'])) != '':
        target_download_path = Checks.expand_data_path(
            getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['TARGET_DOWNLOAD_PATH']['NAME'])), 
            getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME']))
        )
    
    clean_up = not getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['NO_CLEAN_UP']['NAME']))
    
    with DownloadManager.DownloadManager(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['ENTRY_POINT']['NAME'])),
                                         getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['XNAT_SERVER']['NAME'])), 
                                         getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PROJECT']['NAME'])),
                                         target_csv_file,
                                         target_download_path,
                                         log_file) as downloader:

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['DOWNLOAD']['NAME'])):
            downloader.login(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['USER_NAME']['NAME'])))
            downloader.download_all_data(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME']))
            )
            downloader.logout()

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['EXTRACT_AND_PROPAGATE_ALL']['NAME'])):
            
            alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['GLOBAL_PROJECT_ALIAS']['NAME']))
            if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])):
                alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['NAME']))

            downloader.extract_and_propagate_all(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME'])),
                alias,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['SCAN_SOURCE_DATA_COLUMN']['NAME'])),
                clean_up
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_ALL']['NAME'])):
            downloader.login(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['USER_NAME']['NAME'])))
            downloader.download_all_data(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME']))
            )
            downloader.logout()

            alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['GLOBAL_PROJECT_ALIAS']['NAME']))
            if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])):
                alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['NAME']))

            downloader.extract_and_propagate_all(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PROJECT']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME'])),
                alias,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['SCAN_SOURCE_DATA_COLUMN']['NAME'])),
                clean_up
            )

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_MR']['NAME'])):
            downloader.login(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['USER_NAME']['NAME'])))
            downloader.download_all_data(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME']))
            )
            downloader.logout()

            alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['GLOBAL_PROJECT_ALIAS']['NAME']))
            if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])):
                alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['NAME']))

            downloader.extract_and_propagate_mr(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                alias,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['SCAN_SOURCE_DATA_COLUMN']['NAME'])),
                clean_up
            )
        
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['EXTRACT_AND_PROPAGATE_MR']['NAME'])):
            alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['GLOBAL_PROJECT_ALIAS']['NAME']))
            if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])):
                alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['NAME']))

            downloader.extract_and_propagate_mr(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                alias,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['SCAN_SOURCE_DATA_COLUMN']['NAME'])),
                clean_up
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['DOWNLOAD_AND_PROPAGATE_MR']['NAME'])):
            downloader.login(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['USER_NAME']['NAME'])))
            downloader.download_mr(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
            )
            downloader.logout()

            alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['GLOBAL_PROJECT_ALIAS']['NAME']))
            if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])):
                alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['NAME']))

            downloader.extract_and_propagate_mr(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUBJECT_ACCESSION']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ACCESSION']['NAME'])),
                alias,
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['SCAN_SOURCE_DATA_COLUMN']['NAME'])),
                clean_up
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['EXTRACT_FS']['NAME'])):
            alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['GLOBAL_PROJECT_ALIAS']['NAME']))
            if getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['ALIAS_IN_CSV']['NAME'])):
                alias = getattr(args, ARGS.strip_flag(ARGS.ARGS['DOWNLOAD']['PROJECT_ALIAS_DATA_COLUMN']['NAME']))

            downloader.extract_fs(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PROJECT']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PARTICIPANT_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SESSION_ID']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FS_ACCESSION']['NAME'])),
                clean_up
            )
