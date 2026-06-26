import src.DataModels.Arguments as ARGS

import src.ProcessManager as pm
import src.DataModels.Definitions as Definitions
import src.Utils.Checks as Checks
import argparse
import sys
import os

if __name__ == '__main__':

    parser = argparse.ArgumentParser(description='A management System for the Ances MR Processing Pipeline. Provides functionality for parallel processing. All additional arguments that are not specified here will be passed into any processing command specified.',
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    
    #This is a hidden argument which is used by project manager to get relative paths to work.
    # Common Arguments
    parser.add_argument(
        ARGS.ARGS['COMMON']['EXEC_PATH']['NAME'],
        required=False,
        help=argparse.SUPPRESS,
        type=str,
        default=ARGS.ARGS['COMMON']['EXEC_PATH']['DEFAULT'])

    parser.add_argument(
        ARGS.ARGS['COMMON']['LOG']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['LOG']['DESC'],
        type=str,
        default=ARGS.ARGS['COMMON']['LOG']['DEFAULT'])

    # RUN Specific Arguments
    parser.add_argument(
        ARGS.ARGS['RUN']['NUM_CORES']['NAME'],
        required=False,
        help=ARGS.ARGS['RUN']['NUM_CORES']['DESC'],
        default=ARGS.ARGS['RUN']['NUM_CORES']['DEFAULT'],
        type=int)

    
    procs = parser.add_argument_group('Processing operations')
    #Processing Options
    procs.add_argument(
        ARGS.ARGS['RUN']['RUN_PROCESSING_COMMAND']['NAME'],
        required=False,
        help=ARGS.ARGS['RUN']['RUN_PROCESSING_COMMAND']['DESC'],
        type=str)

    procs.add_argument(
        ARGS.ARGS['RUN']['RUN_IN_DATA_PATHS']['NAME'],
        required=False,
        help=ARGS.ARGS['RUN']['RUN_IN_DATA_PATHS']['DESC'],
        action='store_true')

    procs.add_argument(
        ARGS.ARGS['RUN']['RUN_IN_PROCESSING_DIR']['NAME'],
        required=False,
        help=ARGS.ARGS['RUN']['RUN_IN_PROCESSING_DIR']['DESC'],
        action='store_true')

    procs.add_argument(
        ARGS.ARGS['RUN']['LIST_VALID_COMMANDS']['NAME'],
        required=False,
        help=ARGS.ARGS['RUN']['LIST_VALID_COMMANDS']['DESC'],
        action='store_true')
    
    placeholders = parser.add_argument_group('placeholder arguments', description = 'The arguments here perform an action and replace the result of that action in place of the argument.')

    placeholder_argument_mapping = {
        ARGS.ARGS['RUN']['FIND_SUB']['NAME']: f'@{chr(pm.ProcessingState.FIND_SUB)}@',
        ARGS.ARGS['RUN']['FIND_SES']['NAME']: f'@{chr(pm.ProcessingState.FIND_SES)}@',
        ARGS.ARGS['RUN']['FIND_ALIAS']['NAME']: f'@{chr(pm.ProcessingState.FIND_ALIAS)}@',
        ARGS.ARGS['RUN']['FIND_PARAMS']['NAME']: f'@{chr(pm.ProcessingState.FIND_PARAMS)}@',
        ARGS.ARGS['RUN']['USE_BASENAME']['NAME']: f'@{chr(pm.ProcessingState.PATH_ARG)}@'
    }

    placeholder_help_messages = [
        ARGS.ARGS['RUN']['FIND_SUB']['DESC'],
        ARGS.ARGS['RUN']['FIND_SES']['DESC'],
        ARGS.ARGS['RUN']['FIND_ALIAS']['DESC'],
        ARGS.ARGS['RUN']['FIND_PARAMS']['DESC'],
        ARGS.ARGS['RUN']['USE_BASENAME']['DESC']
    ]

    for arg, desc in zip(placeholder_argument_mapping.keys() ,placeholder_help_messages):
        placeholders.add_argument(arg,
                                required = False,
                                help = desc,
                                action = 'store_true')

    pp_scripts_path = os.path.expandvars('$PP_SCRIPTS')
    require_data_file  = False

    if ARGS.ARGS['RUN']['ARGS_IN_CSV']['NAME'] in sys.argv:
        require_data_file = True

    if ARGS.ARGS['COMMON']['EXEC_ARGS']['NAME'] in sys.argv:
        require_data_file = True
    
    if ARGS.ARGS['COMMON']['EXEC_STATUS']['NAME'] in sys.argv:
        require_data_file = True

    #General Settings
    settings = parser.add_argument_group('settings')

    settings.add_argument(
        ARGS.ARGS['COMMON']['DATA_PATH']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['DATA_PATH']['DESC'],
        type=str,
        nargs='+',
        default=None)

    settings.add_argument(
        ARGS.ARGS['COMMON']['DATA_FILE']['NAME'],
        required=require_data_file,
        help=ARGS.ARGS['COMMON']['DATA_FILE']['DESC'],
        type=str)    

    settings.add_argument(
        ARGS.ARGS['RUN']['ARGS_IN_CSV']['NAME'],
        required=False,
        help=ARGS.ARGS['RUN']['ARGS_IN_CSV']['DESC'],
        action='store_true')
    
    settings.add_argument(
        ARGS.ARGS['RUN']['DATA_PATH_COL']['NAME'],
        required=False,
        help=ARGS.ARGS['RUN']['DATA_PATH_COL']['DESC'],
        type=str,
        default=ARGS.ARGS['RUN']['DATA_PATH_COL']['DEFAULT'])    

    settings.add_argument(
        ARGS.ARGS['COMMON']['EXEC_ARGS']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['EXEC_ARGS']['DESC'],
        default=ARGS.ARGS['COMMON']['EXEC_ARGS']['DEFAULT'],
        type=str)

    settings.add_argument(
        ARGS.ARGS['COMMON']['EXEC_STATUS']['NAME'],
        required=False,
        help=ARGS.ARGS['COMMON']['EXEC_STATUS']['DESC'],
        default=ARGS.ARGS['COMMON']['EXEC_STATUS']['DEFAULT'],
        type=str)

    settings.add_argument(
        ARGS.ARGS['RUN']['EXEC_ON_MATCH']['NAME'],
        help=ARGS.ARGS['RUN']['EXEC_ON_MATCH']['DESC'],
        type=str,
        default=None)

    args, unknown = parser.parse_known_args() 
    os.chdir(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME'])))
    log_file = Checks.expand_data_path(getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['LOG']['NAME'])), 
                                       getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_PATH']['NAME'])))

    
    #Compile all the unspecified commands together with positional arguments to get all the arguments
    #to pass through with the script. Collect the recognized arguments in order.
    pass_through = []
    all_passthrough_arguments = unknown + list(placeholder_argument_mapping.keys())
    for arg in sys.argv:
        if arg in all_passthrough_arguments:
            pass_through.append(placeholder_argument_mapping[arg] if arg in placeholder_argument_mapping else arg)

    
    #Create the ProcessManager instance.
    process_manager = pm.ProcessManager(log_file, 
                                        getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['NUM_CORES']['NAME'])),
                                        placeholder_argument_mapping)

    #Check that if a command is specified that it is valid.
    processing_command = getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['RUN_PROCESSING_COMMAND']['NAME']))
    if (processing_command and not processing_command in process_manager.executables):
        print(f'The command {Definitions.COLORS["RED"]}{args.command}{Definitions.COLORS["RESET"]} is not a valid executable found in PP_SCRIPTS.')
        process_manager.list_executables()
        print('Run again with a valid command.')
        sys.exit(1)

    if getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['LIST_VALID_COMMANDS']['NAME'])):
        process_manager.list_executables()

    #Set the processing state so the process manager knows what its doing.
    state = pm.ProcessingState.REGULAR
    for flag in placeholder_argument_mapping:
        if flag in sys.argv:
            state |= ord(placeholder_argument_mapping[flag][1])
    process_manager.add_execution_state(state)

    if getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['RUN_IN_DATA_PATHS']['NAME'])):
        process_manager.add_execution_state(pm.ProcessingState.SWITCH_PATH)

    if getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['RUN_IN_PROCESSING_DIR']['NAME'])):
        process_manager.add_execution_state(pm.ProcessingState.SWITCH_TO_INPROCESS)

    if getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['RUN_PROCESSING_COMMAND']['NAME'])):
        data_source = None

        if getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['DATA_FILE']['NAME'])):
            data_source = Checks.expand_data_path(args.data_file, args.execution_path)
       
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['DATA_PATH']['NAME'])):
            data_source = [ Checks.expand_data_path(path, args.execution_path) for path in args.data_paths ]

        #If the args are explicitly in the csv, then switch the pass_through data to be the name of the
        #csv we want to extract the args from. If they specified additionally in the command line. Pass 
        #those through. Finally if no args are specified then we done want to pass anything through (None).
        if getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['ARGS_IN_CSV']['NAME'])):
            pass_through = data_source

        if pass_through == []:
            pass_through = None

        process_manager.execute_command(getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['RUN_PROCESSING_COMMAND']['NAME'])),
                                        data_source,
                                        getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['DATA_PATH_COL']['NAME'])),
                                        pass_through,
                                        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_ARGS']['NAME'])),
                                        getattr(args, ARGS.strip_flag(ARGS.ARGS['COMMON']['EXEC_STATUS']['NAME'])),
                                        getattr(args, ARGS.strip_flag(ARGS.ARGS['RUN']['EXEC_ON_MATCH']['NAME'])))
