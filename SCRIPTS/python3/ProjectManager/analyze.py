import argparse
import sys
import src.AnalysisManager as AM
import src.Utils.Checks as Checks

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='A management System for the Ances MR Processing Pipeline. Provides functionality for analysis and post processing.',
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
    
    require_project          = False
    require_report_path      = False
    require_map_ids          = False
    require_ses_id           = False
    require_seed_corr_output = False
    

    sync_actions = parser.add_argument_group('Analysis operations')
    sync_actions.add_argument('--run_session_smoothing',
                              required = False,
                              action = 'store_true',
                              help = 'Run gaussian smoothing on BOLD volumes. This runs smoothing for a single subject/session pair.')
    
    sync_actions.add_argument('--run_subjects_smoothing',
                              required = False,
                              action = 'store_true',
                              help = 'Run gaussian smoothing on BOLD volumes. This runs smoothing for a list of subjects.')

    sync_actions.add_argument('--run_project_smoothing',
                              required = False,
                              action = 'store_true',
                              help = 'Run gaussian smoothing on all completed BOLD volumes in a project.')

    sync_actions.add_argument('--run_session_seed_corr',
                              required = False,
                              action = 'store_true',
                              help = 'Run volume seed correlation. This runs smoothing for a single subject/session pair.')
    
    sync_actions.add_argument('--run_subjects_seed_corr',
                              required = False,
                              action = 'store_true',
                              help = 'Run volume seed correlation. This runs smoothing for a list of subjects.')

    sync_actions.add_argument('--run_project_seed_corr',
                              required = False,
                              action = 'store_true',
                              help = 'Run volume seed correlation on all completed BOLD volumes in a project.')
    
    sync_actions.add_argument('--run_project_BOLD_post_proc',
                              required = False,
                              action = 'store_true',
                              help = 'Run smoothing and volume seed correlation on all completed BOLD volumes in a project.')

    if '--run_session_smoothing' in sys.argv:
        require_project     = True
        require_map_ids     = True
        require_ses_id      = True
    
    if '--run_subjects_smoothing' in sys.argv:
        require_project     = True
        require_map_ids     = True
    
    if '--run_project_smoothing' in sys.argv:
        require_project     = True

    if '--run_session_seed_corr' in sys.argv:
        require_project          = True
        require_map_ids          = True
        require_ses_id           = True
        require_seed_corr_output = True
    
    if '--run_subjects_seed_corr' in sys.argv:
        require_project          = True
        require_map_ids          = True
    
    if '--run_project_seed_corr' in sys.argv:
        require_project          = True
    
    if '--run_project_BOLD_post_proc' in sys.argv:
        require_project          = True
        require_seed_corr_output = True
    
    reports = parser.add_argument_group('Queries')
    reports.add_argument('--generate_subject_network_means_report',
                        required = False,
                        help = 'Generate a report detailing bold network average information pertaining to a specific subject in a project.',
                        action = 'store_true')
    
    reports.add_argument('--generate_project_network_means_report',
                        required = False,
                        help = 'Generate a report detailing bold network average information pertaining to a project.',
                        action = 'store_true')

    if '--generate_subject_network_means_report' in sys.argv:
        require_project     = True
        require_report_path = True
        require_map_ids     = True
    
    if '--generate_project_network_means_report' in sys.argv:
        require_project     = True
        require_report_path = True

    #General Settings
    settings = parser.add_argument_group('Settings')
    
    settings.add_argument('--project',
                        required = require_project,
                        help = 'Specify the project of interest.',
                        type = str)
    
    settings.add_argument('--report_path',
                        required = require_report_path,
                        help = 'Specify the path to generate reports to.',
                        type = str)
    
    settings.add_argument('--seed_corr_output_path',
                        required = require_seed_corr_output,
                        help = 'Specify the path to output seed correlation matrices to. This is a relative path within a given project alias Analysis folder.',
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
    
    settings.add_argument('--smoothing_value',
                        required = False,
                        help = 'Set the smoothing value to use.',
                        type = float,
                        default = 7.0)
    
    settings.add_argument('--exclude_networks',
                        required = False,
                        help = 'A list of networks to exclude when generating network means reports',
                        type = str,
                        default = [ 'Unassigned' ],
                        nargs = '+')
    
    settings.add_argument('--force',
                          required = False,
                          action = 'store_true',
                          help = 'Force an opperation even if existing data exists')

    args = parser.parse_args() 
    
    analysis_manager = AM.AnalysisManager(args.entry_point, args.exclude_networks)
    
    report_path = ''
    if require_report_path:
        report_path = Checks.expand_data_path(args.report_path, args.execution_path)

    if args.generate_subject_network_means_report:
        analysis_manager.get_subject_network_means_report(
            args.project,
            args.participant_id,
            report_path
        )
    
    if args.generate_project_network_means_report:
        analysis_manager.get_project_network_means_report(
            args.project,
            report_path
        )

    if args.run_session_smoothing:
        analysis_manager.run_session_smoothing(
            args.project,
            args.participant_id[0],
            args.session_id,
            args.smoothing_value,
            args.force
        )

    if args.run_subjects_smoothing:
        analysis_manager.run_subjects_smoothing(
            args.project,
            args.participant_id,
            args.smoothing_value,
            args.force
        )
    
    if args.run_project_smoothing:
        analysis_manager.run_project_smoothing(
            args.project,
            args.smoothing_value,
            args.force
        )
    
    if args.run_session_seed_corr:
        analysis_manager.run_session_seed_corr(
            args.project,
            args.participant_id[0],
            args.session_id,
            args.seed_corr_output_path,
            args.force
        )

    if args.run_subjects_seed_corr:
        analysis_manager.run_subjects_seed_corr(
            args.project,
            args.participant_id,
            args.seed_corr_output_path,
            args.force
        )
    
    if args.run_project_seed_corr:
        analysis_manager.run_project_seed_corr(
            args.project,
            args.seed_corr_output_path,
            args.force
        )

    if args.run_project_BOLD_post_proc:
        analysis_manager.run_project_BOLD_post_proc(
            args.project,
            args.smoothing_value,
            args.seed_corr_output_path,
            args.force
        )

