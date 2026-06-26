import src.DataModels.Arguments as ARGS

import argparse
import sys
import src.XNATQueryManager as QM
import src.Utils.Checks as Checks

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='A management System for the Ances MR Processing Pipeline. Provides functionality for synchronizing local data with remote XNAT data.',
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    #This is a hidden argument which is used by project manager to get relative paths to work.
    parser.add_argument(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME'],
                        required = False,
                        help     = argparse.SUPPRESS,
                        type     = str,
                        default  = ARGS.ARGS['COMMON']['EXEC_PATH']['DEFAULT'])     
    
    parser.add_argument(ARGS.ARGS['COMMON']['ENTRY_POINT']['NAME'],
                        required = False,
                        help     = ARGS.ARGS['COMMON']['ENTRY_POINT']['DESC'],
                        type     = str,
                        default  = ARGS.ARGS['COMMON']['ENTRY_POINT']['DEFAULT'])

    parser.add_argument(ARGS.ARGS['COMMON']['XNAT_SERVER']['NAME'],
                        required = False,
                        help     = ARGS.ARGS['COMMON']['XNAT_SERVER']['DESC'],
                        type     = str,
                        default  = ARGS.ARGS['COMMON']['XNAT_SERVER']['DEFAULT'])     

    parser.add_argument(ARGS.ARGS['COMMON']['LOG']['NAME'],
                        required = False,
                        help     = ARGS.ARGS['COMMON']['LOG']['DESC'],
                        type     = str,
                        default  = ARGS.ARGS['COMMON']['LOG']['DEFAULT'])

    parser.add_argument(ARGS.ARGS['COMMON']['PROJECT']['NAME'],
                        help     = ARGS.ARGS['COMMON']['PROJECT']['DESC'],
                        type     = str) 
    
    require_user_name   = False
    require_report_path = False

    sync_actions = parser.add_argument_group('Sync operations')
    
    sync_actions.add_argument(ARGS.ARGS['SYNC']['UPDATE_ACCESSION_IDS']['NAME'],
                              required=False,
                              help=ARGS.ARGS['SYNC']['UPDATE_ACCESSION_IDS']['DESC'],
                              action='store_true')

    sync_actions.add_argument(ARGS.ARGS['SYNC']['GENERATE_XNAT_REPORT']['NAME'],
                              required=False,
                              help=ARGS.ARGS['SYNC']['GENERATE_XNAT_REPORT']['DESC'],
                              action='store_true')
    
    if ARGS.ARGS['SYNC']['UPDATE_ACCESSION_IDS']['NAME'] in sys.argv:
        require_user_name   = True
    
    if ARGS.ARGS['SYNC']['GENERATE_XNAT_REPORT']['NAME'] in sys.argv:
        require_report_path = True
        require_user_name   = True
    
    #General Settings
    settings = parser.add_argument_group('Settings')
    
    settings.add_argument(ARGS.ARGS['COMMON']['USER_NAME']['NAME'],
                          required = False,
                          help     = ARGS.ARGS['COMMON']['USER_NAME']['DESC'],
                          type     = str)     
    
    settings.add_argument(ARGS.ARGS['COMMON']['REPORT_PATH']['NAME'],
                          required = False,
                          help     = ARGS.ARGS['COMMON']['REPORT_PATH']['DESC'],
                          type     = str)

    settings.add_argument(ARGS.ARGS['SYNC']['EXCLUDE_LOCAL']['NAME'],
                          required = False,
                          help     = ARGS.ARGS['SYNC']['EXCLUDE_LOCAL']['DESC'],
                          action   = 'store_true')

    
    args = parser.parse_args() 
        
    log_file = ''
    if args.log_file != '':
        log_file = Checks.expand_data_path(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['LOG']['NAME'])), 
                                           getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME'])))
    
    with QM.XNATQueryManager(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['ENTRY_POINT']['NAME'])),
                             getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['XNAT_SERVER']['NAME'])),
                             getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['USER_NAME']['NAME'])),
                             getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PROJECT']['NAME'])),
                             log_file) as query_manager:

        report_path = ''
        if require_report_path:
            report_path = Checks.expand_data_path(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['REPORT_PATH']['NAME'])), 
                                                  getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME'])))

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['SYNC']['GENERATE_XNAT_REPORT']['NAME'])):
            query_manager.generate_report(getattr(args, ARGS.strip_flag(ARGS.ARGS['SYNC']['EXCLUDE_LOCAL']['NAME'])), 
                                          report_path)

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['SYNC']['UPDATE_ACCESSION_IDS']['NAME'])):
            query_manager.update_accession_from_xnat()

