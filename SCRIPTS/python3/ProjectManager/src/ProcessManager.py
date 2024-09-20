import multiprocessing
import subprocess
import os
import src.DataModels.Definitions as Definitions
from src.Utils.ParseCSV import ParseCSV
from enum import IntFlag

#Defines the different processing states which can be set.
#Regular just means execute the command normally,
#Switch path means switch the command execution directly.
#Finally PATH_ARG means use the path as an execution argument.
class ProcessingState(IntFlag):
    REGULAR              = 0 
    SWITCH_PATH          = 1
    PATH_ARG             = 1 << 1 
    FIND_PARAMS          = 1 << 2
    SWITCH_TO_INPROCESS  = 1 << 3


class ProcessManager(object):
    def __init__(self, log_file: str, num_cores: int, placeholder_argument_mapping: dict) -> None:
        
        #First check if PP_SCRIPTS is in the environment variables and in path.
        pp_scripts_dir = os.environ.get('PP_SCRIPTS')
        if not pp_scripts_dir:
            print(f'The environment variable PP_SCRIPTS is not set, please ensure your environment variables are set correctly.')
            raise RuntimeError

        path_dirs = os.environ.get('PATH', '').split(os.pathsep)
        if not pp_scripts_dir in path_dirs:
            print(f'PP_SCRIPTS: {pp_scripts_dir} is not $path, please ensure your environment variables are set correctly.')
            raise RuntimeError

        self.__num_cores = num_cores
        self.__log_file = log_file
        self.proc_command = ''
        self.arg_list = []
        self.processing_state = ProcessingState.REGULAR

        self.manager = multiprocessing.Manager()
        self.successes = self.manager.list()
        self.failures = self.manager.list()

        #Compile a list of valid commands.
        # List all files in the directory
        files = os.listdir(pp_scripts_dir)
        
        # Initialize an empty list to store executable files
        self.executables = []
        
        # Iterate over each file in the directory
        for file in files:
            # Get the full path of the file
            file_path = os.path.join(pp_scripts_dir, file)
            
            # Check if the file is a regular file and is executable
            if os.path.isfile(file_path) and os.access(file_path, os.X_OK):
                # Add the file to the list of executables
                self.executables.append(file)

        self.placeholder_argument_mapping = placeholder_argument_mapping

    def __parse_cmd_string(self,
                           cmd: str,
                           data_path: str) -> str:
        result = cmd 

        result = result.replace(f'@{chr(ProcessingState.PATH_ARG)}@', os.path.basename(data_path))

        params_path = ''
        for path in os.listdir(data_path):
            if path == f'{os.path.basename(data_path)}.{Definitions.PARAMS_EXTENSION}':
                params_path = os.path.join(data_path, path)


        result = result.replace(f'@{chr(ProcessingState.FIND_PARAMS)}@', params_path)


        return result

    
    def __run_and_dump(self, 
                       f, 
                       cmd_str: str, 
                       batch_number: int, 
                       current_iter: int, 
                       total_work: int) -> None:

        f.write(f'Executing command: {cmd_str}\n')
        f.write(f'Current working directory: {os.getcwd()}\n')
        
        #Run the process.
        result = subprocess.run(
            cmd_str.split(),
            stdout = subprocess.PIPE,
            stderr = subprocess.PIPE,
            universal_newlines = True
        )

        #Dump stdout and stderr to the log file.
        f.write(f'Execution complete\n')
        f.write('Standard Output:\n')
        f.write(result.stdout)
        f.write('\n')
        f.write('Standard Error:\n')
        f.write(result.stderr)
        f.write('\n\n')

        #Now append the successes and failures to each list.
        print(f'Batch {batch_number} completed running "{cmd_str}" on data source {current_iter + 1}/{total_work}.')
        if result.returncode != 0:
            self.failures.append(cmd_str)
            return
        
        self.successes.append(cmd_str)
    
    def __run_process(self, batch_number: int, batch_by_data_paths: bool) -> None:
        #Create the log_file for this batch.
        file_path    = os.path.dirname(self.__log_file)
        log_name     = os.path.basename(self.__log_file)
        split = os.path.splitext(log_name)
        fname = f'{split[0]}_{self.proc_command}_batch_{batch_number}{split[1]}'
        fpath = os.path.join(file_path, fname)
        
        f = None
        try:
            f = open(fpath, 'w')
        except:
            return
        
        #Now we have the log file open for writting.
        f.write(f'Created log file {fname}.\n')

        if batch_by_data_paths:
            #Check the indicies of the processing paths.
            if batch_number >= self.__num_cores or self.__num_cores < 1: 
                return

            
            n_data_paths = len(self.paths)
            left_over = n_data_paths % self.__num_cores
            base_size = n_data_paths // self.__num_cores
            
            
            #Check if we need to shift the start index to account for extra work that has already
            #been accumulated.
            #Calculate the start and stop indexes.
            start_index = base_size * batch_number

            if batch_number != 0:
                start_index += batch_number if batch_number < left_over else left_over
            
            end_index = start_index + base_size
            
            if batch_number < left_over:
                end_index += 1
            
            print(f'Batch {batch_number} processing data slice [{start_index},{end_index - 1}].')
        
        
            #Now access the correct data paths for this batch.
            data_paths = self.paths[start_index : end_index]
            args_slice = self.arg_list[start_index : end_index]
            for index,args_path in enumerate(zip(args_slice, data_paths)):
                args, path = args_path
                cmd_str = f'{self.proc_command} {args}'
                cmd_str = self.__parse_cmd_string(cmd_str, path) 
                
                #Check if we need to change the path because of the processing state.
                if self.processing_state & ProcessingState.SWITCH_PATH:
                    os.chdir(path) #Paths must be absolute

                if self.processing_state & ProcessingState.SWITCH_TO_INPROCESS:
                    split_path = path.split('/')
                    if len(split_path) > 1:
                        os.chdir('/'.join(split_path[:-1]))






                self.__run_and_dump(f, cmd_str, batch_number, index, len(data_paths))

        else:     
            #If we are not batching based on the execution locations then all we need to do is spawn the
            #subprocess for this command.
            cmd_str = f'{self.proc_command} {self.arg_list[batch_number]}'
            cmd_str = self.__parse_cmd_string(cmd_str, '') #Data paths are not relevant in this situation.
            self.__run_and_dump(f, cmd_str, batch_number, 0, 1) 
       
        f.close()
    
    def __dispatch_jobs(self) -> None:
        #Check that the argument list is the same length as the data paths and that the processing command has been
        #specified.
        if self.proc_command == '':
            return
        
        run_data_paths = len(self.paths) > 0

        current_dir = os.getcwd()
        processes = []
        
        f = None
        try:
            f = open(self.__log_file, 'w')
        except:
            return
        
        f.write(f'Created log file {os.path.basename(self.__log_file)}, executing the job {self.proc_command} in {self.__num_cores} processes.\n')

        for batch_number in range(self.__num_cores):
            p = multiprocessing.Process(target = self.__run_process, args = [batch_number, run_data_paths])
            f.write(f'Dispatching batch {batch_number}...\n')
            processes.append(p)
            p.start()

        #Now wait for all the processes to complete
        for p in processes:
            p.join()

        f.write(f'All jobs complete.\n')
        f.write(f'\nThe following completed {self.proc_command} with exit status 0:\n')
        for path in self.successes:
            f.write(f'{path}\n')
        f.write(f'\nThe following completed {self.proc_command} with non-zero exit status:\n')
        for path in self.failures:
            f.write(f'{path}\n')
        
        #Switch the working directory back to where we started.
        os.chdir(current_dir)

    def add_execution_state(self, state: ProcessingState) -> None:
        self.processing_state |= state

    def list_executables(self) -> None:
        print('-------------- Valid Commands --------------')
        for index, exec in enumerate(self.executables):
            print(f'\t{index + 1}. {exec}')

    
    #Executes a command in path using csh. If execution paths are not None then execute the command from each execution path with the args applied.
    #Additionally args can either be a CSV file containing a specification for what arguments to run for each data entry or it can be
    #a list of arguments to apply globally.
    def execute_command(self, 
                        command          : str, 
                        data_source      : list | str | None, 
                        data_column      : str  | None, 
                        args_spec        : list | str | None, 
                        args_data_column : str  | None):
        
        if data_source and type(data_source) == str:
            csv_parser = ParseCSV(data_source)
            
            if data_column == None:
                print(f'The data column has not been specified but the data source {data_source} is assumed to be a csv.')
                print('Cannot extract data from csv file.')
                raise RuntimeError

            self.paths = csv_parser.get_column_as_list(data_column)

            #Test if the number of cores is greater than or equal to the number of jobs. If it is
            #then adjust it so that we dont try to run on too many cores.
            amount_of_work = len(self.paths)
            if self.__num_cores > amount_of_work:
                print(f'The number of cores set {self.__num_cores} is greater than the number of jobs to process {amount_of_work}.')
                print('Adjusting the number of cores to match the number of jobs.')
                self.__num_cores = amount_of_work
            
            #Additionally if args_spec is a string then we are extrating from a csv.
            if args_data_column == None:
                print('Cannot extract arguments from {args_spec} if the argument data column is not specified.')
                raise RuntimeError 
            
            #Lets get all the argument column info and split it up and add it to args
            self.arg_list = [ arg.strip() for arg in csv_parser.get_column_as_list(args_data_column) ]
                
            #Replace placeholder arguments.
            for index in range(len(self.arg_list)): 
                for placeholder in self.placeholder_argument_mapping:
                    self.arg_list[index] = self.arg_list[index].replace(placeholder, self.placeholder_argument_mapping[placeholder])
                    


        #Paths can be either a list or a string which points to a csv file.
        if type(data_source) == list:
            self.paths = data_source 
        elif data_source == None:
            self.paths =  []
            self.__num_cores = 1

        if type(args_spec) == list:
            self.arg_list = [' '.join(args_spec)] * max(len(self.paths), self.__num_cores)
        elif args_spec == None:
            self.arg_list = [''] * max(len(self.paths), self.__num_cores)

        self.proc_command = command

    
        #Now lets attempt to split up the work based on the number of execution_paths. If execution_paths is None, then the command will only be 
        #executed on a single thread once.
        if self.paths == None and self.__num_cores > 1:
            print(f'No execution paths have been specified thus the workload for {command} cannot be distributed.')
            print(f'Adjusting the number of cores from {self.__num_cores} to 1.')
            self.__num_cores = 1

        #Now lets dispatch the jobs.
        self.__dispatch_jobs()
                
