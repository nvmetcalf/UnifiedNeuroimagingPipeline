import argparse
import sys
import src.XNATQueryManager as QM
import src.Utils.Checks as Checks

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='A management System for the Ances MR Processing Pipeline. Provides functionality for synchronizing local data with remote XNAT data.',
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    #This is a hidden argument which is used by project manager to get relative paths to work.
    parser.add_argument('--execution_path',
                        required = False,
                        help = argparse.SUPPRESS,
                        type = str,
                        default = '')     
    
    parser.add_argument('--entry_point',
                        required = False,
                        help = 'The database name to connect to.',
                        default='ProjectManagerDB',
                        type=str)

    parser.add_argument('--server',
                        required = False,
                        help = 'Specify the target xnat server to connect to. Must be in the form "https://<server_name>/".',
                        type = str,
                        default = 'https://cnda.wustl.edu/')     
    
    require_user_name   = False
    require_project     = False
    require_report_path = False

    sync_actions = parser.add_argument_group('Sync operations')
    
    sync_actions.add_argument('--generate_cnda_report',
                              required = False,
                              help = f'Generate a report detailing up to date information from the XNAT server.',
                              action='store_true')
    
    sync_actions.add_argument('--generate_unlinked_sessions_report',
                              required = False,
                              help = f'Generate a report detailing all remote sessions that do not exist in ProjectManager.',
                              action='store_true')
    
    if '--generate_cnda_report' in sys.argv:
        require_report_path = True
        require_project     = True
        require_user_name   = True
    
    if '--generate_unlinked_sessions_report' in sys.argv:
        require_report_path = True
        require_project     = True
        require_user_name   = True
    
    #General Settings
    settings = parser.add_argument_group('Settings')
    
    settings.add_argument('--user_name',
                        required = require_user_name,
                        help = 'The user that is logging in to the xnat server.',
                        type = str)     
    
    settings.add_argument('--project',
                        required = require_project,
                        help = 'Specify the project of interest.',
                        type = str)
    
    settings.add_argument('--report_path',
                        required = require_report_path,
                        help = 'Specify the path to generate reports to.',
                        type = str)
    
    settings.add_argument('--include_mr',
                        required = False,
                        help = 'Include MR data from CNDA.',
                        action = 'store_true')
    
    settings.add_argument('--include_pet',
                        required = False,
                        help = 'Include PET data from CNDA.',
                        action = 'store_true')
    
    settings.add_argument('--include_fs',
                        required = False,
                        help = 'Include FS data from CNDA.',
                        action = 'store_true')
    
    args = parser.parse_args() 
    
    query_manager = QM.XNATQueryManager(database_name = args.entry_point,
                                        server = args.server)
    report_path = ''
    if require_report_path:
        report_path = Checks.expand_data_path(args.report_path, args.execution_path)

    if args.generate_cnda_report:
        query_manager.login(args.user_name)
        query_manager.generate_xnat_report(
            args.project,
            args.include_mr,
            args.include_pet,
            args.include_fs,
            report_path
        )
        query_manager.logout()

    if args.generate_unlinked_sessions_report:
        query_manager.login(args.user_name)
        query_manager.generate_missing_data_report(
            args.project,
            args.include_mr,
            args.include_pet,
            args.include_fs,
            report_path
        )
        query_manager.logout()

