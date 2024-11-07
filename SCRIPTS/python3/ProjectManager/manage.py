import src.ProjectManager as ProjectManager
import src.Utils.Checks as Checks
import src.DataModels.Definitions as Definitions
import argparse
import sys

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='A management System for the Ances MR Processing Pipeline. Provides functionality to manage data in the ProjectManager database.',
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

    #Now add the potential options that can be executed. 
    require_project           = False
    require_project_alias     = False
    require_map_ids           = False
    require_report_path       = False
    require_ses_id            = False
    require_proc_status       = False
    require_id_csv            = False
    require_id_col            = False
    default_fuzzy_match_level = 0
    
    update_and_build = parser.add_argument_group('Update operations')

    #Update Options
    update_and_build.add_argument('--update_subjects',
                        required = False,
                        help = 'Add or update a specfic subject in a given project.',
                        action='store_true')
    
    update_and_build.add_argument('--update_projects',
                        required = False,
                        help = 'Attempt to update all projects specified in the entrypoint.',
                        action='store_true')

    update_and_build.add_argument('--update_project',
                        required = False,
                        help = 'update a specific project individually.',
                        action='store_true')
    
    update_and_build.add_argument('--update_project_alias',
                        required = False,
                        help = 'update a specific project alias individually.',
                        action='store_true')
    
    update_and_build.add_argument('--update_accession_from_csv',
                        required = False,
                        help = 'update a specific project alias individually.',
                        action='store_true')

    if '--update_subject' in sys.argv:
        require_project = True
        require_map_ids = True

    if '--update_project' in sys.argv:
        require_project = True
    
    if '--update_project_alias' in sys.argv:
        require_project       = True
        require_project_alias = True
    
    if '--update_accession_from_csv' in sys.argv:
        require_project       = True
        require_id_csv        = True
        require_id_col        = True
    
    reports = parser.add_argument_group('Queries')
    #Report arguments.
    reports.add_argument('--generate_project_report',
                        required = False,
                        help = 'Generate a report detailing all information pertaining to a specific project in the DB.',
                        action = 'store_true')

    reports.add_argument('--generate_subject_report_by_participant_ids',
                        required = False,
                        help = 'Given the project and a list of map ids. Generate a report about all information pertaining to each subject in the DB.',
                        action = 'store_true')
    
    reports.add_argument('--generate_subject_report_by_sub_ses',
                        required = False,
                        help = 'Given the project, a map id. Generate a report about all information pertaining to that subject and session in the DB.',
                        action = 'store_true')
    
    reports.add_argument('--generate_project_duplicate_sessions_report',
                        required = False,
                        help = 'Generate a report detailing all duplicate sessions pertaining to a specific project in the DB.',
                        action = 'store_true')
    
    reports.add_argument('--generate_all_duplicate_sessions_report',
                        required = False,
                        help = 'Generate a report detailing all possibile duplicate sessions in the DB.',
                        action = 'store_true')
    
    reports.add_argument('--generate_project_report_by_processing_status',
                        required = False,
                        help = 'Generate a report detailing all subjects which match the given processing status in a project.',
                        action = 'store_true')
    
    reports.add_argument('--generate_report_by_processing_status',
                        required = False,
                        help = 'Generate a report detailing all subjects which match the given processing status in all projects.',
                        action = 'store_true')
    
    reports.add_argument('--generate_session_link_report',
                        required = False,
                        help = 'Generate a report detailing all scan sources and their links in a project.',
                        action = 'store_true')

    #Now set the required arguments based on what was specified.
    if '--generate_project_report' in sys.argv:
        require_project     = True
        require_report_path = True

    if '--generate_subject_report_by_participant_ids' in sys.argv:
        require_project     = True
        require_map_ids     = True
        require_report_path = True

    if '--generate_subject_report_by_sub_ses' in sys.argv:
        require_project     = True
        require_map_ids     = True
        require_ses_id      = True
        require_report_path = True

    if '--generate_project_duplicate_sessions_report' in sys.argv:
        require_project     = True
        require_report_path = True
        default_fuzzy_match_level = 1
    
    if '--generate_all_duplicate_sessions_report' in sys.argv:
        require_report_path = True
        default_fuzzy_match_level = 1

    if '--generate_project_report_by_processing_status' in sys.argv:
        require_project     = True
        require_report_path = True
        require_proc_status = True 
    
    if '--generate_report_by_processing_status' in sys.argv:
        require_report_path = True
        require_proc_status = True 

    if '--generate_session_link_report' in sys.argv:
        require_report_path = True
        require_project     = True

    accession_ids = parser.add_argument_group('CNDA ID mapping settings and options')
        
    accession_ids.add_argument('--id_csv',
                               required = require_id_csv,
                               help = 'The csv file which associates CNDA accession ids to server ids.',
                               type = str)
    
    accession_ids.add_argument('--id_col',
                               required = False,
                               help = 'The column which stores subject IDs.',
                               type = str,
                               default = Definitions.MAP_ID)

    accession_ids.add_argument('--id_accession_col',
                               required = False,
                               help = 'The column which stores subject accession IDs.',
                               type = str,
                               default = Definitions.SUBJECT_ACCESSION)
    
    accession_ids.add_argument('--session_col',
                               required = False,
                               help = 'The column which stores session IDs.',
                               type = str,
                               default = Definitions.SESSION_ID)
    
    accession_ids.add_argument('--session_accession_col',
                               required = False,
                               help = 'The column which stores session accession IDs.',
                               type = str,
                               default = Definitions.SESSION_ACCESSION)
    
    accession_ids.add_argument('--fs_accession_col',
                               required = False,
                               help = 'The column which stores fs accession IDs.',
                               type = str,
                               default = Definitions.FS_ACCESSION)
    
    #General Settings
    settings = parser.add_argument_group('Settings')
    settings.add_argument('--project',
                        required = require_project,
                        help = 'Specify the project of interest.',
                        type = str)

    settings.add_argument('--project_alias',
                        required = require_project_alias,
                        help = 'Specify the project alias of interest.',
                        type = str)
    
    settings.add_argument('--participant_id',
                        required = require_map_ids,
                        help = 'Specify the map ID(s) of interest.',
                        type = str,
                        nargs = (1 if require_ses_id else '+')) #If a session id is specified then we only want 1 map id otherwise it can be a list of ids.
    
    settings.add_argument('--session_id',
                        required = require_ses_id,
                        help = 'Specify the session ID of interest.',
                        type = str)
    
    settings.add_argument('--report_path',
                        required = require_report_path,
                        help = 'Specify the path to generate reports to.',
                        type = str)
    
    settings.add_argument('--processing_status',
                        required = require_proc_status,
                        help = 'Specify the processing status to match (not case sensitive, enclose strings with a space with "".',
                        type = str)
    
    settings.add_argument('--fill_missing_info',
                        required = False,
                        help = 'If any data cannot be automatically detected, fill it in manually.',
                        action = 'store_true',
                        default = False)
    
    settings.add_argument('--separate_subjects',
                        required = False,
                        help = 'Seperate subjects by an empty row in generated reports.',
                        action = 'store_true',
                        default = False)

    settings.add_argument('--force_merge',
                        required = False,
                        help = 'If any data inconsistancy issues are found that cannot be automatically resolved, force them to be updated.',
                        action = 'store_true',
                        default = False)

    settings.add_argument('--fuzzy_match_level',
                        required = False,
                        help = 'Specify how closely session ids are required to match in order to fuzzy match.',
                        type = int,
                        default = default_fuzzy_match_level)
    
    settings.add_argument('--deep_search',
                        required = False,
                        help = 'Default behavior is to stop searching deeper directories when a session folder is found. This option will recursively search everywhere.',
                        action = 'store_true')
    
    extension = parser.add_argument_group('Extended Report Options.')
    
    extension.add_argument('--extend_report',
                        required = False,
                        help = 'Include a list of all nifti files found for each session. Requires a search of every subject included in the report.',
                        action = 'store_true')
    
    args = parser.parse_args() 

    #Create the ProjectManager instance.
    project_manager = ProjectManager.ProjectManager(args.entry_point,
                                                    args.deep_search,
                                                    args.extend_report)

    report_path = ''
    if require_report_path:
        report_path = Checks.expand_data_path(args.report_path, args.execution_path)

    accession_csv_path = ''
    if '--id_csv' in sys.argv:
        accession_csv_path = Checks.expand_data_path(args.id_csv, args.execution_path)

    #Perform update operations.
    if args.update_subjects:
        project_manager.update_subjects(
            args.project,
            args.participant_id,
            args.fill_missing_info,
            args.force_merge
        )

    if args.update_projects:
        project_manager.update_all_projects(
            args.fill_missing_info,
            args.force_merge
        )

    if args.update_project:
        project_manager.update_project(
            args.project,
            args.fill_missing_info,
            args.force_merge
        )

    if args.update_project_alias:
        project_manager.update_project_alias(
            args.project,
            args.project_alias,
            args.fill_missing_info,
            args.force_merge
        )
    
    #Perform report options.
    if args.generate_project_report:
        project_manager.get_project_wide_report(
            args.project,
            report_path,
            args.separate_subjects
        )

    if args.generate_subject_report_by_participant_ids:
        project_manager.get_subject_report_by_map_ids(
            args.project,
            args.participant_id,
            report_path,
            args.separate_subjects
        )
    
    if args.generate_subject_report_by_sub_ses:
        project_manager.get_subject_report_by_sub_ses(
            args.project,
            args.participant_id[0], 
            args.session_id,
            report_path,
            args.fuzzy_match_level
        )
    
    if args.generate_project_duplicate_sessions_report:
        project_manager.get_duplicate_sessions_report_by_project(
            args.project,
            report_path,
            args.separate_subjects
        )
    
    if args.generate_all_duplicate_sessions_report:
        project_manager.get_all_duplicate_sessions_report(
            report_path,
            args.separate_subjects
        )
    
    if args.generate_project_report_by_processing_status:
        project_manager.get_project_report_by_processing_status(
            args.project,
            args.processing_status,
            report_path,
            args.separate_subjects
        )
    
    if args.generate_report_by_processing_status:
        project_manager.get_all_processing_status_report(
            args.processing_status,
            report_path,
            args.separate_subjects
        )

    if args.generate_session_link_report:
        project_manager.get_session_link_mapping(
            args.project,
            report_path
        )

    if args.update_accession_from_csv:
        project_manager.update_accession_values_from_csv(
            args.project,
            accession_csv_path,
            args.id_col,
            args.id_accession_col,
            args.session_col,
            args.session_accession_col,
            args.fs_accession_col,
            args.force_merge)

