import src.ProcessManager as pm
import src.DataModels.Definitions as Definitions
import src.Utils.Checks as Checks
import argparse
import sys
import os

if __name__ == '__main__':

    parser = argparse.ArgumentParser(description='A managment System for the Ances MR Processing Pipeline. Provides functionality for parallel processing.',
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--execution_path',
                        required = False,
                        help = 'Specify the root directory where this script is being executed from. Used when executing this script outside of the source path.',
                        type = str,
                        default = '')     

    parser.add_argument('--num_cores',
                        required = False,
                        help = 'The amount of cores to use for processing.',
                        default = 1,
                        type=int)
    
    
    parser.add_argument('--log_file',
                        required = True,
                        help = 'Specify the log file to write processing information to.',
                        type = str)     

    require_data_paths = False
    require_data_file  = False
    
    procs = parser.add_argument_group('Processing operations')

    syntax_checker_path  = os.path.expandvars('$PP_SCRIPTS/CheckSyntax')
    p2_path              = os.path.expandvars('$PP_SCRIPTS/P2')
    generate_params_path = os.path.expandvars('$PP_SCRIPTS/GenerateParams')

    #Processing Options
    procs.add_argument('--run_generate_params',
                        required = False,
                        help = f'Runs GenerateParams ({generate_params_path}) on provided data.',
                        action='store_true')
    
    procs.add_argument('--run_syntax_check',
                        required = False,
                        help = f'Runs a syntax check using the syntax checker located at {syntax_checker_path}.',
                        action='store_true')
    
    procs.add_argument('--run_P2',
                        required = False,
                        help = f'Runs P2 ({p2_path}) on provided data.',
                        action='store_true')
    
    #Require either data_paths or a source csv file to run.
    if not '--data_paths' in sys.argv:
        require_data_file = True

    if not '--data_file' in sys.argv:
        require_data_path = True

    
    #General Settings
    settings = parser.add_argument_group('Settings')
    
    settings.add_argument('--data_paths',
                        required = require_data_paths,
                        help = 'Specify data paths of interest.',
                        type = str,
                        nargs = '+')     
    
    settings.add_argument('--data_file',
                        required = require_data_file,
                        help = 'Specify a csv file which contains the data paths of interest.',
                        type = str)     
    
    settings.add_argument('--data_column',
                        required = False,
                        help = 'Specify a csv file which contains the data paths of interest.',
                        default = Definitions.DATA_PATH,
                        type = str)     
    
    settings.add_argument('--syntax_strictness',
                        required = False,
                        help = 'The syntax strictness to use.',
                        default = 0,
                        type=int)
    
    settings.add_argument('--syntax_verbosity',
                        required = False,
                        help = 'The syntax strictness to use.',
                        default = 2,
                        type=int)
    
    settings.add_argument('--reg',
                        required = False,
                        help = f'Runs registration processing.',
                        action='store_true')
    
    settings.add_argument('--fMRI',
                        required = False,
                        help = f'Runs functional MRI processing.',
                        action='store_true')
    
    settings.add_argument('--surf',
                        required = False,
                        help = f'Runs surface projection.',
                        action='store_true')
    
    settings.add_argument('--QC',
                        required = False,
                        help = f'Runs QC generation.',
                        action='store_true')
    

    args = parser.parse_args() 
    
    #Set the data path based on whichever was specified.
    data_source = ''
    if args.data_file:
        data_source = Checks.expand_data_path(args.data_file, args.execution_path)
    else:
        data_source = args.data_paths
        
        #Expand out all the paths if needed.
        for index,path in enumerate(data_source):
            data_source[index] = Checks.expand_data_path(path, args.execution_path)

    log_file = Checks.expand_data_path(args.log_file, args.execution_path)
    
    #Create the ProcessManager instance.
    process_manager = pm.ProcessManager(data_source, 
                                        log_file, 
                                        args.num_cores,
                                        args.data_column)

    if args.run_generate_params:
        process_manager.run_generate_params()

    if args.run_syntax_check:
        process_manager.run_syntax_check([args.syntax_verbosity, 
                                          args.syntax_strictness])
    if args.run_P2:
        mods_to_run = [
            ('-reg' , args.reg),
            ('-fMRI', args.fMRI),
            ('-surf', args.surf),
            ('-QC'  , args.QC)
        ]
        
        argument_list = []
        for flag, status in mods_to_run:
            if status:
                argument_list.append(flag)
        
        argument_list += ['-syntax_verbosity', str(args.syntax_verbosity), 
                          '-syntax_strictness', str(args.syntax_strictness)]

        process_manager.run_P2(argument_list)

    
