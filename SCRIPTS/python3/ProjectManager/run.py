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
    parser.add_argument('--execution_path',
                        required = False,
                        help = argparse.SUPPRESS,
                        type = str,
                        default = '')     

    parser.add_argument('--num_cores',
                        required = False,
                        help = 'The amount of cores to use for processing.',
                        default = 1,
                        type=int)
    
    parser.add_argument('--log_file',
                        required = False,
                        help = 'Specify the log file to write processing information to.',
                        default = 'run.log',
                        type = str)     

    require_command    = False
    require_data_file  = False

    pp_scripts_path = os.path.expandvars('$PP_SCRIPTS')
    
    procs = parser.add_argument_group('Processing operations')
    #Processing Options
    procs.add_argument('--run_processing_command',
                        required = False,
                        help = f'Runs a script specified in $PP_SCRIPTS ({pp_scripts_path})',
                        action = 'store_true')

    procs.add_argument('--run_in_data_paths',
                        required = False,
                        help='Run the current command at the location of every specified data path',
                        action = 'store_true')

    procs.add_argument('--run_in_processing_dir',
                       required = False,
                       help = f'Run the current command at the location specied in the processing dir for this path. For instance the path /A/B/C/sub-aaaa_ses-bbbbb would execute in the directory /A/B/C/.',
                       action = 'store_true'
                       )

    
    procs.add_argument('--list_valid_commands',
                        required = False,
                        help = 'Lists commands that can be executed.',
                        action = 'store_true')
    
    placeholders = parser.add_argument_group('placeholder arguments', description = 'The arguments here perform an action and replace the result of that action in place of the argument.')

    placeholder_argument_mapping = {
        '--find_params'  : f'@{chr(pm.ProcessingState.FIND_PARAMS)}@',
        '--use_basename' : f'@{chr(pm.ProcessingState.PATH_ARG)}@'
    }

    placeholder_help_messages = ('Will replace this argument with the ".params" file found at the execution path for this commnad.',
                                 'Use the specified data path as a parameter for the execution command.')
    

    for arg, desc in zip(placeholder_argument_mapping.keys() ,placeholder_help_messages):
        placeholders.add_argument(arg,
                                required = False,
                                help = desc,
                                action = 'store_true')


    
    if '--run_processing_command' in sys.argv:
        require_command = True

    if '--args_in_csv' in sys.argv:
        require_data_file = True

    if '--execution_arguments_column' in sys.argv:
        require_data_file = True

    #General Settings
    settings = parser.add_argument_group('settings')
    
    settings.add_argument('--command',
                        required = require_command,
                        help = 'Specify what processing command to run',
                        type = str,
                        default = None)     

    settings.add_argument('--data_paths',
                        required = False,
                        help = 'specify data paths of interest.',
                        type = str,
                        nargs = '+',
                        default = None)     
    
    settings.add_argument('--data_file',
                        required = require_data_file,
                        help = 'Specify a csv file which contains the data paths of interest.',
                        type = str,
                        default = None)     
    
    settings.add_argument('--data_path_column',
                        required = False,
                        help = 'Specify the data column to extract data paths from.',
                        default = Definitions.DATA_PATH,
                        type = str) 
    
    settings.add_argument('--args_in_csv',
                        required = False,
                        help = 'Look at data_file for execution arguments.',
                        action = 'store_true')

    settings.add_argument('--exec_arguments_column',
                        required = False,
                        help = 'Specify the data column which contains specific command execution arguments.',
                        default = Definitions.EXEC_ARGS,
                        type = str) 
    

    

    args, unknown = parser.parse_known_args() 

    os.chdir(args.execution_path)

    #Set the data path based on whichever was specified.
    log_file = Checks.expand_data_path(args.log_file, args.execution_path)
    
    #Compile all the unspecified commands together with positional arguments to get all the arguments
    #to pass through with the script. Collect the recognized arguments in order.
    pass_through = []
    all_passthrough_arguments = unknown + list(placeholder_argument_mapping.keys())
    for arg in sys.argv:
        if arg in all_passthrough_arguments:
            pass_through.append(placeholder_argument_mapping[arg] if arg in placeholder_argument_mapping else arg)

    
    #Create the ProcessManager instance.
    process_manager = pm.ProcessManager(log_file, 
                                        args.num_cores,
                                        placeholder_argument_mapping)

    #Check that if a command is specified that it is valid.
    if args.command and not args.command in process_manager.executables:
        print(f'The command {Definitions.COLORS["RED"]}{args.command}{Definitions.COLORS["RESET"]} is not a valid executable found in PP_SCRIPTS.')
        process_manager.list_executables()
        print('Run again with a valid command.')
        sys.exit(1)

    if args.list_valid_commands:
        process_manager.list_executables()

    #Set the processing state so the process manager knows what its doing.
    state = pm.ProcessingState.REGULAR
    for flag in placeholder_argument_mapping:
        if flag in sys.argv:
            state |= ord(placeholder_argument_mapping[flag][1])
    
    process_manager.add_execution_state(state)
    if args.run_in_data_paths:
        process_manager.add_execution_state(pm.ProcessingState.SWITCH_PATH)
    if args.run_in_processing_dir:
        process_manager.add_execution_state(pm.ProcessingState.SWITCH_TO_INPROCESS)

    if args.run_processing_command:
        data_source = None

        if args.data_file:
            data_source = Checks.expand_data_path(args.data_file, args.execution_path)
       
        if args.data_paths:
            data_source = [ Checks.expand_data_path(path, args.execution_path) for path in args.data_paths ]

        

        #If the args are explicitly in the csv, then switch the pass_through data to be the name of the
        #csv we want to extract the args from. If they specified additionally in the command line. Pass 
        #those through. Finally if no args are specified then we done want to pass anything through (None).
        if args.args_in_csv:
            pass_through = data_source

        if pass_through == []:
            pass_through = None


        process_manager.execute_command(args.command,
                                        data_source,
                                        args.data_path_column,
                                        pass_through,
                                        args.exec_arguments_column)

