import os
import pandas

import src.Subject as Subject
import src.Utils.CustomFlatten as CustomFlatten
import src.DataExtraction as DataExtraction
import src.DataModels.Definitions as Definitions
import src.Utils.ParseCSV as ParseCSV
import src.Utils.DatabaseManager as DBM

class ProjectManager(DBM.DatabaseManager):
    def __init__(self, database_name: str, deep_search = False, extend_reports = False) -> None:

        super().__init__(database_name)

        self.__extend_reports = extend_reports
        self.__deep_search = deep_search
        

    #Finds all the dirs that are named sub-x_ses-y and compiles them into a list.
    def __find_subject(self, root_dir: str, target_subject_id: str) -> tuple:
        #All paths used in this function should be absolute so that
        #we dont have to worry about dealing with pushing and popping paths. 
        def recursively_find_sub_ses(current_dir: str) -> list:
            #Switch the directory to the one we are looking in.
            os.chdir(current_dir)

            #Get the immediate subdirectories.
            dirs = [ child for child in os.listdir() if os.path.isdir(child) ]
            
            #If there are no more directories to look in return an empty list and dont:
            #recurse anymore.
            if len(dirs) == 0:
                return []

            matching = []
            found_match = False
            for dir in dirs:
                if 'sub' in dir and 'ses' in dir:
                    found_match = True
                    if DataExtraction.guess_map_id_from_path(dir) == target_subject_id:
                        matching.append(os.path.abspath(dir))

            #Now if we have found some subject sessions return those.
            if not self.__deep_search and found_match:
                return matching

            #Otherwise we need to keep looking.
            found_files = matching.copy()
            for dir in dirs:
                
                #Exclude dirs that we already meet our criteria, we dont need to search them.
                if dir in matching:
                    continue

                os.chdir(current_dir) #Make sure we are at the right dir.
                found_files += recursively_find_sub_ses(os.path.abspath(dir))
            
            return found_files
        
        def find_all_analysis_files(current_dir: str) -> list:

            os.chdir(current_dir)

            analysis_files = [] 
            dirs =  []

            #Now go through all the children and sort them based on their type:
            for child in os.listdir():
                if os.path.isdir(child):
                    dirs.append(os.path.abspath(child))
                    continue
                
                #Otherwise check if it meets the analysis criteria.
                for modality in Definitions.ANALYSIS_FILE_TYPES:
                    meets_file_type = False
                    meets_extension = False
                    
                    for criteria in Definitions.ANALYSIS_FILE_TYPES[modality]:
                        if criteria in child and target_subject_id in child:
                            meets_file_type = True
                            break
                    
                    for ext in Definitions.ANALYSIS_FILE_EXTENSIONS[modality]:
                        if child.endswith(ext):
                            meets_extension = True
                            break

                    if meets_file_type and meets_extension:
                        analysis_files.append(os.path.abspath(child))
                        break

            #Now go through each of the found directories and add all the other found files.
            for dir in dirs:
                os.chdir(current_dir)
                analysis_files += find_all_analysis_files(dir)

            return analysis_files

        print(f'Finding all subject/session pairs starting at root dir: {root_dir} matching {target_subject_id} ...')
        alias_dir    = os.path.join(self._projects_dir, root_dir)
        analysis_dir = os.path.join(alias_dir, Definitions.ANALYSIS)
        current_dir  = os.getcwd()

        all_sub_ses  = recursively_find_sub_ses(alias_dir)
        
        print(f'Finding all analysis files starting at root dir: {root_dir} matching {target_subject_id} ...')
        all_analysis = find_all_analysis_files(analysis_dir)

        os.chdir(current_dir)
            
        print(f'Done finding subject/session pairs at root dir: {root_dir} matching {target_subject_id}')

        return (all_sub_ses, all_analysis)

    #Finds all the dirs with the name sub-x_ses-y and returns their paths.
    #Finds all analysis files in a project alias as well. Assumes these are located in the Analysis folder.
    def __find_all_sub_ses(self, project_dir: str) -> tuple:
        #All paths used in this function should be absolute so that
        #we dont have to worry about dealing with pushing and popping paths. 
        def recursively_find_sub_ses(current_dir: str, depth: int) -> list:
            
            #First check if we have maxed out our depth.
            if depth == Definitions.MAXIMUM_SEARCH_DEPTH:
                return []
           
            #Switch the directory to the one we are looking in.
            os.chdir(current_dir)

            #Get the immediate subdirectories.
            dirs = [ child for child in os.listdir() if os.path.isdir(child) ]
            
            #If there are no more directories to look in return an empty list and dont:
            #recurse anymore.
            if len(dirs) == 0:
                return []

            matching = []
            for dir in dirs:
                if 'sub' in dir and 'ses' in dir:
                    matching.append(os.path.abspath(dir))

            #Now if we have found some subject sessions return those.
            if len(matching) > 0 and not self.__deep_search:
                return matching

            #Otherwise we need to keep looking.
            found_sub_ses = matching
            for dir in dirs:
                os.chdir(current_dir) #Make sure we are at the right dir.
                found_sub_ses += recursively_find_sub_ses(os.path.abspath(dir), depth + 1)
            
            return found_sub_ses

        def find_all_analysis_files(current_dir: str, depth: int) -> list:

            #First check if we have maxed out our depth.
            if depth == Definitions.MAXIMUM_SEARCH_DEPTH:
                return []

            os.chdir(current_dir)

            analysis_files = [] 
            dirs =  []

            #Now go through all the children and sort them based on their type:
            for child in os.listdir():
                if os.path.isdir(child):
                    dirs.append(os.path.abspath(child))
                    continue
                
                #Otherwise check if it meets the analysis criteria.
                for modality in Definitions.ANALYSIS_FILE_TYPES:
                    meets_file_type = False
                    meets_extension = False
                    
                    for criteria in Definitions.ANALYSIS_FILE_TYPES[modality]:
                        if criteria in child:
                            meets_file_type = True
                            break
                    
                    for ext in Definitions.ANALYSIS_FILE_EXTENSIONS[modality]:
                        if child.endswith(ext):
                            meets_extension = True
                            break

                    if meets_file_type and meets_extension:
                        analysis_files.append(os.path.abspath(child))
                        break

            #Now go through each of the found directories and add all the other found files.
            for dir in dirs:
                os.chdir(current_dir)
                analysis_files += find_all_analysis_files(dir, depth + 1)

            return analysis_files

        #Ensure that we keep executing at the correct location in the filesystem. 
        print(f'Finding all subject/session pairs starting at root dir: {project_dir}...')

        alias_dir    = os.path.join(self._projects_dir, project_dir)
        analysis_dir = os.path.join(alias_dir, Definitions.ANALYSIS)
        current_dir  = os.getcwd()

        all_sub_ses  = recursively_find_sub_ses(alias_dir, 0)
        
        print(f'Finding all analysis files starting at root dir: {project_dir} ...')
        all_analysis = find_all_analysis_files(analysis_dir, 0)

        os.chdir(current_dir)

        print(f'Done finding subject/session pairs at root dir: {project_dir}')

        return (all_sub_ses, all_analysis)
        
    #The point of this function is to take a list of all found sources and organize them.
    #The following is the organizational structure which will be used:
    #   -project_name
    #       -subject
    #           +path to sources (list)
    def __consolidate(self, sub_ses_list: list) -> dict:
        sorted = {}

        for sub_ses_path in sub_ses_list:
            map_id  = DataExtraction.guess_map_id_from_path(sub_ses_path)
            
            #Check if an error has occured and something couldnt be guessed from the path.
            if map_id == -1:
                print(f'Could not infer all required information from the path {sub_ses_path}, skipping...')
                continue
            
            #Check if the map_id has been added to sorted.
            if not map_id in sorted:
                #Add the map id with the path to the project.
                sorted[map_id] = [
                    sub_ses_path
                ]
                continue
            
            #Finally if the project and map id were found then just add the path to the
            #map_ID entry
            sorted[map_id].append(sub_ses_path)

        return sorted

    def __concatenate_dataframe_with_separation(self, 
                                                original_df: pandas.DataFrame, 
                                                new_dataframe: pandas.DataFrame, 
                                                separate_subjects: bool) -> pandas.DataFrame:
        #Check that anything is being added.
        if new_dataframe.empty:
            return original_df

        to_concat = []
        if separate_subjects:
            empty_row = pandas.DataFrame(None, index = [0], columns = original_df.columns)
            to_concat = [original_df, empty_row, new_dataframe]
        else:
            to_concat = [original_df, new_dataframe]

        return pandas.concat(to_concat)
    

    def __get_duplicate_sessions_dataframe_by_project(self, project: str, separate_subjects: bool) -> pandas.DataFrame:
        result = pandas.DataFrame()

        if not project in self._projects_data[Definitions.PROJECTS]:
            print(f'Could not find the project {project} in ProjectsData. Ensure that this is a real project and has been specified correctly.')
            return result 
        
        for subject in self._generate_subject_by_project(project, self.__extend_reports):
            subject_df = subject.get_expanded_duplicate_dataframe()

            result = self.__concatenate_dataframe_with_separation(result, subject_df, separate_subjects)
       
        return result

    def __get_sessions_by_status_in_project(self, project: str, status:str, separate_subjects: bool) -> pandas.DataFrame:
        result = pandas.DataFrame()

        if not project in self._projects_data[Definitions.PROJECTS]:
            print(f'Could not find the project {project} in ProjectsData. Ensure that this is a real project and has been specified correctly.')
            return result 
        
        for subject in self._generate_subject_by_project(project, self.__extend_reports):
            expanded_data = subject.get_expanded_data()
            
            to_keep = []
            for session in expanded_data[Definitions.SESSION_DATA]:
                try:
                    if expanded_data[Definitions.SESSION_DATA][session][Definitions.PROC_STATUS].lower() == status:
                        to_keep.append(session)
                except KeyError:
                    print(f'Could not find the field "processing_status" for subject {str(session["_id"])}, skipping...')

            #Remove unwanted sessions.
            to_remove = set(expanded_data[Definitions.SESSION_DATA].keys()) - set(to_keep)
            for key in to_remove:
                del expanded_data[Definitions.SESSION_DATA][key]

             
            subject_df = CustomFlatten.dict_to_dataframe(expanded_data, exclude_columns = [ Definitions.DUPLICATES,
                                                                                            Definitions.LONGITUDINAL])

            result = self.__concatenate_dataframe_with_separation(result, subject_df, separate_subjects)
       
        return result

    #----------------- Update, Build, and Duplicate detection functions ------------------
    def update_subjects(self, 
                        project: str, 
                        map_ids: list, 
                        prompt_missing_data: bool,
                        force_update: bool) -> None:

        subject = Subject.Subject(self._projects_data, self._database, project)
        for id in map_ids: 
            #Find all the paths that are associated with this subject.
            subject_data_paths = []
            subject_analysis   = []
            for project_alias in self._projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ALIASES]:
                session_folders, analysis_files = self.__find_subject(project_alias, id)
                subject_data_paths += session_folders
                subject_analysis   += analysis_files

            subject.load_by_map_id(id, self.__extend_reports)
            subject.update(id, subject_data_paths, subject_analysis, {}, force_update)
            subject.prompt(prompt_missing_data, force_update)
            subject.clear()

    #This function builds the full DB for every subject and session relating to a project 
    #If a subject does exist then it updates that subjects data. If a subject does not exist 
    #then it creates it.
    def build_project_alias(self, 
                            project: str, 
                            project_alias: str,
                            prompt_missing_data: bool,
                            force_update: bool,
                            consolidated = None) -> None:

        #Now consolidate the information into the project, session, path format.
        consolidated_sub_ses  = None
        consolidated_analysis = None

        if consolidated == None:
            all_sub_ses, all_analysis = self.__find_all_sub_ses(project_alias)
            try:
                consolidated_sub_ses = self.__consolidate(all_sub_ses)
                consolidated_analysis = self.__consolidate(all_analysis)
            except KeyError:
                print(f'There was an error trying to build the project alias {project_alias}. Skipping...')
                return
        else:
            consolidated_sub_ses, consolidated_analysis = consolidated
        
        #Initialize the subject object.
        subject = Subject.Subject(self._projects_data, self._database, project)
        #Now lets go through each subject and update them.
        for map_id in consolidated_sub_ses:
            analysis_files = []
            if map_id in consolidated_analysis:
                    analysis_files = consolidated_analysis[map_id]

            subject.load_by_map_id(map_id, self.__extend_reports)
            subject.update(map_id, consolidated_sub_ses[map_id],analysis_files ,{}, force_update)
            subject.prompt(prompt_missing_data, force_update)
            subject.clear()
        
        print(f'Completed building project alias {project_alias}')
         

    #This function builds the full DB for every subject and session relating to a project 
    #If a subject does exist then it updates that subjects data. If a subject does not exist 
    #then it creates it.
    def build_project(self, 
                      project: str, 
                      prompt_missing_data: bool,
                      force_update: bool,
                      consolidated = None) -> None:

        for project_alias in self._projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ALIASES]:
            self.build_project_alias(project, project_alias, prompt_missing_data, force_update, consolidated)

    #This function builds the full DB for every subject and session relating to a project 
    #If a subject does exist then it updates that subjects data. If a subject does not exist 
    #then it creates it.
    def build_all_projects(self,
                           prompt_missing_data: bool,
                           force_update: bool) -> None:

        for project in self._projects_data[Definitions.PROJECTS]:
            self.build_project(project, prompt_missing_data, force_update)
            print(f'Done building project: {project}')

    def update_project_alias(self,
                             project: str,
                             project_alias: str,
                             prompt_missing_data: bool,
                             force_update: bool) -> None:

        all_sub_ses, all_analysis = self.__find_all_sub_ses(project_alias)

        #Now consolidate the information into the project, session, path format.
        try:
            consolidated_sub_ses = self.__consolidate(all_sub_ses)
            consolidated_analysis = self.__consolidate(all_analysis)

        except KeyError:
            print(f'There was an error trying to build the project alias {project_alias}. Skipping...')
            return

        found_ids = set(consolidated_sub_ses.keys())
    
        #Now build the project for all the found keys.
        self.build_project_alias(project,
                                 project_alias,
                                 prompt_missing_data,  
                                 force_update, 
                                 consolidated = (consolidated_sub_ses, consolidated_analysis))
        
        #Now go through all the ids that werent touched by the build procecss and check that they still exist.
        not_modified = set(self._database[project].distinct(Definitions.MAP_ID)) - found_ids
        
        subject = Subject.Subject(self._projects_data, self._database, project)
        for map_id in not_modified:
            if subject.load_by_map_id(map_id, self.__extend_reports):
                subject.check_fs_existance()

    
    #This function is very similar to the build_project function. The only difference is that it
    #also scans through the file system at the project level and updates all subjects, not just those that were found
    #(removes data that no longer exists).
    def update_project(self, 
                       project: str,
                       prompt_missing_data: bool,
                       force_update: bool) -> None:

        for project_alias in self._projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ALIASES]:
            self.update_project_alias(project, project_alias, prompt_missing_data, force_update)
        
    
    def update_all_projects(self,
                            prompt_missing_data: bool,
                            force_update: bool) -> None:

        for project in self._projects_data[Definitions.PROJECTS]:
            self.update_project(project, prompt_missing_data, force_update)
            print(f'Done updating project: {project}')

    def update_accession_values_from_csv(self,
                                         project               : str,
                                         update_csv            : str,
                                         id_col                : str,
                                         id_accession_col      : str,
                                         session_col           : str,
                                         session_accession_col : str,
                                         fs_accession          : str,
                                         force_update          : bool) -> None:

        csv_parser = ParseCSV.ParseCSV(update_csv, '')
        
        if not csv_parser.check_header_existance(id_col):
            return

        #Check that not everything is unset.
        if (not csv_parser.check_header_existance(id_accession_col)      and 
            not csv_parser.check_header_existance(session_col)           and 
            not csv_parser.check_header_existance(session_accession_col) and 
            not csv_parser.check_header_existance(fs_accession)):

            print('All columns are not specified, no work to do.')
            return

        if not (csv_parser.check_header_existance(session_col) and csv_parser.check_header_existance(session_accession_col)):
            print('Both the session ID and session accession column must be specified.')
            return

        if not (csv_parser.check_header_existance(session_col) and csv_parser.check_header_existance(fs_accession)): 
            print('Both the session ID and fs accession column must be specified.')
            return
        
        print(f'Updating {len(csv_parser.row_data)} entries.')
        #Go through each row in the update_csv and get the subjects from each row.
        for id, id_accession, session, session_accession, fs_id in csv_parser.generate_csv_data((id_col, 
                                                                                                 id_accession_col, 
                                                                                                 session_col, 
                                                                                                 session_accession_col, 
                                                                                                 fs_accession)):

            subject_object = Subject.Subject(self._projects_data, self._database, project)
            if not subject_object.load_by_map_id(id, self.__extend_reports):
                print(f'Could not load in the participant: {id}, skipping...')
                continue
        
            if id_accession != None:
                subject_object.update_metadata({Definitions.SUBJECT_ACCESSION: id_accession}, force_update)


            if session == None:
                continue

            #Otherwise update all other session specific info.
            session_object = subject_object.get_session_by_session_id(session)

            if session_object == None:
                print(f'Could not load in the session: {session} for participant {id}, skipping...')
                continue

            session_object.update({
                                      Definitions.SESSION_ACCESSION : session_accession,
                                      Definitions.FS_ACCESSION      : fs_id
                                  },
                                  force_update)

        #Now go through and update duplicate information.
        print(f'Updating all duplicate entries in project {project}.')
        for subject in self._generate_subject_by_project(project, self.__extend_reports):
            subject.update_duplicate_accession(force_update)


    #----------------- Report functions ------------------
    def get_project_wide_report(self, 
                                project: str, 
                                report_path: str, 
                                separate_subjects: bool) -> None:

        result = pandas.DataFrame()
        
        #Create a subject object to use to load and generate data.
        subject = Subject.Subject(self._projects_data, self._database, project)
        
        #Get all the uids in the given project.
        uids = self._database[project].distinct('_id')

        for uid in uids:
            subject.load_by_uid(uid, self.__extend_reports)
            subject_df = subject.get_expanded_dataframe()
            result = self.__concatenate_dataframe_with_separation(result, subject_df, separate_subjects)
            subject.clear()

        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)

    #Given the project to look in, the map_ids to look for, and a path to save the report to,
    def get_subject_report_by_map_ids(self, 
                                      project: str, 
                                      map_ids: list, 
                                      report_path: str,
                                      separate_subjects: bool) -> None:

        result = pandas.DataFrame()
        subject = Subject.Subject(self._projects_data, self._database, project)
        
        for map_id in map_ids:
            subject.load_by_map_id(map_id, self.__extend_reports)
            subject_df = subject.get_expanded_dataframe()
            subject.clear()

            result = self.__concatenate_dataframe_with_separation(result, subject_df, separate_subjects)

        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)

    #Gets information about a subject by, project, map ID, and session ID. Additionally takes a
    #fuzzy level parameter which specifies how far away the session id can be to be considered a match (0
    #is an exact match and higher is less strict.)
    def get_subject_report_by_sub_ses(self, project: str, map_id: str, sess_id: str, report_path: str, fuzzy_level) -> None:
        #create a new dataframe 
        #Load in the subject.
        subject = Subject.Subject(self._projects_data, self._database, project)

        subject.load_by_map_id(map_id, self.__extend_reports)
    
        result = subject.get_session_dataframe_by_session_id(sess_id, fuzzy_level)
        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)

    def get_duplicate_sessions_report_by_project(self, project: str, report_path: str, separate_subjects: bool) -> None:

        result = self.__get_duplicate_sessions_dataframe_by_project(project, separate_subjects)
        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)
    
    def get_all_duplicate_sessions_report(self, report_path: str, separate_subjects: bool) -> None:
        result = pandas.DataFrame()

        for project in self._projects_data[Definitions.PROJECTS]:
            result = pandas.concat([result, self.__get_duplicate_sessions_dataframe_by_project(project, separate_subjects)])
        
        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)
                
    #Generate a report which gets all the subjects which match a given processing status. 
    def get_project_report_by_processing_status(self, 
                                                project: str, 
                                                proc_status: str, 
                                                report_path: str,
                                                separate_subjects: bool) -> None:
        #Check that the given processing status is an option defined in the projects_data.
        valid_status = list(self._projects_data[Definitions.NAMING_CONVENTIONS][Definitions.ALLOWED_PROC_STATUSES].values())

        found_status = False
        for status in valid_status:
            if status.lower() == proc_status.lower():
                found_status = True
                break
        
        if not found_status:
            print(f'The processing status "{proc_status}" was not matched to any of the options defin in ProjectsInfo: {valid_status}')
            return

        result = self.__get_sessions_by_status_in_project(project, proc_status.lower(), separate_subjects)
        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)

    
    def get_all_processing_status_report(self, 
                                         proc_status: str, 
                                         report_path: str, 
                                         separate_subjects: bool) -> None:
        
        result = pandas.DataFrame()
        #Iterate through each project and generate the report that way.
        for project in list(self._projects_data[Definitions.PROJECTS].keys()):
            result = pandas.concat([result, self.__get_sessions_by_status_in_project(project, proc_status.lower(), separate_subjects)])
            print(f'Done searching {project}.')

        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)
    
    #Generate a csv report which details
    def get_session_link_mapping(self,
                                 project: str,
                                 report_path: str) -> None:
        
        linked_data = {
            Definitions.SOURCE_DIR : [],
            Definitions.LINKED     : [],
        }

        print(f'Finding all scan sources for project {project}')
        scan_sources = list(self._projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS].keys())
        
        session_source_dirs = {}
        #Now we need to search each scan source for subject/session information.
        for scan_source in scan_sources:
            raw_data_dir = os.path.join(self._scans_dir, scan_source, Definitions.RAW_DATA)
            scan_dir = raw_data_dir if os.path.isdir(raw_data_dir) else os.path.join(self._scans_dir, scan_source)
            
            subjects = []
            #Now that we have determined the raw_data_dir we need to search in this scan_dir for all the subject folders.
            for child in os.listdir(scan_dir):
                if os.path.isdir(os.path.join(scan_dir, child)) and child.startswith('sub'):
                    session_source_dirs[child] = []
                    subjects.append(child)

            for subject in subjects:
                subject_dir = os.path.join(scan_dir, subject)
                for child in os.listdir(subject_dir):
                    data_path = os.path.join(scan_dir, subject, child)
                    if os.path.isdir(data_path) and child.startswith('ses'):
                        session_source_dirs[subject].append(data_path)

        #Now we need to find every subject/session pair in the entire project.
        print(f'Finding all session paths for project {project}')
        all_sub_ses = []
        for project_alias in self._projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ALIASES]:
            sub_ses, _ = self.__find_all_sub_ses(project_alias)
            all_sub_ses += sub_ses

        
        #Now transform all the found sessions into a consolidated list.
        consolidated = self.__consolidate(all_sub_ses)
        #Build up the report based on this info.
        for subject in session_source_dirs:
            for session in session_source_dirs[subject]:
                sub_ses = f'{subject}_{os.path.basename(session)}'

                #Try to associate the session to one of the source sessions.
                found_linked_session = ''
                candidate_key = subject.replace('sub-','')
                if candidate_key in consolidated:
                    for candidate in consolidated[candidate_key]:
                        if candidate.endswith(sub_ses):
                            found_linked_session = candidate
                            break
                
                linked_data[Definitions.SOURCE_DIR].append(session)
                linked_data[Definitions.LINKED].append(found_linked_session)

        result = pandas.DataFrame.from_dict(linked_data)
        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False) 
        
