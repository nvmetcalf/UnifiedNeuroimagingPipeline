import multiprocessing
import subprocess
import os
import enum
import pandas

class ProcessingCommand(enum.Enum):
    SYNTAX_CHECK    = 1
    P2              = 2
    GENERATE_PARAMS = 3

class ProcessManager(object):
    def __init__(self, paths: list | str, log_file: str, num_cores: int, default_data_column) -> None:
        self.__num_cores = num_cores
        self.__log_file = log_file

        self.manager = multiprocessing.Manager()
        self.successes = self.manager.list()
        self.failures = self.manager.list()

        #Paths can be either a list or a string which points to a csv file.
        if type(paths) == list:
            self.paths = paths
        else:
            #Otherwise then it is a name to a csv file.
            try:
                df = pandas.read_csv(paths)
                self.paths = df[default_data_column].dropna().tolist()
            except FileNotFoundError:
                print(f'File {paths} not found. Please check the filename and try again.')
                raise FileNotFoundError

        #Test if the number of cores is greater than or equal to the number of jobs. If it is
        #then adjust it so that we dont try to run on too many cores.
        amount_of_work = len(self.paths)
        if self.__num_cores > amount_of_work:
            print(f'The number of cores set {self.__num_cores} is greater than the number of jobs to process {amount_of_work}.')
            print('Adjusting the number of cores to match the number of jobs.')
            self.__num_cores = amount_of_work

    
    #Generates the command to execute and switches the current working directory
    #to the correct location to execute that command.
    def __generate_command(self, command: ProcessingCommand, path: str, args: list) -> str:
        args = [str(arg) for arg in args]
        result = ''
        sub_folder = os.path.basename(path)

        if not os.path.isdir(path):
            return ''

        if command == ProcessingCommand.GENERATE_PARAMS:
            os.chdir(path)
            result = 'GenerateParams'
        if command == ProcessingCommand.SYNTAX_CHECK:
            #Get the file name from the data path.
            syntax_fname = f'{sub_folder}.params'

            #switch to the correct path as well.
            os.chdir(path)
            
            #Check if the file exists.
            if not os.path.isfile(syntax_fname):
                return ''

            #return the command string with the args (syntax verbosity and strictness) attatched
            result = f'CheckSyntax {syntax_fname} ' + ' '.join(args)

        if command == ProcessingCommand.P2:
            os.chdir(os.path.join(path, '../'))
            result = f'P2 {sub_folder} ' + ' '.join(args)

        return result 

    #This is the driver function which runs the target process.
    #It takes:
    #   1. A starting index for data paths (inclusive)
    #   2. The ending index for data paths (exclusive)
    #   3. The system process to run on all data paths
    #   4. The arguments passed in for this process

    def __run_process(self, 
                      system_proc: ProcessingCommand, 
                      batch_number: int, 
                      args: list) -> None:


        #Check the indicies of the processing paths.
        if batch_number >= self.__num_cores or self.__num_cores < 1: 
            return
        
        data_paths = []
        
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
        
        print(f'Batch {batch_number} processing data slice [{start_index},{end_index}].')

        #Now access the correct data paths for this batch.
        data_paths = self.paths[start_index : end_index]
        
        #Create the log_file for this batch.
        file_path    = os.path.dirname(self.__log_file)
        log_name     = os.path.basename(self.__log_file)
        split = os.path.splitext(log_name)
        fname = f'{split[0]}_{system_proc.name}_batch_{batch_number}{split[1]}'
        fpath = os.path.join(file_path, fname)
        
        f = None
        try:
            f = open(fpath, 'w')
        except:
            return
        
        #Now we have the log file open for writting.
        f.write(f'Created log file {fname}, executing the following command: \n')
        for index,path in enumerate(data_paths):
            proc_command = self.__generate_command(system_proc, path, args)
            
            if proc_command == '':
                f.write(f'Could not generate processing command for data path {path}, moving on...\n')
                continue

            f.write(f'Executing command: {proc_command}\n')

            #Run the process.
            result = subprocess.run(
                proc_command.split(),
                stdout = subprocess.PIPE,
                stderr = subprocess.PIPE,
                universal_newlines = True
            )

            #Dump stdout and stderr to the log file.
            f.write(f'Execution for {path} complete\n')
            f.write('Standard Output:\n')
            f.write(result.stdout)
            f.write('\n')
            f.write('Standard Error:\n')
            f.write(result.stderr)
            f.write('\n\n')

            #Now append the successes and failures to each list.
            if result.returncode:
                print(f'Batch {batch_number} completed running {system_proc.name} on data source {index + 1}/{len(data_paths)}.')
                self.failures.append(path)
                continue
            
            print(f'Batch {batch_number} completed running {system_proc.name} on data source {index + 1}/{len(data_paths)}.')
            self.successes.append(path)

        f.close()
    
    def __dispatch_jobs(self,job: ProcessingCommand, args: list) -> None:
        current_dir = os.getcwd()
        processes = []
        
        f = None
        try:
            f = open(self.__log_file, 'w')
        except:
            return

        f.write(f'Created log file {os.path.basename(self.__log_file)}, executing the job {job.name} in {self.__num_cores} processes.\n')
        for batch_number in range(self.__num_cores):
            p = multiprocessing.Process(target = self.__run_process, 
                                        args = [job, 
                                                batch_number,
                                                args])

            f.write(f'Dispatching batch {batch_number}...\n')
            processes.append(p)
            p.start()

        #Now wait for all the processes to complete
        for p in processes:
            p.join()

        f.write(f'All jobs complete.\n')
        f.write(f'\nThe following data paths completed {job.name} with exit status 0:\n')
        for path in self.successes:
            f.write(f'{path}\n')
        f.write(f'\nThe following data paths completed {job.name} with non-zero exit status:\n')
        for path in self.failures:
            f.write(f'{path}\n')
        
        #Switch the working directory back to where we started.
        os.chdir(current_dir)
    
    def run_P2(self, args: list) -> None:
        self.__dispatch_jobs(ProcessingCommand.P2, args)
    
    def run_syntax_check(self, args: list) -> None:
        self.__dispatch_jobs(ProcessingCommand.SYNTAX_CHECK, args)

    def run_generate_params(self) -> None:
        self.__dispatch_jobs(ProcessingCommand.GENERATE_PARAMS, [])



