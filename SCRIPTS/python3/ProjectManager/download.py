import argparse
import sys
import src.DataModels.Definitions as Definitions
import src.DownloadManager as DownloadManager
import src.Utils.Checks as Checks

if __name__ == '__main__':

    
    parser = argparse.ArgumentParser(description='A management System for the Ances MR Processing Pipeline. Provides functionality for downloading and managing new data.',
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
    
    parser.add_argument('--target_download_path',
                        required = False,
                        help = 'Specify the target path to download data to. Default defined in ProjectManager database.',
                        type = str,
                        default = None)     
    
    parser.add_argument('--target_csv_file',
                        required = True,
                        help = 'Specify data paths of interest.',
                        type = str)     

    require_project                   = False
    require_user_name                 = False
    require_project_alias_data_column = False
    require_global_project_alias      = False
    
    download_actions = parser.add_argument_group('Download operations')

    download_actions.add_argument('--download_all',
                                  required = False,
                                  help = f'Given a csv file specifying the: cnda session accession id, and the fs accession id. Download the specified subjects and data files.',
                                  action='store_true')
    
    download_actions.add_argument('--extract_and_propagate_all',
                                  required = False,
                                  help = f'Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs accession id. Extract downloaded files to Scans and propagate specified sessions into',
                                  action='store_true')
    
    download_actions.add_argument('--download_and_propagate_all',
                                  required = False,
                                  help = f'Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs accession id. Download the specified subjects and data files.',
                                  action='store_true')
    
    download_actions.add_argument('--download_and_propagate_mr',
                                  required = False,
                                  help = f'Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs accession id. Download the specified subjects and data files.',
                                  action='store_true')
    
    download_actions.add_argument('--download_mr',
                                  required = False,
                                  help = f'Given a csv file specifying the: cnda session accession id, and the fs accession id. Download the specified subjects and data files.',
                                  action='store_true')
    
    download_actions.add_argument('--extract_and_propagate_mr',
                                  required = False,
                                  help = f'Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs accession id. Extract downloaded files to Scans and propagate specified sessions into',
                                  action='store_true')
    
    download_actions.add_argument('--download_fs',
                                  required = False,
                                  help = f'Given a csv file specifying the: cnda session accession id, and the fs accession id. Download the specified subjects and data files.',
                                  action='store_true')
    
    download_actions.add_argument('--extract_fs',
                                  required = False,
                                  help = f'Given a csv file specifying the: map id, session_id, cnda session accession id, and the fs accession id. Extract downloaded files to Scans and propagate specified sessions into',
                                  action='store_true')
    
    
    sync_actions = parser.add_argument_group('Sync operations')
    
    #Require either data_paths or a source csv file to run.
    if '--download_all' in sys.argv:
        require_user_name  = True
    
    if '--extract_and_propagate_all' in sys.argv:
        require_project    = True
    
    if '--download_and_propagate_all' in sys.argv:
        require_project    = True
        require_user_name  = True
    
    if '--download_and_propagate_mr' in sys.argv:
        require_project    = True
        require_user_name  = True
    
    if '--download_mr' in sys.argv:
        require_user_name  = True
    
    if '--extract_and_propagate_mr' in sys.argv:
        require_project    = True
    
    if '--download_fs' in sys.argv:
        require_user_name  = True
    
    if '--extract_fs' in sys.argv:
        require_project    = True


    if '--project_alias_data_column' in sys.argv and '--global_project_alias' in sys.argv:
        print('You cannot specify both a global propagation alias and a project alias propagation data column.')
        print('Specify one or the other.')
        print()
        parser.print_help()
        sys.exit(1)
    
    #General Settings
    settings = parser.add_argument_group('Settings')
    
    settings.add_argument('--user_name',
                        required = require_user_name,
                        help = 'The user that is logging in to the xnat server.',
                        type = str)     
    

    settings.add_argument('--subject_id_data_column',
                        required = False,
                        help = 'Specify the data column to read subject ids from in the target_csv_file.',
                        default = 'participant_id',
                        type = str) 
    
    settings.add_argument('--subject_accession_data_column',
                        required = False,
                        help = 'Specify the data column to read subject ids from in the target_csv_file.',
                        default = 'subject_accession',
                        type = str) 
    
    settings.add_argument('--session_id_data_column',
                        required = False,
                        help = 'Specify the data column to read session ids from in the target_csv_file.',
                        default = 'session_id',
                        type = str)
    
    settings.add_argument('--session_accession_data_column',
                        required = False,
                        help = 'Specify the data column to read session accession numbers from in the target_csv_file.',
                        default = 'Session_Accession',
                        type = str)     
    
    settings.add_argument('--fs_accession_data_column',
                        required = False,
                        help = 'Specify the data column to read fs accession ids from in the target_csv_file.',
                        default = 'fs_accession',
                        type = str) 
    
    settings.add_argument('--scan_source_data_column',
                        required = False,
                        help = 'Specify the data column to read scan source extraction locations from in the target_csv_file.',
                        default = Definitions.SCAN_SOURCE,
                        type = str)
    
    settings.add_argument('--project_alias_data_column',
                        required = require_project_alias_data_column,
                        help = 'Specify the data column to read what project to propagate into in the target_csv_file.',
                        default = 'project_alias',
                        type = str)
    
    settings.add_argument('--alias_in_csv',
                        required = False,
                        help = 'Look at data_file for execution arguments.',
                        action = 'store_true')
    
    settings.add_argument('--global_project_alias',
                        required = require_global_project_alias,
                        help = 'Specify the project of interest.',
                        type = str,
                        default = None)
    
    settings.add_argument('--project',
                        required = require_project,
                        help = 'Specify the project of interest.',
                        type = str)
    
    settings.add_argument('--download_chunk_size',
                        required = False,
                        help = 'Specify the chunk size to download data.',
                        default = 8192,
                        type = int)     
    
    settings.add_argument('--log_file',
                        required = False,
                        help = 'Specify a log file to log propagation information to.',
                        type = str)
    
    settings.add_argument('--no_clean_up',
                         required = False,
                         help = f'Dont remove successful propagations out of the download cache.',
                         action='store_true')
    

    args = parser.parse_args() 
    
    #Process the paths.
    target_csv_file = Checks.expand_data_path(args.target_csv_file, args.execution_path)

    log_file = None
    if args.log_file:
        log_file = Checks.expand_data_path(args.log_file, args.execution_path)
    
    target_download_path = None
    if args.target_download_path:
        target_download_path = Checks.expand_data_path(args.target_download_path, args.execution_path)
    
    clean_up = not args.no_clean_up
    
    with  DownloadManager.DownloadManager(database_name = args.entry_point,
                                          server = args.server, 
                                          download_csv = target_csv_file,
                                          download_chunk_size = args.download_chunk_size,
                                          download_dir = target_download_path,
                                          log_file = log_file) as downloader:

        

        if args.download_all:
            downloader.login(args.user_name)
            downloader.download_all_data(
                    args.session_accession_data_column,
                    args.fs_accession_data_column
            )
            downloader.logout()

        if args.extract_and_propagate_all:
            alias = args.project_alias_data_column if args.alias_in_csv else args.global_project_alias
            downloader.extract_and_propagate_all(
                args.project,
                args.subject_id_data_column,
                args.subject_accession_data_column,
                args.session_id_data_column,
                args.session_accession_data_column,
                args.fs_accession_data_column,
                alias,
                args.alias_in_csv,
                args.scan_source_data_column,
                clean_up
            )
        
        if args.download_and_propagate_all:
            downloader.login(args.user_name)
            downloader.download_all_data(
                    args.session_accession_data_column,
                    args.fs_accession_data_column
            )
            downloader.logout()
            alias = args.project_alias_data_column if args.alias_in_csv else args.global_project_alias
            downloader.extract_and_propagate_all(
                args.project,
                args.subject_id_data_column,
                args.subject_accession_data_column,
                args.session_id_data_column,
                args.session_accession_data_column,
                args.fs_accession_data_column,
                alias,
                args.alias_in_csv,
                args.scan_source_data_column,
                clean_up
            )
        
        if args.download_and_propagate_mr:
            downloader.login(args.user_name)
            downloader.download_mr(
                    args.session_accession_data_column,
            )
            downloader.logout()
            alias = args.project_alias_data_column if args.alias_in_csv else args.global_project_alias
            downloader.extract_and_propagate_mr(
                args.project,
                args.subject_id_data_column,
                args.subject_accession_data_column,
                args.session_id_data_column,
                args.session_accession_data_column,
                alias,
                args.alias_in_csv,
                args.scan_source_data_column,
                clean_up
            )
        
        if args.download_mr:
            downloader.login(args.user_name)
            downloader.download_mr(
                    args.session_accession_data_column
            )
            downloader.logout()
        
        if args.extract_and_propagate_mr:
            alias = args.project_alias_data_column if args.alias_in_csv else args.global_project_alias
            downloader.extract_and_propagate_mr(
                args.project,
                args.subject_id_data_column,
                args.subject_accession_data_column,
                args.session_id_data_column,
                args.session_accession_data_column,
                alias,
                args.alias_in_csv,
                args.scan_source_data_column,
                clean_up
            )
        
        if args.download_and_propagate_mr:
            downloader.login(args.user_name)
            downloader.download_mr(
                    args.session_accession_data_column
            )
            downloader.logout()
            alias = args.project_alias_data_column if args.alias_in_csv else args.global_project_alias
            downloader.extract_and_propagate_mr(
                args.project,
                args.subject_id_data_column,
                args.subject_accession_data_column,
                args.session_id_data_column,
                args.session_accession_data_column,
                alias,
                args.alias_in_csv,
                args.scan_source_data_column,
                clean_up
            )
        
        if args.download_fs:
            downloader.login(args.user_name)
            downloader.download_fs(
                    args.fs_accession_data_column
            )
            downloader.logout()
        
        if args.extract_fs:
            alias = args.project_alias_data_column if args.alias_in_csv else args.global_project_alias
            downloader.extract_fs(
                args.project,
                args.subject_id_data_column,
                args.session_id_data_column,
                args.fs_accession_data_column,
                clean_up
            )
