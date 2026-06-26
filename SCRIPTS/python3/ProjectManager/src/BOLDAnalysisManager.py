import os
from scipy.io import loadmat
import numpy as np
import tqdm
import subprocess
import datetime as dt

import src.DataModels.Definitions as Definitions
import src.DataModels.ColumnNames as ColumnNames 
import src.DataModels.AnalysisDefinitions as AnalysisDefinitions
import src.DataExtraction as DataExtractor

import src.Session as Session
import src.Utils.DatabaseManager as DBM

class BOLDAnalysis(DBM.DatabaseManager):
    '''Handles the automated post processing and analysis of UNP processing.

    Attributes:
        __analysis_utils (str) : The path to the analysis utils folder which contains relevant matlab and post 
                                 processing scripts.
    Requirements:
        "fslmaths" and "matlab" with a appropriate licenses must be in the system path in order for all functionality 
        to work.
    '''

    def __init__(self, 
                 project: str, 
                 database_name: str, 
                 exclude_networks: list,
                 log_file: str) -> None:
        '''Initialize the analysis manager object.

        Parameters:
            project          (str)       : The project name.
            database_name    (str)       : The name of the mongoDB database.
            exclude_networks (list[str]) : A list of networks to exclude from analysis reports.
        '''

        self.__analysis_utils = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'Utils/Analysis')

        super().__init__(database_name, project, log_file)
        
        #Now we need to remove the networks we want to exclude.
        for network in exclude_networks:
            if network in AnalysisDefinitions.BOLD_MEAN_NETWORKS:
                del AnalysisDefinitions.BOLD_MEAN_NETWORKS[network]
                continue

            self.log((f'Could not exclude the network {network} '
                      f'because it does not exist in the AnalysisDefinitions file.'))

    #Analysis and data extraction.
    def __extract_network_means(self, network_means_file: str) -> dict:
        '''Extract a dictionary containing the network means from a network means ".mat" file.

        Requires that the network means file must contain a 'SeedCorrMatrix' key to extract data from. This could be 
        improved in the future if processing of networks means is transitioned away from the old matlab scripts and 
        into this class internally. However thats neither here nor there.

        Parameters:
            network_means_file (str) : The path to the network means file.

        Returns:
            networks (dict[str -> float]) : A dictionary where the keys are the subnetwork names
                                            and the values are subnetwork values.
        '''

        data_key = 'SeedCorrMatrix'  
        try:
            mat_file = loadmat(network_means_file)
            z_matrix = np.arctanh(np.triu(mat_file[data_key], k = 1))
        except KeyError:
            self.log(f'Could not extract {data_key} from file {os.path.basename(network_means_file)}.')
            return {}

        #Next we need to create the network means matrix.
        networks = {}   

        network_names  = list(AnalysisDefinitions.BOLD_MEAN_NETWORKS.keys())
        network_ranges = list(AnalysisDefinitions.BOLD_MEAN_NETWORKS.values())
        
        for i, range1 in enumerate(network_ranges):
            sub_net1 = network_names[i]

            for j, range2 in enumerate(network_ranges[i:], start = i):
                sub_net2 = network_names[j]

                submatrix = z_matrix[np.ix_(range1, range2)]
                submatrix_nonzero = submatrix[(submatrix != 0) & (~np.isnan(submatrix))] 

                mean = 0
                if submatrix_nonzero.size > 0:
                    mean = np.mean(submatrix_nonzero)

                #Now add to the networks dictionary.
                networks[f'{sub_net1}_x_{sub_net2}'] = mean
        
        return networks

    def __extract_BOLD_MB_level(self, session_data_path: str) -> tuple:
        '''Attempts to return the BOLD MB level for the given data path.
        
        Parameters:
            session_data_path (str) : The path to the session folder of interest.
        
        Returns:
            MB_level (int) : The multiband level of the BOLD session extracted from the session params file. 0 is 
                             returned if the MB level cant be determined.
        '''

        extractor = DataExtractor.DataExtractor(self._projects_data, session_data_path, self)
        

        return (extractor.get_MB_level(), )

    def __extract_BOLD_denoising(self, session_data_path: str) -> tuple:
        '''Extract the bold atlas aligned, denoising, and the atlas aligned / denoising ratio.
        
        Extract the atlas aligned, denoising and atlas aligned from the fMRI_denoising.txt file. Assumes that the
        file has two lines. The first line is the atlas aligned value and the second is the denoising value. 
        Additionally, the values must be the last thing in each line.

        Parameters:
            session_data_path (str) : The path to the sub/ses folder.

        Returns:
            tuple (float, float, float) : The atlas aligned, denoising, and aa/dn ratio.
        '''

        aa = 0
        dn = 0
        r = 0
        try:
            bold_denoising_path = os.path.join(session_data_path, 
                                               AnalysisDefinitions.QC_DIR, 
                                               AnalysisDefinitions.BOLD_VARIANCE_FILE)

            time_remaining_file = open(bold_denoising_path, 'r')
            lines = [ line.strip() for line in time_remaining_file.readlines() ] 
            
            file_rows = iter(lines)
            try:
                try:
                    aa = float(next(file_rows).split()[-1])
                    dn = float(next(file_rows).split()[-1])

                except ValueError:
                    pass
                
            except StopIteration:
                pass
            time_remaining_file.close()
        except FileNotFoundError:
            pass
        
        if dn != 0:
            r = aa/dn
        return (aa, dn, r)

    def __extract_frame_info(self, session_path: str) -> tuple:
        '''Try to extract BOLD frame data from a given session. Return 

        Extract the BOLD frame count variables from the provided BOLD session (except the first 4 of each run which are 
        unused) from a given session path. Extracts total frames, usable_frames, and mean FD, and the time delta 
        between frames.

        Parameters:
            session_data_path (str) : The path to the sub/ses folder.

        Returns:
            tuple (int, int, float) : A tuple containing total frames, the usable frames after censoring, the 
                                      mean frame displacement value, and the frame time delta.

        '''

        #First determine if necisarry file paths exist.
        movement_dir = os.path.join(
            session_path, 
            AnalysisDefinitions.BOLD_DIR, 
            AnalysisDefinitions.BOLD_MOVEMENT_DIR
        )

        movement_list_file = os.path.join(movement_dir, AnalysisDefinitions.BOLD_RUN_LIST_FILE)
        #Try to open the file and get the fd values for each bold run.
         
        movement_values = []
        total_frames = 0
        uncensored_frames = 0
        
        run_list = []
        try:
            list_file = open(movement_list_file, 'r')
            run_list = [fname.replace('_dat','') for fname in list_file.read().splitlines()]
            list_file.close()
                
        except FileNotFoundError:
            self.log(f'Could not find {movement_list_file}.')
            return (0, 0, 0)
        
        for run_file in run_list:
            #Extract total frames and the number of usable_frames. 
            try:
                time_mask_path = os.path.join(
                    movement_dir, 
                    f'{run_file}.{AnalysisDefinitions.BOLD_FRAME_MASK_EXTENSION}'
                )

                mask_file = open(time_mask_path, 'r')
                mask_list = [ int(mask) for mask in mask_file.readline().split() ]
                mask_file.close()
                
                total_frames += len(mask_list)
                uncensored_frames += sum(mask_list)

            except FileNotFoundError:
                self.log(f'Could not find the frame mask file {time_mask_path}')
                return (0, 0, 0)

            #Extract mean fd value.
            try:
                fd_file_path = os.path.join(movement_dir, f'{run_file}.{AnalysisDefinitions.BOLD_FD_EXTENSION}')
                fd_file = open(fd_file_path, 'r')
                exclusion_frame_counter = 0
                
                for line in fd_file:

                    #Skip the first N frames defined in the AnalysisDefinitions file.
                    if exclusion_frame_counter < AnalysisDefinitions.BOLD_EXCLUDE_FIRST_FRAMES:
                        exclusion_frame_counter += 1
                        continue

                    try:
                        movement_values.append(float(line))
                    except ValueError:
                        self.log(f'Could not convert {line} to a floating point value in {fd_file_path}')

                fd_file.close()

            except FileExistsError:
                return (0, 0, 0)

        #Average everything that was extracted.
        mean_fd = 0
        if len(movement_values) > 0:
            mean_fd = np.median(movement_values)

        return (total_frames, uncensored_frames, mean_fd)
        
    #Runs the smooth_subjects script on the given session data path.
    def __smooth_session(self, 
                         session_object   : Session.Session, 
                         smoothing_amount : float, 
                         force_smoothing  : bool) -> None:
        '''Runs gaussian smoothing on a provided session.

        Perform gaussian smoothing on the BOLD "_rsfMRI_uout_bpss_resid" or "_rsfMRI_uout_resid_bpss" files if they 
        exist and smoothing hasnt already been performed. If force_smoothing is True then overwrite smoothed files.
        
        Requires that "fslmaths" is in the environment path in order to compute the smoothing.

        Parameters:
            session_object   (Session) : The Session to apply smoothing to.
            smoothing_amount (float)   : The amount of smoothing to apply.
            force_smoothing  (bool)    : A flag to force smoothing to be applied even if smoothing 
                                         files were already found.
        '''
        
        #Extract the bold analysis for this session.
        if not AnalysisDefinitions.BOLD in session_object.analysis:
           return #There is no analysis here.

        analysis_object  = session_object.analysis[AnalysisDefinitions.BOLD]

        #First check if smoothing has been set for this session.
        session_id = session_object.data[ColumnNames.SESSION_ID]
        session_data_path = session_object.data[ColumnNames.DATA_PATH]
        sub_ses = os.path.basename(session_data_path)
        functional_volume_path = os.path.join(session_data_path, 'Functional/Volume')

        smoothing_value_format = str(smoothing_amount).rstrip('0').rstrip('.')
        smoothing_types = {
            AnalysisDefinitions.BOLD_BPASS_SMOOTHING : f'{sub_ses}{AnalysisDefinitions.BOLD_BANDPASS}',
            AnalysisDefinitions.BOLD_RESID_SMOOTHING : f'{sub_ses}{AnalysisDefinitions.BOLD_RESID}'
        }

        smoothing_file_names = {}
        for name in smoothing_types:
            smoothing_file_names[name] = f'{smoothing_types[name]}_sm{smoothing_value_format}.nii.gz'

        #Check if smoothing files are present on the file system. If so then smoothing defintely has been run.
        smoothed = False
        for smoothing_type, file_name  in smoothing_file_names.items():
            if os.path.isfile(os.path.join(functional_volume_path, file_name)):
                smoothed = True
                analysis_object.update( {smoothing_type : True} )
                continue

            analysis_object.update( {smoothing_type : False} )

        
        if (smoothed and not force_smoothing):
            self.log(f'It appears that smoothing has already been performed for the session {session_id}. Skipping...')
            return
        
        #Otherwise we need to smooth the subject.
        self.log(f'Smoothing session {session_id}...')
        smoothing_sigma = smoothing_amount / 2.3548 

        current_dir = os.getcwd()
        os.chdir(functional_volume_path)

        smoothing_applied = []
        for smoothing_type in smoothing_types:
            name = smoothing_types[smoothing_type]
            if os.path.isfile(os.path.join(functional_volume_path, f'{name}.nii.gz')):
                
                command_string = (f'fslmaths {name}.nii.gz '
                                  f'-kernel gauss {smoothing_sigma} '
                                  f'-fmean {name}_sm{smoothing_value_format}.nii.gz')

                smoothing = subprocess.Popen(command_string.split(), 
                                               stdout = subprocess.PIPE, 
                                               stderr = subprocess.PIPE,
                                               universal_newlines = True)

                stdout, stderr = smoothing.communicate()
                
                if stdout != '':
                    self.log(f'Command output:{stdout}')
                if stderr != '':
                    self.log(f'Command error:{stderr}')

                smoothing.wait()
                
                if smoothing.returncode == 0:
                    smoothing_applied.append(smoothing_type)

        os.chdir(current_dir)

        if len(smoothing_applied) == 0:
            self.log(f'Could not apply smoothing to {sub_ses}, make sure that all required files have been generated.')
            return
        
        #Now we need to go through the smoothing applied and updated the session objects appropriately.
        for smoothing in smoothing_applied:
            analysis_object.update({ smoothing : True })  

    def __compute_session_seed_corr(self,
                                    session_object: Session.Session, 
                                    seed_corr_output_dir: str,
                                    force_new_correlation: bool) -> None:
        '''Compute the participant seed correlation matrix for a processed session.

        This function essentially wraps a matlab file called "Compute_Participant_Seed_Corr.m". 

        Parameters:
            session_object        (Session) : The Session to compute the participant seed correlation for.
            seed_corr_output_dir  (str)     : The directory to save the resulting seed correlation file to.
            force_new_correlation (bool)    : Force the correlation to be computed even if an existing file is found.
        '''
        
        if not AnalysisDefinitions.BOLD in session_object.analysis:
            return

        session_id = session_object.data[ColumnNames.SESSION_ID]
        bold_analysis = session_object.analysis[AnalysisDefinitions.BOLD]

        #First check if BOLD analysis already exists for this session.
        if (
            AnalysisDefinitions.BOLD_SEED_CORR_ANALYSIS in bold_analysis.data and
            len(bold_analysis.data[AnalysisDefinitions.BOLD_SEED_CORR_ANALYSIS]) > 0 and
            not force_new_correlation
        ):
            self.log(('It appears that correlation matrices were already found for the session '
                      f'{session_id}, skipping...'))
            return
        
        session_data_path = session_object.data[ColumnNames.DATA_PATH]
        sub_ses = os.path.basename(session_data_path)
        
        #We need to find the Analysis folder.
        split_session_path = session_data_path.split(os.sep)
        project_alias_folder = os.sep.join(split_session_path[:2])
        found = False
        
        for dir in split_session_path[2:]:
            project_alias_folder += f'{os.sep}{dir}'
            if dir in self._projects_data[Definitions.PROJECTS][self._project][Definitions.PROJECT_ALIASES]:
                found = True
                break

        #Now see if we found the project folder.
        if not found:
            self.log(f'Could not find a project folder for the session {session_id}. Skipping...')
            return

        output_data_path = os.path.join(project_alias_folder, AnalysisDefinitions.ANALYSIS, seed_corr_output_dir)
        os.makedirs(output_data_path, exist_ok = True)
        output_data_path = os.path.join(output_data_path, f'{sub_ses}_seed_corr.mat')

        #Now we need to run the matlab script to compute the volume seed correlation.
        command_string = (f'matlab -batch '
                          f'"Compute_Participant_Seed_Corr('
                              f'\'{session_object.data[ColumnNames.DATA_PATH]}\',\'{output_data_path}\''
                          f')"')
        
        try:
            matlab = subprocess.Popen(command_string, 
                                      shell = True,
                                      cwd = self.__analysis_utils,
                                      stdout = subprocess.PIPE, 
                                      stderr = subprocess.PIPE,
                                      universal_newlines = True)

            stdout, stderr = matlab.communicate()
            
            if stdout != '':
                self.log(f'Command output:{stdout}')
            if stderr != '':
                self.log(f'Command error:{stderr}')

            matlab.wait()
        except:
            self.log(f'There was an error attempting to compute participant seed correlation for session {session_id}.')
            return

        #Now check to see if the file was generated. If it was then we should add it to the session data. 
        if matlab.returncode != 0:
            self.log(f'There was an error attempting to compute participant seed correlation for session {session_id}.')
            return
        
        bold_analysis.append_to_list(AnalysisDefinitions.BOLD_SEED_CORR_ANALYSIS, output_data_path)

    #------------------------------ Analysis run options (session specific) ------------------------------.
    def run_session_smoothing(self,
                              sub_ses_list: list,
                              smoothing_amount: float,
                              force_smoothing: bool) -> None:
        '''Run smoothing on appropiate UNP BOLD files for specific sessions in a given project.

        Parameters:
            sub_ses_list     (list)  : This is a list of sub/ses strings which specifies specific sessions of interest
                                       instead of running smoothing on the whole project.
            smoothing_amount (float) : The amount of smoothing to use.
            force_smoothing  (bool)  : A flag which overwrites existing smoothing files if set.
        '''
        
        self.set_tqdm_print()
        for session_object in tqdm.tqdm(self._generate_sessions_by_sub_ses_strings(sub_ses_list), 
                                        desc = f'Running gaussian smoothing for sessions in {self._project}',
                                        total = len(sub_ses_list)):
            if session_object != None:
                self.__smooth_session(session_object, smoothing_amount, force_smoothing)
        self.unset_tqdm_print()
    
    def run_session_seed_corr(self,
                              sub_ses_list: list,
                              seed_corr_output_dir: str,
                              force_seed_corr: bool) -> None:
        '''Run seed correlation matrix calculations on appropiate UNP BOLD files for a specified sessions.

        Parameters:
            seed_corr_output_dir (str)  : The directory to output seed correlation matrices to.
            force_seed_corr      (bool) : A flag which overwrites existing smoothing files if set.
        '''

        self.set_tqdm_print()
        for session_object in tqdm.tqdm(self._generate_sessions_by_sub_ses_strings(sub_ses_list), 
                                        desc = f'Generating seed correlation matrices for sessions in {self._project}',
                                        total = len(sub_ses_list)):
            if session_object != None:
                self.__compute_session_seed_corr(session_object, seed_corr_output_dir, force_seed_corr)
        self.unset_tqdm_print()
    
    def run_session_BOLD_post_proc(self,
                                   sub_ses_list: list,
                                   smoothing_amount: float,
                                   seed_corr_output_dir: str,
                                   force_analysis: bool) -> None:
        '''Run BOLD post processing steps for the current project.

        Runs project smoothing then project seed correlation matrix calculations.

        Parameters:
            smoothing_amount     (float) : The smoothing amount.
            seed_corr_output_dir (str)   : The directory to output seed correlation matrices to.
            force_seed_corr      (bool)  : A flag which overwrites existing smoothing files if set.
        '''
        
        self.run_session_smoothing(sub_ses_list, smoothing_amount, force_analysis)
        self.run_session_seed_corr(sub_ses_list, seed_corr_output_dir, force_analysis)
    
    #------------------------------ Analysis run options (project specific) ------------------------------.
    def run_project_smoothing(self,
                              smoothing_amount: float,
                              force_smoothing: bool) -> None:
        '''Run smoothing on appropiate UNP BOLD files for everything in the given project.

        Parameters:
            smoothing_amount (float) : The amount of smoothing to use.
            force_smoothing  (bool)  : A flag which overwrites existing smoothing files if set.
            sub_ses_list     (list)  : This is a list of sub_ses strings which specifies specific sessions of interest
                                       instead of running smoothing on the whole project.
        '''

        self.set_tqdm_print()
        for subject_object in tqdm.tqdm(self._generate_subject_by_project(False), 
                                        desc = f'Running gaussian smoothing for project {self._project}',
                                        total = self._get_total_subjects_in_project()):
            
            #Go through each session, check that the session is in Participants and if so try to run the smoothing.
            for session_uid in subject_object.sessions:
                session_object = subject_object.sessions[session_uid]
                if Definitions.PARTICIPANTS in session_object.data[ColumnNames.DATA_PATH]:
                    self.__smooth_session(session_object, smoothing_amount, force_smoothing)

            subject_object.clear()
        self.unset_tqdm_print()
    

    def run_project_seed_corr(self,
                              seed_corr_output_dir: str,
                              force_seed_corr: bool) -> None:
        '''Run seed correlation matrix calculations on appropiate UNP BOLD files for a specific project.

        Parameters:
            seed_corr_output_dir (str)  : The directory to output seed correlation matrices to.
            force_seed_corr      (bool) : A flag which overwrites existing smoothing files if set.
        '''

        self.set_tqdm_print()
        for subject_object in tqdm.tqdm(self._generate_subject_by_project(False), 
                                        desc = f'Generating seed correlation matrices for project {self._project}',
                                        total = self._get_total_subjects_in_project()):
            
            #Go through each session, check that the session is in Participants and if so try to run the smoothing.
            for session_uid in subject_object.sessions:
                session_object = subject_object.sessions[session_uid]
                if Definitions.PARTICIPANTS in session_object.data[ColumnNames.DATA_PATH]:
                    self.__compute_session_seed_corr(session_object, seed_corr_output_dir, force_seed_corr)

            subject_object.clear()

        self.unset_tqdm_print()

    def run_BOLD_post_proc(self,
                           smoothing_amount: float,
                           seed_corr_output_dir: str,
                           force_analysis: bool) -> None:
        '''Run BOLD post processing steps for the current project.

        Runs project smoothing then project seed correlation matrix calculations.

        Parameters:
            smoothing_amount     (float) : The smoothing amount.
            seed_corr_output_dir (str)   : The directory to output seed correlation matrices to.
            force_seed_corr      (bool)  : A flag which overwrites existing smoothing files if set.
        '''
        
        self.run_project_smoothing(smoothing_amount, force_analysis)
        self.run_project_seed_corr(seed_corr_output_dir, force_analysis)
    
    #------------------------------ Analysis extraction options ------------------------------.
    def extract_QC_metrics(self) -> None:
        '''Extract the QC metrics from smoothed sessions and add them to the DB.
        
        Extract QC metrics from session BOLD files including BOLD time remaining, atlas aligned, denoising, and the
        (atlas aligned / denoising) ratio.
        '''
        
        self.set_tqdm_print()
        for subject_object in tqdm.tqdm(self._generate_subject_by_project(False),
                                        total=self._get_total_subjects_in_project(),
                                        desc ='Extracting QC metrics: '):

            for session_object in subject_object.sessions.values():
                if not AnalysisDefinitions.BOLD in session_object.analysis:
                    continue
                
                session_path = session_object.data[ColumnNames.DATA_PATH]
                aa, dn, r = self.__extract_BOLD_denoising(session_path)
                total_frames, usable_frames, mean_fd = self.__extract_frame_info(session_path)
                
                #Instaniate an extractor object to get session specific variables.
                extractor = DataExtractor.DataExtractor(self._projects_data, session_path, self)
                extracted_bold_data = extractor.get_BOLD_params()
                
                #If nothing was extracted then dont add anything.
                if len(extracted_bold_data) == 0:
                    continue

                usable_time = 0 
                if AnalysisDefinitions.BOLD_TR in extracted_bold_data:
                    usable_time = extracted_bold_data[AnalysisDefinitions.BOLD_TR] * usable_frames

                extracted_bold_data.update(
                    {
                        AnalysisDefinitions.BOLD_MB_LEVEL       : extractor.get_MB_level(),
                        AnalysisDefinitions.BOLD_TOTAL_FRAMES   : total_frames,
                        AnalysisDefinitions.BOLD_USABLE_FRAMES  : usable_frames,
                        AnalysisDefinitions.BOLD_TIME_REMAINING : usable_time,
                        AnalysisDefinitions.BOLD_FD             : mean_fd,
                        AnalysisDefinitions.BOLD_ATLAS_ALIGNED  : aa,
                        AnalysisDefinitions.BOLD_DENOISING      : dn,
                        AnalysisDefinitions.BOLD_VAR_RATIO      : r
                    }
                )

                #The implemenation of the BOLD MB level extraction is very slow because it uses the DataExtractor 
                #class which does a lot of stuff which is not useful for just getting the MB level. This is could be 
                #faster if the bold MB level extraction was separated from the DataExtractor.
                session_object.analysis[AnalysisDefinitions.BOLD].update(extracted_bold_data)

        self.unset_tqdm_print()
    
    def extract_BOLD_network_means(self) -> None:
        '''Extract the network means from existing seed correlation files and add them to the analysis DB document.
        '''
        
        self.set_tqdm_print()
        for subject_object in tqdm.tqdm(self._generate_subject_by_project(False),
                                        total=self._get_total_subjects_in_project(),
                                        desc='Extracting network means: '):
            for session_object in subject_object.sessions.values():
                if not AnalysisDefinitions.BOLD in session_object.analysis:
                    continue
                
                analysis_object = session_object.analysis[AnalysisDefinitions.BOLD]
                if not AnalysisDefinitions.BOLD_SEED_CORR_ANALYSIS in analysis_object.data:
                    continue
                
                all_network_means = {}
                for path in analysis_object.data[AnalysisDefinitions.BOLD_SEED_CORR_ANALYSIS]:
                    
                    try:
                        file_stat = os.stat(path)
                        path_entry = {
                            AnalysisDefinitions.BOLD_SEED_CORR_PATH : path,
                            AnalysisDefinitions.LAST_MODIFIED : dt.datetime.fromtimestamp(
                                                                    file_stat.st_mtime, 
                                                                    tz=dt.timezone.utc
                                                                ).strftime('%Y-%m-%d %H:%M'), 
                            AnalysisDefinitions.OWNER : file_stat.st_uid
                        }
                    except Exception as e:
                        self.log(f'Could not stat {path}, {e}')
                        continue

                    path_entry.update(self.__extract_network_means(path))
                    all_network_means[path] = path_entry
                
                #Now add this to the analysis.
                analysis_object.update({AnalysisDefinitions.BOLD_MEANS : all_network_means})
        self.unset_tqdm_print()

    def clear_BOLD_analysis(self) -> None:
        '''For each analysis object clear out all extraneous metadata. Data will be written again upon next extraction.

        Primarily used in development to ensure a clean database.
        '''
        for subject_object in tqdm.tqdm(self._generate_subject_by_project(False),
                                        total=self._get_total_subjects_in_project(),
                                        desc='Cleaning extracted metadata: '):
            for session_object in subject_object.sessions.values():
                if not AnalysisDefinitions.BOLD in session_object.analysis:
                    continue
                
                analysis_object = session_object.analysis[AnalysisDefinitions.BOLD]

                keys_to_remove = set(analysis_object.data.keys()) - {'_id', AnalysisDefinitions.ANALYSIS_TYPE}
                analysis_object.clean_keys(keys_to_remove)



