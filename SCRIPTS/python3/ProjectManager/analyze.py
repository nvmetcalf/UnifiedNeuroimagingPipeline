import src.DataModels.Arguments as ARGS

import argparse
import sys
import src.BOLDAnalysisManager as BAM
import src.Utils.Checks as Checks

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description = ('A management System for the Ances MR Processing Pipeline. Provides functionality for analysis '
                       'and post processing.'),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

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
        required = False,
        help     = ARGS.ARGS['COMMON']['LOG']['DESC'],
        type     = str,
        default  = ARGS.ARGS['COMMON']['LOG']['DEFAULT'])
    
    parser.add_argument(
        ARGS.ARGS['COMMON']['PROJECT']['NAME'],
        help     = ARGS.ARGS['COMMON']['PROJECT']['DESC'],
        type     = str) 
    
    require_seed_corr_output = False
    require_sub_ses_strings  = False

    bold_sync_actions = parser.add_argument_group('BOLD Analysis operations')
    bold_sync_actions.add_argument(
        ARGS.ARGS['ANALYZE']['RUN_BOLD_SMOOTHING']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['RUN_BOLD_SMOOTHING']['DESC'],
        action='store_true')

    bold_sync_actions.add_argument(
        ARGS.ARGS['ANALYZE']['RUN_BOLD_SEED_CORR']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['RUN_BOLD_SEED_CORR']['DESC'],
        action='store_true')
    
    bold_sync_actions.add_argument(
        ARGS.ARGS['ANALYZE']['RUN_BOLD_POST_PROC']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['RUN_BOLD_POST_PROC']['DESC'],
        action='store_true')
    
    bold_sync_actions.add_argument(
        ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_SMOOTHING']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_SMOOTHING']['DESC'],
        action='store_true')

    bold_sync_actions.add_argument(
        ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_SEED_CORR']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_SEED_CORR']['DESC'],
        action='store_true')
    
    bold_sync_actions.add_argument(
        ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_POST_PROC']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_POST_PROC']['DESC'],
        action='store_true')

    if ARGS.ARGS['ANALYZE']['RUN_BOLD_SEED_CORR']['NAME'] in sys.argv:
        require_seed_corr_output = True
    
    if ARGS.ARGS['ANALYZE']['RUN_BOLD_POST_PROC']['NAME'] in sys.argv:
        require_seed_corr_output = True
    
    if ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_SEED_CORR']['NAME'] in sys.argv:
        require_seed_corr_output = True
        require_sub_ses_strings  = True
    
    if ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_POST_PROC']['NAME'] in sys.argv:
        require_seed_corr_output = True
        require_sub_ses_strings  = True
    
    bold_reports = parser.add_argument_group('BOLD Queries')
    
    bold_reports.add_argument(
        ARGS.ARGS['ANALYZE']['EXTRACT_BOLD_QC']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['EXTRACT_BOLD_QC']['DESC'],
        action='store_true')
    
    bold_reports.add_argument(
        ARGS.ARGS['ANALYZE']['EXTRACT_BOLD_NETWORK_MEANS']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['EXTRACT_BOLD_NETWORK_MEANS']['DESC'],
        action='store_true')
    
    bold_reports.add_argument(
        ARGS.ARGS['ANALYZE']['CLEAN']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['CLEAN']['DESC'],
        action='store_true')

    #General Settings
    settings = parser.add_argument_group('Settings')
    
    settings.add_argument(
        ARGS.ARGS['ANALYZE']['SEED_CORR_OUTPUT_PATH']['NAME'],
        required=require_seed_corr_output,
        help=ARGS.ARGS['ANALYZE']['SEED_CORR_OUTPUT_PATH']['DESC'],
        type=str)
    
    settings.add_argument(
        ARGS.ARGS['COMMON']['SUB_SES_STRINGS']['NAME'],
        required=require_sub_ses_strings,
        help=ARGS.ARGS['COMMON']['SUB_SES_STRINGS']['DESC'],
        type=str,
        default = [],
        nargs='+')
    
    settings.add_argument(
        ARGS.ARGS['ANALYZE']['SMOOTHING_VALUE']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['SMOOTHING_VALUE']['DESC'],
        type=float,
        default=ARGS.ARGS['ANALYZE']['SMOOTHING_VALUE']['DEFAULT'])
    
    settings.add_argument(
        ARGS.ARGS['ANALYZE']['EXCLUDE_NETWORKS']['NAME'],
        required=False,
        help=ARGS.ARGS['ANALYZE']['EXCLUDE_NETWORKS']['DESC'],
        type=str,
        default=ARGS.ARGS['ANALYZE']['EXCLUDE_NETWORKS']['DEFAULT'],
        nargs='+')

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

    args = parser.parse_args() 
    
    log_file = ''
    if getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['LOG']['NAME'])) != '':
        log_file = Checks.expand_data_path(args.log_file, args.execution_path)
    
    with BAM.BOLDAnalysis(
        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['PROJECT']['NAME'])), 
        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['ENTRY_POINT']['NAME'])), 
        getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['EXCLUDE_NETWORKS']['NAME'])),
        log_file
    ) as analysis_manager:
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['EXTRACT_BOLD_QC']['NAME'])):
            analysis_manager.extract_QC_metrics()
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['EXTRACT_BOLD_NETWORK_MEANS']['NAME'])):
            analysis_manager.extract_BOLD_network_means()
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['CLEAN']['NAME'])):
            analysis_manager.clear_BOLD_analysis()
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['RUN_BOLD_SMOOTHING']['NAME'])):
            analysis_manager.run_project_smoothing(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['SMOOTHING_VALUE']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME'])),
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['RUN_BOLD_SEED_CORR']['NAME'])):
            analysis_manager.run_project_seed_corr(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['SEED_CORR_OUTPUT_PATH']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME'])),
            )

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['RUN_BOLD_POST_PROC']['NAME'])):
            analysis_manager.run_project_BOLD_post_proc(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['SMOOTHING_VALUE']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['SEED_CORR_OUTPUT_PATH']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME'])),
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_SMOOTHING']['NAME'])):
            analysis_manager.run_session_smoothing(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUB_SES_STRINGS']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['SMOOTHING_VALUE']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME'])),
            )
        
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_SEED_CORR']['NAME'])):
            analysis_manager.run_session_seed_corr(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUB_SES_STRINGS']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['SEED_CORR_OUTPUT_PATH']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME']))
            )

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['RUN_SESSION_BOLD_POST_PROC']['NAME'])):
            analysis_manager.run_session_BOLD_post_proc(
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['SUB_SES_STRINGS']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['SMOOTHING_VALUE']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['ANALYZE']['SEED_CORR_OUTPUT_PATH']['NAME'])),
                getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['FORCE']['NAME']))
            )
