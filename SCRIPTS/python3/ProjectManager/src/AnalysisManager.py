import os
from scipy.io import loadmat
import numpy as np
import tqdm
import subprocess
import builtins

import src.DataModels.Definitions as Definitions
import src.Session as Session
import src.Subject as Subject
import src.Utils.CustomFlatten as CustomFlatten
import src.Utils.DatabaseManager as DBM
import src.Subject as Subject

class AnalysisManager(DBM.DatabaseManager):
    def __init__(self, database_name: str, exclude_networks: list) -> None:
        self.__analysis_utils = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'Utils/Analysis')

        super().__init__(database_name)
        
        #Now we need to remove the networks we want to exclude.
        for network in exclude_networks:
            if network in Definitions.MEAN_NETWORKS:
                del Definitions.MEAN_NETWORKS[network]
                continue

            print(f'Could not exclude the network {network} because it does not exist in the Definitions file.')

    #Analysis and data extraction.
    def __extract_network_means(self, network_means_file: str) -> dict:

        data_key = 'SeedCorrMatrix'  
        mat_file = None
        z_matrix = None
        try:
            mat_file = loadmat(network_means_file)
            z_matrix = np.arctanh(np.triu(mat_file[data_key], k = 1))
        except KeyError:
            print(f'Could not extract {data_key} from file {os.path.basename(network_means_file)}.')
            return {}

        #Next we need to create the network means matrix.
        networks = {}   

        network_names  = list(Definitions.MEAN_NETWORKS.keys())
        network_ranges = list(Definitions.MEAN_NETWORKS.values())
        
        for i, range1 in enumerate(network_ranges):
            sub_net1 = network_names[i]

            for j, range2 in enumerate(network_ranges[i:]):
                sub_net2 = network_names[j]

                submatrix = z_matrix[np.ix_(range1, range2)]
                submatrix_nonzero = submatrix[(submatrix != 0) & (~np.isnan(submatrix))] 

                mean = 0
                if submatrix_nonzero.size > 0:
                    mean = np.mean(submatrix_nonzero)

                #Now add to the networks dictionary.
                networks[f'{sub_net1}_x_{sub_net2}'] = mean
        
        return networks

    def __add_subject_to_analysis_dict(self, 
                                       subject_object: Subject.Subject, 
                                       all_data: dict) -> None:

        map_id = subject_object.data[Definitions.MAP_ID]

        #Add in the important information from the subject.
        all_data[map_id] = {
            Definitions.MAP_ID            : subject_object.data[Definitions.MAP_ID],
            Definitions.SUBJECT_ACCESSION : subject_object.data[Definitions.SUBJECT_ACCESSION],
            Definitions.SESSIONS          : {}
        }
        
        #Now lets iterate through each session object and 
        for session_uid in subject_object.sessions:
            session_data = subject_object.sessions[session_uid].data

            #Now lets copy in some of the session data for this session
            all_data[map_id][Definitions.SESSIONS][session_uid] = {
                Definitions.SESSION_ID           : session_data[Definitions.SESSION_ID],
                Definitions.DATA_PATH            : session_data[Definitions.DATA_PATH],
                Definitions.PROC_STATUS          : session_data[Definitions.PROC_STATUS],
                Definitions.SESSION_ACCESSION    : session_data[Definitions.SESSION_ACCESSION],
                Definitions.FS_VERSION           : session_data[Definitions.FS_VERSION],
                Definitions.BOLD_MB_FACTOR       : session_data[Definitions.BOLD_MB_FACTOR],
                Definitions.BOLD_BPASS_SMOOTHING : session_data[Definitions.BOLD_BPASS_SMOOTHING],
                Definitions.BOLD_RESID_SMOOTHING : session_data[Definitions.BOLD_RESID_SMOOTHING],
                Definitions.ANALYSIS : {}
            }

            #Now lets go through each of the analysis.
            for modality in session_data[Definitions.ANALYSIS]:
                if not modality in all_data[map_id][Definitions.SESSIONS][session_uid][Definitions.ANALYSIS]:
                   all_data[map_id][Definitions.SESSIONS][session_uid][Definitions.ANALYSIS][modality] = {}
                    
                for data_path in session_data[Definitions.ANALYSIS][modality]:
                    all_data[map_id][Definitions.SESSIONS][session_uid][Definitions.ANALYSIS][modality] = {
                        Definitions.BOLD_MEANS : self.__extract_network_means(data_path),
                        Definitions.DATA_PATH  : data_path
                    }

    #Runs the smooth_subjects script on the given session data path.
    def __smooth_session(self, session_object: Session.Session, smoothing_amount: float, force_smoothing: bool) -> None:
        #First check if smoothing has been set for this session.

        session_id = session_object.data[Definitions.SESSION_ID]
        
        if (not force_smoothing) and (session_object.data[Definitions.BOLD_BPASS_SMOOTHING] or session_object.data[Definitions.BOLD_RESID_SMOOTHING]):
            print(f'It appears that smoothing has already been performed for the session {session_id}. Skipping...')
            return
        
        #Otherwise we need to smooth the subject.
        print(f'Smoothing session {session_id}...')
        functional_volume_path = os.path.join(session_object.data[Definitions.DATA_PATH], 'Functional/Volume')
        sub_ses = os.path.basename(session_object.data[Definitions.DATA_PATH])

        smoothing_value_format = str(smoothing_amount).rstrip('0').rstrip('.')
        smoothing_sigma = smoothing_amount / 2.3548 

        smoothing_types = {
            Definitions.BOLD_BPASS_SMOOTHING : f'{sub_ses}_rsfMRI_uout_bpss_resid',
            Definitions.BOLD_RESID_SMOOTHING : f'{sub_ses}_rsfMRI_uout_resid_bpss'
        }

        smoothing_applied = []

        current_dir = os.getcwd()

        for smoothing_type in smoothing_types:
            name = smoothing_types[smoothing_type]
            if os.path.isfile(os.path.join(functional_volume_path, f'{name}.nii.gz')):
                os.chdir(functional_volume_path)
                
                command_string = f'fslmaths {name}.nii.gz -kernel gauss {smoothing_sigma} -fmean {name}_sm{smoothing_value_format}.nii.gz'
                smoothing = subprocess.Popen(command_string.split())
                smoothing.wait()
                
                if smoothing.returncode == 0:
                    smoothing_applied.append(smoothing_type)

        os.chdir(current_dir)

        if len(smoothing_applied) == 0:
            print(f'Could not apply smoothing to {sub_ses}, make sure that all required files have been generated.')
            return
        
        #Now we need to go through the smoothing applied and updated the session objects appropriately.
        for smoothing in smoothing_applied:
            session_object.update({ smoothing : True }, True)  

    def __compute_participant_seed_corr(self,
                                        project: str,
                                        session_object: Session.Session, 
                                        seed_corr_output_dir: str,
                                        force_new_correlation: bool) -> None:

        session_id = session_object.data[Definitions.SESSION_ID]
        analysis_dict = session_object.data[Definitions.ANALYSIS]

        #First check if BOLD analysis already exists for this session.
        if ('BOLD' in analysis_dict) and (not force_new_correlation) and len(analysis_dict['BOLD']) > 0:
            print(f'It appears that correlation matrices were already found for the session {session_id}, skipping...')
            return
        
        session_data_path = session_object.data[Definitions.DATA_PATH]
        sub_ses = os.path.basename(session_data_path)
        
        #We need to find the Analysis folder.
        split_session_path = session_data_path.split(os.sep)
        project_alias_folder = os.sep.join(split_session_path[:2])
        found = False
        
        for dir in split_session_path[2:]:
            project_alias_folder += f'{os.sep}{dir}'
            if dir in self._projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ALIASES]:
                found = True
                break

        #Now see if we found the project folder.
        if not found:
            print(f'Could not find a project folder for the session {session_id}. Skipping...')
            return

        output_data_path = os.path.join(project_alias_folder, Definitions.ANALYSIS, seed_corr_output_dir)
        os.makedirs(output_data_path, exist_ok = True)
        output_data_path = os.path.join(output_data_path, f'{sub_ses}_seed_corr.mat')

        #Now we need to run the matlab script to compute the volume seed correlation.
        command_string = f'matlab -batch "Compute_Participant_Seed_Corr(\'{session_object.data[Definitions.DATA_PATH]}\',\'{output_data_path}\')"'
        
        try:
            matlab = subprocess.Popen(command_string, shell = True,  cwd = self.__analysis_utils)
            matlab.wait()
        except:
            print(f'There was an error attempting to compute participant seed correlation for session {session_id}.')
            return


        #Now check to see if the file was generated. If it was then we should add it to the session data. 
        if matlab.returncode != 0:
            print(f'There was an error attempting to compute participant seed correlation for session {session_id}.')
            return

        #Now we have for sure completed, we need to add it to the database.
        #Get the current analysis dict
        current_analysis = session_object.data[Definitions.ANALYSIS]
        if not 'BOLD' in current_analysis:
            current_analysis['BOLD'] = [ output_data_path ]
        else:
            current_analysis['BOLD'].append(output_data_path)

        session_object.update({Definitions.ANALYSIS : current_analysis}, force_update = True)

    #------------------------------ Analysis run options ------------------------------.
    #Run smoothing for a single subject/session pair.
    def run_session_smoothing(self,
                              project: str,
                              subject_id: str,
                              session_id: str,
                              smoothing_amount: float,
                              force_smoothing: bool) -> None:

        subject_object = Subject.Subject(self._projects_data, self._database, project)
        subject_object.load_by_map_id(subject_id, False)
        
        session_object = subject_object.get_session_by_session_id(session_id)

        if session_object == None:
            print(f'The session_id {session_id} cannot be loaded for subject {subject_id}, skipping ...')
            return

        #Now smooth the session.
        self.__smooth_session(session_object, smoothing_amount, force_smoothing)
    
    #Run smoothing for a single subject/session pair.
    def run_subjects_smoothing(self,
                               project: str,
                               subject_ids: str,
                               smoothing_amount: float,
                               force_smoothing: bool) -> None:

        subject_object = Subject.Subject(self._projects_data, self._database, project)
        for map_id in subject_ids:
            subject_object.load_by_map_id(map_id, False)

            for session_uid in subject_object.sessions:
                session_object = subject_object.sessions[session_uid]
                if Definitions.PARTICIPANTS in session_object.data[Definitions.DATA_PATH]:
                    self.__smooth_session(session_object, smoothing_amount, force_smoothing)
                
            subject_object.clear()
        

    def run_project_smoothing(self,
                              project: str,
                              smoothing_amount: float,
                              force_smoothing: bool) -> None:

        default_print = builtins.print
        builtins.print = lambda *args, **kwargs: tqdm.tqdm.write(" ".join(map(str, args)))

        for subject_object in tqdm.tqdm(self._generate_subject_by_project(project, False), 
                                        desc = f'Running gaussian smoothing for project {project}',
                                        total = self._get_total_subjects_in_project(project)):
            
            #Go through each session, check that the session is in Participants and if so try to run the smoothing.
            for session_uid in subject_object.sessions:
                session_object = subject_object.sessions[session_uid]
                if Definitions.PARTICIPANTS in session_object.data[Definitions.DATA_PATH]:
                    self.__smooth_session(session_object, smoothing_amount, force_smoothing)

            subject_object.clear()

        builtins.print = default_print

    def run_session_seed_corr(self,
                              project: str,
                              subject_id: str,
                              session_id: str,
                              seed_corr_output_dir: str,
                              force_seed_corr: bool) -> None:

        subject_object = Subject.Subject(self._projects_data, self._database, project)
        subject_object.load_by_map_id(subject_id, False)
        
        session_object = subject_object.get_session_by_session_id(session_id)

        if session_object == None:
            print(f'The session_id {session_id} cannot be loaded for subject {subject_id}, skipping ...')
            return

        #Now compute the seed correlation matrix.
        #Figure out the data path.
        self.__compute_participant_seed_corr(project, session_object, seed_corr_output_dir, force_seed_corr)
    
    def run_subjects_seed_corr(self,
                               project: str,
                               subject_ids: str,
                               seed_corr_output_dir: str,
                               force_seed_corr: bool) -> None:

        subject_object = Subject.Subject(self._projects_data, self._database, project)
        for map_id in subject_ids:
            subject_object.load_by_map_id(map_id, False)

            for session_uid in subject_object.sessions:
                session_object = subject_object.sessions[session_uid]
                if Definitions.PARTICIPANTS in session_object.data[Definitions.DATA_PATH]:
                    self.__compute_participant_seed_corr(project, session_object, seed_corr_output_dir, force_seed_corr)

                subject_object.clear()

    def run_project_seed_corr(self,
                              project: str,
                              seed_corr_output_dir: str,
                              force_seed_corr: bool) -> None:

        default_print = builtins.print
        builtins.print = lambda *args, **kwargs: tqdm.tqdm.write(" ".join(map(str, args)))

        for subject_object in tqdm.tqdm(self._generate_subject_by_project(project, False), 
                                        desc = f'Generating seed correlation matrices for project {project}',
                                        total = self._get_total_subjects_in_project(project)):
            
            #Go through each session, check that the session is in Participants and if so try to run the smoothing.
            for session_uid in subject_object.sessions:
                session_object = subject_object.sessions[session_uid]
                if Definitions.PARTICIPANTS in session_object.data[Definitions.DATA_PATH]:
                    self.__compute_participant_seed_corr(project, session_object, seed_corr_output_dir, force_seed_corr)

            subject_object.clear()
        
        builtins.print = default_print

    def run_project_BOLD_post_proc(self,
                                   project: str,
                                   smoothing_amount: float,
                                   seed_corr_output_dir: str,
                                   force_analysis: bool) -> None:
        
        self.run_project_smoothing(project, smoothing_amount, force_analysis)
        self.run_project_seed_corr(project, seed_corr_output_dir, force_analysis)

    
    #------------------------------ Report options ------------------------------
    def get_subject_network_means_report(self,
                                         project     : str,
                                         subject_ids : list,
                                         report_path : str) -> None:
        all_data = {}
        #Create the subject object.
        subject_object = Subject.Subject(self._projects_data, self._database, project)
        
        for map_id in subject_ids:
            subject_object.load_by_map_id(map_id, False)
            self.__add_subject_to_analysis_dict(subject_object, all_data)
            subject_object.clear()
        
        #Now save the report.
        result = CustomFlatten.dict_to_dataframe(all_data)

        result.to_csv(report_path, index = False)
    
    def get_project_network_means_report(self,
                                         project     : str,
                                         report_path : str) -> None:
        all_data = {}
        
        default_print = builtins.print
        builtins.print = lambda *args, **kwargs: tqdm.tqdm.write(" ".join(map(str, args)))
        
        for subject_object in tqdm.tqdm(self._generate_subject_by_project(project, False), 
                                        desc = f'Extracting network means for project {project}',
                                        total = self._get_total_subjects_in_project(project)):

            self.__add_subject_to_analysis_dict(subject_object, all_data)
            subject_object.clear()
        
        builtins.print = default_print

        #Now save the report.
        result = CustomFlatten.dict_to_dataframe(all_data)

        result.to_csv(report_path, index = False)

