import os
import pandas
from csv import DictReader

import src.DataModels.Definitions as Definitions
import src.DataModels.ColumnNames as ColumnNames
import src.DataModels.AnalysisDefinitions as AnalysisDefinitions

import src.Subject as Subject
import src.Utils.CustomFlatten as CustomFlatten
import src.DataExtraction as DataExtraction
import src.Utils.DatabaseManager as DBM
import src.XNATQueryManager as QM

class ProjectManager(DBM.DatabaseManager):
    '''The main data management driver for ProjectManager.
    
    This class deals primarily with the mongoDB database. It is responsible for both updating data in the database 
    based on local and remote data sources and extracting data from that database and presenting that data in a 
    readable way.

    Attributes:
        __extend_reports (bool) : A flag which specifies if additional filesystem data (which is not stored) in
                                  the database should be included in report data.
        __deep_search    (bool) : A flag which specifies if the depth of sub/ses searches should stop whenever a 
                                  sub/ses folder.
        __remote_data    (dict) : This stores data fetched by the XNATQueryManager class into a structured format 
                                  which can be adjoined to local session data. The structure of this dictionary is as
                                  follows:  
                                  __remote_data:
                                      "cnda_subject_accession 1" :
                                          "cnda_session_accession 1" : 
                                              queried data...
                                          ...
                                      ...
    '''

    def __init__(self, 
                 database_name: str, 
                 project : str,
                 logger: str,
                 deep_search = False, 
                 extend_reports = False, 
                 adjoin_remote_data = False,
                 show_remote_id_cols = False,
                 server = 'https://cnda.wustl.edu/') -> None:
        '''Initialize the project manager class.

        Set internal data attributes. If adjoin_remote_data is set then query xnat with the XNATQueryManager and
        store the data in the __remote_data attribute.

        Parameters:
            database_name       (str)  : The name of the database to connect to.
            project             (str)  : The name of the project to perform operations on.
            logger              (str)  : The path to a logging file.
            deep_search         (bool) : A flag specifying if a deep search should be performed or not.
            extend_reports      (bool) : A flag specifying if additional local data should be concatenated to database 
                                         query data.
            adjoin_remote_data  (bool) : A flag specifying if remote data should be concatenated to database query
                                         data.
            show_remote_id_cols (bool) : A flag specifying if remote data id columns (used to match database 
                                         information) should be included in local reports.
            server              (str)  : The link to the xnat server to extract data from.
        '''
        
        super().__init__(database_name, project, logger)

        self.__extend_reports = extend_reports
        self.__deep_search = deep_search
        
        self.__remote_data = {}
        if adjoin_remote_data:
            user_name = input(f'Please enter the user name for {server}: ')

            #Currently the query_manager itself doesnt have a log file, would have to do a more robust way to handle
            #passing over the logging to this object to make this work.
            query_manager = QM.XNATQueryManager(database_name, server, user_name, project, log_file = None) 

            #Now get the remote data from the xnat server.
            self.__remote_data = query_manager.get_remote_extended_query(show_remote_id_cols)

    def __check_for_remote_data(self, subject_accession: str) -> bool:
        '''Check if remote data aquired from xnat has been specified for a particular subject.
        
        Returns T/F depending on the status of __remote_data.

        Parameters:
            subject_accession (str) : The subject accession for the remote data in question.

        Returns:
            exists (bool) : If remote data exists for the given subject accession value.
        '''

        if self.__remote_data == {}:
            return False

        return subject_accession in self.__remote_data
        
  
    def __create_file_folder_list(self, 
                                  start_dir: str, 
                                  search_type: str, 
                                  contains = [], 
                                  endswith = [], 
                                  find_subject_id = '') -> list:
        '''Used to find all sub/ses folders or analysis files at a given directory.
        
        Uses os.walk to search for files or dirs based on the contains or endswith criteria. If __deep_search is false 
        then stop os.walk will stop at at the level that the first match was found, otherwise os.walk will continue 
        until all possible files are found.

        Parameters:
            start_dir        (str)       : The path to the root directory to start at.
            search_type      (str)       : Either 'file' or 'dir'. Determines if the search will look for dirs or 
                                           files.
            contains         (list[str]) : A list of substrings that a match must contain. All substrings must be 
                                           found.
            endswith         (list[str]) : A list of substrings that a match must additionally end with. Only one of 
                                           the candidates must be present.
            find_subject_id (str)        : A subject_id the match must contain.

        Returns:
            final_match (list[str]) : A list of absolute paths that match the criteria.
        '''

        sub_ses_set = set()
        if search_type not in ['dir', 'file']:
            raise NotImplementedError

        for walk_tup in os.walk(start_dir):
            root = walk_tup[0]
            search_list = walk_tup[1] if search_type == 'dir' else walk_tup[2]

            if len(contains) == 0:
                match_contains = search_list
            else:
                match_contains = []
                for path in search_list:
                    if all(sub_string in path for sub_string in contains):
                        match_contains.append(path)

            final_match = match_contains if len(endswith) == 0 else [
                candidate for candidate in match_contains if any(candidate.endswith(sub_string) for sub_string in endswith)
            ]

            if find_subject_id:
                final_match = [
                    candidate for candidate in final_match if DataExtraction.guess_map_id_from_path(candidate) == find_subject_id
                ]

            if search_type == 'dir':
                search_list[:] = [path for path in search_list if path not in final_match]

            if self.__deep_search:
                search_list.clear()

            for path in final_match:
                sub_ses_set.add(os.path.join(root, path))

        return sub_ses_set

    def __find_sub_ses(self, project_dir: str, target_subject_id = '', find_analysis = True) -> tuple:
        '''Used to find all sub/ses folders and analysis files for a given project.
        
        Leverages the __create_file_folder_list function to generate the file lists. 

        Parameters:
            project_dir       (str)  : The directory to the project alias folder in the UNP projects folder.
            target_subject_id (str)  : If we are only searching for a specific subject_id then it should be specified
                                       here. If empty then just find all sub/ses folders.
            find_analysis     (bool) : Flag to determine if analysis files specified in AnalysisDefinitions should be
                                       included.
        Returns:
            result (tuple[list[str], list[str]]) : A tuple of two sets. The first being all the sub/ses paths found
                                                   at the project alias and the second being an optional set of all 
                                                   analysis files (if find_analysis is True).
        '''

        #Ensure that we keep executing at the correct location in the filesystem. 
        self.log(f'Finding all subject/session pairs starting at root dir: {project_dir}...')

        alias_dir    = os.path.join(self._projects_dir, project_dir)
        analysis_dir = os.path.join(alias_dir, AnalysisDefinitions.ANALYSIS)
        current_dir  = os.getcwd()
        
        #Exclude the analysis folder.
        all_sub_ses = set()
        for f in os.listdir(alias_dir):
            if os.path.isdir(os.path.join(alias_dir, f)) and (not AnalysisDefinitions.ANALYSIS in f):
                all_sub_ses |= self.__create_file_folder_list(os.path.join(alias_dir, f), 'dir', contains=['sub','ses'], find_subject_id=target_subject_id)
        
        all_analysis = set()

        if find_analysis:
            self.log(f'Finding all analysis files starting at root dir: {project_dir} ...')
            
            contains = []
            endswith = []
            for analysis_type in AnalysisDefinitions.ANALYSIS_TYPES.values():
                for file_types in analysis_type.values():
                    contains += file_types['FILE_TYPE']
                    endswith += file_types['FILE_EXTENSIONS']
        
            all_analysis = self.__create_file_folder_list(analysis_dir, 'file', contains=contains, endswith=endswith)

            os.chdir(current_dir)

            self.log(f'Done finding subject/session pairs at root dir: {project_dir}')
        
        return (all_sub_ses, all_analysis)
        
    def __consolidate(self, sub_ses: set, allow_multiple=False, return_multiples=False) -> dict:
        '''Used to structure a set of paths with subject and session data included. 

        Generally used with the __find_sub_ses output (either analysis lists or sub/ses). Strucutres the list based
        on subject and session information. Additionally allows for filtering of sub/ses data based on constraints. 
        Generates the following structure:
        {
            sub_id 1 : {
                session_path_1,
                session_path_2,
                    ...
            },
            ...
        }

        Parameters:
            sub_ses          (str)  : The set to structure.
            allow_multiple   (bool) : Allow for multiple unique session paths to be consolidated together. If False then 
                                      if two unique paths are found then the subject will be skipped and paths will not  
                                      be consolidated. sub/ses folders require that only one imaging session exists in 
                                      one place for a project, otherwise there is no way to differentiate between the 
                                      sessions when they move locations on the FS.
            return_multiples (bool) : Allow multiples to be returned or not. If True then return all found paths for a
                                      given subject object. If False then just return one. Used for finding all analysis
                                      files and returning either one or all depending on the situation.
        Returns:
            result (dict[str -> set[str]]) : The resulting consolidated dictionary.
        '''

        sorted = {}
        for sub_ses_path in sub_ses:
           map_id = DataExtraction.guess_map_id_from_path(sub_ses_path)
           ses_id = DataExtraction.guess_sess_id_from_path(sub_ses_path)
           
           # Check if an error has occurred and something couldn't be guessed from the path.
           if map_id == '' or ses_id == '':
               self.log(f'Could not infer all required information from the path {sub_ses_path}, skipping...')
               continue
                
            
           # Check if the map_id has been added to sorted.
           if map_id not in sorted:
               # Add the map ID with the path to the project.
               sorted[map_id] = {sub_ses_path}
           else:
               sorted[map_id].add(sub_ses_path)

        #Finally, if the project and map ID were found, check for duplicate sessions.
        subs_to_remove = []
        for map_id, paths in sorted.items():
           
           # Build up the session index
           ses_index = {}
           for path in paths:
               session_id = DataExtraction.guess_sess_id_from_path(path)

               if session_id == '':
                   continue

               if session_id not in ses_index:
                   ses_index[session_id] = {path}
               else:
                   ses_index[session_id].add(path)

           # Remove paths with more than one entry if not allowing multiple
           for session_id, candidate_paths in ses_index.items():
               if return_multiples and len(candidate_paths) < 2:
                   #If we only want to keep entries with more than 1 path then remote everything else.          
                   paths.difference_update(candidate_paths)
               else:
                   continue

               if len(candidate_paths) > 1 and not allow_multiple:
                   #Filter out anything more than 1 path.
                   self.log(f'It appears that there were multiple conflicting sessions for the data path {path}. '
                         f'Please choose the session you want and re-add this session to PM.')
                   paths.difference_update(candidate_paths)

           # Check if any paths remain; if not, mark for removal
           if not paths:
               subs_to_remove.append(map_id)

        # Remove map_ids with no remaining paths
        for map_id in subs_to_remove:
           del sorted[map_id]

        return sorted

    def __get_duplicate_sessions_dataframe_by_project(self, include_analysis: bool, separate_subjects: bool) -> pandas.DataFrame:
        '''Create a dataframe of sessions which are duplicates.

        Parameters:
            separate_subjects (bool) : If duplicate session entries should be separated by whitespace.

        Returns:
            result (pandas.DataFrame) : The final dataframe.
        '''

        result = pandas.DataFrame()

        if not self._project in self._projects_data[Definitions.PROJECTS]:
            self.log((f'Could not find the project {self._project} in ProjectsData. '
                   'Ensure that this is a real project and has been specified correctly.'))
            return result 
        
        for subject in self._generate_subject_by_project(self.__extend_reports):

            if len(subject.data[Definitions.DUPLICATES]) == 0:
                continue
            
            sa = subject.data[ColumnNames.SUBJECT_ACCESSION]
            if self.__check_for_remote_data(sa):
                subject.set_adjoined_data(self.__remote_data[sa])
            
            subject_df = subject.get_duplicate_dataframe(include_analysis)

            result = self._concatenate_dataframe_with_separation(result, subject_df, separate_subjects)
       
        return result

    def __check_untouched_subject_ids(self, touched_sub_ids: set) -> None:
        '''Given the subject IDs that have been updated (touched), go through all untouched IDs and check for existance.

        Parameters:
            touched_sub_ids (set) : A set of all previously updated ids.
        '''

        not_modified = set(self._database[self._project].distinct(ColumnNames.PARTICIPANT_ID)) - touched_sub_ids
        
        subject = Subject.Subject(self._projects_data, self._database, self._project, self)
        for map_id in not_modified:
            if subject.load_by_map_id(map_id, self.__extend_reports):
                subject.check_fs_existance()
                subject.clear()
                

    #----------------- Update, Build, and Duplicate detection functions ------------------
    def build_project_alias(self, 
                            project_alias: str,
                            prompt_missing_data: bool,
                            force_update: bool,
                            consolidated = None) -> None:
        '''Update each found subject in a project. Does not touch unfound subjects also in the project alias.

        Parameters:
            project_alias       (str)  : The project alias to build.
            prompt_missing_data (bool) : If data cannot be found then prompt the user for it.
            force_update        (bool) : If data conflicts are found between the DB representation and incoming data 
                                         force update everything.
            consolidated        (dict) : If not None then use this list of consolidated sub/ses and analysis to build.
        '''

        #Now consolidate the information into the project, session, path format.
        consolidated_sub_ses  = None
        consolidated_analysis = None

        if consolidated == None:
            all_sub_ses, all_analysis = self.__find_sub_ses(project_alias)
            try:
                consolidated_sub_ses = self.__consolidate(all_sub_ses)
                consolidated_analysis = self.__consolidate(all_analysis, allow_multiple=True)
            except KeyError:
                self.log(f'There was an error trying to build the project alias {project_alias}. Skipping...')
                return
        else:
            consolidated_sub_ses, consolidated_analysis = consolidated
        
        #Initialize the subject object.
        subject = Subject.Subject(self._projects_data, self._database, self._project, self)
        #Now lets go through each subject and update them.
        for map_id in consolidated_sub_ses:
            analysis_files = []
            if map_id in consolidated_analysis:
                    analysis_files = consolidated_analysis[map_id]

            subject.load_by_map_id(map_id, self.__extend_reports)
            subject.update(map_id, consolidated_sub_ses[map_id],analysis_files ,{}, force_update)
            subject.prompt(prompt_missing_data, force_update)
            subject.clear()
        
        self.log(f'Completed building project alias {project_alias}')

    def build_project(self, 
                      prompt_missing_data: bool,
                      force_update: bool,
                      consolidated = None) -> None:
        '''Build a project. Go through each project alias in the specified project and run build_project_alias.

        Parameters:
            prompt_missing_data (bool) : If data cannot be found then prompt the user for it.
            force_update        (bool) : If data conflicts are found between the DB representation and incoming data 
                                         force update everything.
            consolidated        (dict) : If not None then use this list of consolidated sub/ses and analysis to build.
        '''

        for project_alias in self._projects_data[Definitions.PROJECTS][self._project][Definitions.PROJECT_ALIASES]:
            self.build_project_alias(project_alias, prompt_missing_data, force_update, consolidated)

    def update_project_alias(self,
                             project_alias: str,
                             prompt_missing_data: bool,
                             force_update: bool) -> None:
        '''Update each found subject in a project alias.

        For each sub/ses found in the given project alias update it. Then for every sub/ses not found check to see if
        they still exist. If not remove them.

        Parameters:
            project_alias       (str)  : The project alias to build.
            prompt_missing_data (bool) : If data cannot be found then prompt the user for it.
            force_update        (bool) : If data conflicts are found between the DB representation and incoming data 
                                         force update everything.
            consolidated        (dict) : If not None then use this list of consolidated sub/ses and analysis to build.
        '''

        all_sub_ses, all_analysis = self.__find_sub_ses(project_alias)

        #Now consolidate the information into the project, session, path format.
        try:
            consolidated_sub_ses = self.__consolidate(all_sub_ses)
            consolidated_analysis = self.__consolidate(all_analysis, allow_multiple=True)
        except KeyError:
            self.log(f'There was an error trying to build the project alias {project_alias}. Skipping...')
            return

        found_ids = set(consolidated_sub_ses.keys())
        
        #Now build the project for all the found keys.
        self.build_project_alias(project_alias,
                                 prompt_missing_data,  
                                 force_update, 
                                 consolidated = (consolidated_sub_ses, consolidated_analysis))
        
        #Check for the untouched subjects and if they DNE remove them from the DB.
        self.__check_untouched_subject_ids(found_ids)
        

    def update_project(self, 
                       prompt_missing_data: bool,
                       force_update: bool) -> None:
        '''Update a project. 

        Go through each project alias in the specified project and run build_project. Additionally remove all
        DB entries which do not exist anymore.

        Parameters:
            prompt_missing_data (bool) : If data cannot be found then prompt the user for it.
            force_update        (bool) : If data conflicts are found between the DB representation and incoming data 
                                         force update everything.
            consolidated        (dict) : If not None then use this list of consolidated sub/ses and analysis to build.
        '''
        
        project_iter = iter(self._projects_data[Definitions.PROJECTS][self._project][Definitions.PROJECT_ALIASES])
        all_sub_ses, all_analysis = self.__find_sub_ses(next(project_iter))

        for project_alias in project_iter:
            sub_ses, analysis = self.__find_sub_ses(project_alias)
            all_sub_ses |= sub_ses
            all_analysis |= analysis

        #Now consolidate.
        try:
            consolidated_sub_ses = self.__consolidate(all_sub_ses)
            consolidated_analysis = self.__consolidate(all_analysis, allow_multiple=True)
        except KeyError:
            self.log(f'There was an error trying to build the project alias {project_alias}. Skipping...')
            return
        
        found_ids = set(consolidated_sub_ses.keys())

        #Now build the project.
        self.build_project(prompt_missing_data, 
                           force_update, 
                           consolidated = (consolidated_sub_ses, consolidated_analysis))

        #Check for the untouched subjects and if they DNE remove them from the DB.
        self.__check_untouched_subject_ids(found_ids)

    def update_accession_values_from_csv(self,
                                         update_csv            : str,
                                         id_col                : str,
                                         id_accession_col      : str,
                                         session_col           : str,
                                         session_accession_col : str,
                                         fs_accession          : str,
                                         force_update          : bool) -> None:
        '''Given a CSV file, update subject and session entries with associated accession values.

        Parameters:
            update_csv       (str)  : The path to the csv file of interest.
            id_col           (str)  : The name of the participant id column.
            id_accession_col (str)  : The name of the participant id accession column.
            session_col      (str)  : The name of the session id column.
            session_col      (str)  : The name of the session accession column.
            fs_accession     (str)  : The name of fs accession column.
            force_update     (bool) : A flag indicating if conflicting accession values should be forced or not.
        '''

        with open(update_csv, 'r') as file:
            csv_parser = DictReader(file)

            header_cols = set(csv_parser.fieldnames)
            required = {id_col, id_accession_col, session_col, session_accession_col, fs_accession }
            
            if len(required - header_cols) != 0:
                self.log('All columns are not specified, no work to do.')
                return
            
            self.log('Updating ...')
            #Go through each row in the update_csv and get the subjects from each row.
            for row in csv_parser:
                id                = row[id_col]
                id_accession      = row[id_accession_col]
                session           = row[session_col]
                session_accession = row[session_accession_col]
                fs_id             = row[fs_accession]

                subject_object = Subject.Subject(self._projects_data, self._database, self._project, self)
                if not subject_object.load_by_map_id(id, self.__extend_reports):
                    self.log(f'Could not load in the participant: {id}, skipping...')
                    continue
            
                if id_accession != None:
                    subject_object.update_metadata({ColumnNames.SUBJECT_ACCESSION: id_accession}, force_update)


                if session == None:
                    continue

                #Otherwise update all other session specific info.
                session_object = subject_object.get_session_by_session_id(session)

                if session_object == None:
                    self.log(f'Could not load in the session: {session} for participant {id}, skipping...')
                    continue

                session_object.update({
                                          ColumnNames.SESSION_ACCESSION : session_accession,
                                          ColumnNames.FS_ACCESSION      : fs_id
                                      },
                                      force_update)

            #Now go through and update duplicate information.
            self.log(f'Updating all duplicate entries in project {self._project}.')
            for subject in self._generate_subject_by_project(self.__extend_reports):
                subject.update_duplicate_accession(force_update)

    #Zombie destroyer
    def clean_database(self) -> None:
        '''Clean up entries which no longer exist on the FS.

        Theoretically this should never have to be called. Go through every subject and check that they exist.
        If not remove the entry from the DB.
        '''
        #Simply checks that everything in the database exists and cleans up if not.
        for subject_object in self._generate_subject_by_project(False):
            subject_object.check_fs_existance()

    def wipe_metadata(self) -> None:
        '''This function wipes all metadata which is not scraped from the imaging data in the database.

        Should be used with caution, if information is not exported then there is no way to recover this data.
        '''

        confirm = input(('This command will wipe all metadata not found in filesystem imaging data from the DB. Are '
                         'you sure you want to do this ([Y]es/[N]o)? ')).lower()

        if not confirm in ['yes', 'y']:
            self.log('Confirmation refused, exiting early.')
            return

        self.log('Clearing subject accession.')
        self._database[self._project].update_many(
            {},
            {
                '$set' : { 
                    ColumnNames.SUBJECT_ACCESSION : Definitions.MISSING_BY_TYPE[type(ColumnNames.SUBJECT_ACCESSION)]
                }
            }
        )
        
        self.log('Clearing session accession.')
        self._database[Definitions.SESSIONS].update_many(
            {},
            {
                '$set' : { 
                    ColumnNames.SESSION_ACCESSION : Definitions.MISSING_BY_TYPE[type(ColumnNames.SESSION_ACCESSION)]
                }
            }
        )

        self.log('Clearing fs accession.')
        self._database[Definitions.SESSIONS].update_many(
            {},
            {
                '$set' : { 
                    ColumnNames.FS_ACCESSION : Definitions.MISSING_BY_TYPE[type(ColumnNames.FS_ACCESSION)]
                }
            }
        )

    #----------------- Report functions ------------------
    def get_project_wide_report(self, 
                                report_path: str,
                                include_analysis: bool,
                                separate_subjects: bool) -> None:
        '''Generate a report detailing all data in a project.

        Go through each subject entry in a project and gather all relating imaging sessions. Then aggregate the data 
        together into a CSV file.

        Parameters:
            report_path       (str)  : The path to the generated report.
            include_analysis  (bool) : A flag which determines if analysis files should be included in the report.
            separate_subjects (bool) : A flag which determines if whitespace should be included between subject entries.
        '''

        result = pandas.DataFrame()
        
        #Create a subject object to use to load and generate data.
        subject = Subject.Subject(self._projects_data, self._database, self._project, self)
        
        #Get all the uids in the given project.
        uids = self._database[self._project].distinct('_id')
        for uid in uids:
            subject.load_by_uid(uid, self.__extend_reports)
            sa = subject.data[ColumnNames.SUBJECT_ACCESSION]
            if self.__check_for_remote_data(sa):
                subject.set_adjoined_data(self.__remote_data[sa])

            subject_df = subject.get_dataframe(include_analysis)
            result = self._concatenate_dataframe_with_separation(result, subject_df, separate_subjects)
            subject.clear()

        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)

    def get_session_report_by_sub_ses_string(self,
                                             sub_ses_strings: list, 
                                             report_path: str, 
                                             include_analysis: bool,
                                             separate_subjects: bool) -> None:
        '''Generate a report for specified sessions given a list of sub/ses strings.
        
        Given a list of sub/ses strings extract the subject ID and session ID, then aggregate session information into
        a report.

        Parameters:
            sub_ses_strings (list[str]) : The list of sub/ses strings in question.
            report_path (str)           : The path to the generated report.
            include_analysis  (bool) : A flag which determines if analysis files should be included in the report.
            separate_subjects (bool) : A flag which determines if whitespace should be included between subject entries.
        '''

        result = pandas.DataFrame()
        
        for session_object in self._generate_sessions_by_sub_ses_strings(sub_ses_strings):
            if session_object != None:
                result = self._concatenate_dataframe_with_separation(
                    result, 
                    CustomFlatten.dict_to_dataframe(
                        session_object.get_report_ready_data(include_analysis), 
                        exclude_columns = ['_id']
                    ),
                    separate_subjects
                )
                    
        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)

    def get_duplicate_sessions_report_by_project(self, 
                                                 report_path: str, 
                                                 include_analysis: bool,
                                                 separate_subjects: bool) -> None:
        '''Get all the duplicate sessions in a project.

        Calls __get_duplicate_sessions_dataframe_by_project which determines duplicates by checking for identical 
        scan source locations.

        Parameters:
            report_path       (str)  : The path to save the report to.
            separate_subjects (bool) : If separatation should be included.
        '''

        result = self.__get_duplicate_sessions_dataframe_by_project(include_analysis, separate_subjects)
        result = CustomFlatten.clean_dataframe_empty_columns(result)
        result.to_csv(report_path, index = False)
    
    #Generate a csv report which details
    def get_session_link_mapping(self, report_path: str) -> None:
        '''Determine the source dicom linking for all sessions in a project.

        Parameters:
            report_path (str)  : The path to save the report to.
        '''
        
        linked_data = {
            Definitions.SOURCE_DIR : [],
            Definitions.LINKED     : [],
        }

        self.log(f'Finding all scan sources for project {self._project}')
        scan_sources = list(self._projects_data[Definitions.PROJECTS][self._project][Definitions.SCAN_LOCATIONS].keys())
        
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
        self.log(f'Finding all session paths for project {self._project}')
        all_sub_ses = {}
        for project_alias in self._projects_data[Definitions.PROJECTS][self._project][Definitions.PROJECT_ALIASES]:
            sub_ses, _ = self.__find_sub_ses(project_alias, find_analysis=False)
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
        
    def export_accession_values(self,
                                report_path           : str,
                                id_col                : str,
                                id_accession_col      : str,
                                session_col           : str,
                                session_accession_col : str,
                                fs_accession          : str) -> None:
        '''Export all the accession values from the DB to a CSV.

        This is important because the CNDA accession values are the only metadata that cant be scrapped from the FS 
        imaging data. In the case that the DB needs to be rebuilt the accession mapping can be saved this way so you 
        dont have to re-generate it.

        Parameters:
            report_path           (str) : The path to save the report to.
            id_col                (str) : The name of he subject id column.
            id_accession_col      (str) : The name of the subject accession column.
            session_col           (str) : The name of the session id column.
            session_accession_col (str) : The name of the session accession column.
            fs_accession          (str) : The name of the fs accession column.
        '''

        result = { 
            id_col                : [],
            id_accession_col      : [],
            session_col           : [],
            session_accession_col : [],
            fs_accession          : []
        }
    
        session_values = {
            session_col           : ColumnNames.SESSION_ID, 
            session_accession_col : ColumnNames.SESSION_ACCESSION, 
            fs_accession          : ColumnNames.FS_ACCESSION
        }

        #First lets go through each subject and then go through each session.
        for subject in self._generate_subject_by_project(False):
            subject_id = subject.data[ColumnNames.PARTICIPANT_ID]
            subject_accession = subject.data[ColumnNames.SUBJECT_ACCESSION]
            
            #Initialize bins to extract values from.
            for session_object in subject.sessions.values():
                #Add in the subject_id and subject_accession.
                result[id_col].append(subject_id)
                result[id_accession_col].append(subject_accession)
                
                #Add in other accession values.
                for col_name, value in session_values.items():
                    result[col_name].append(session_object.data[value])

        #Now convert to dataframe and save.
        df = pandas.DataFrame.from_dict(result)
        df.to_csv(report_path, index = False)
    
    def find_multiple_definitions(self, report_path : str) -> None:
        '''Find all multiple subject definitions in a project.

        Parameters:
            report_path (str) : The path to save the report to.
        '''

        result = { 
            ColumnNames.PARTICIPANT_ID : [],
            ColumnNames.SESSION_ID     : [],
            ColumnNames.DATA_PATH      : []
        }

        for project_alias in self._projects_data[Definitions.PROJECTS][self._project][Definitions.PROJECT_ALIASES]:
            sub_ses, _ = self.__find_sub_ses(project_alias, find_analysis=False)
            consolidated_sub_ses = self.__consolidate(sub_ses, return_multiples=True)
            
            #Now add to the result.
            for map_id, paths in consolidated_sub_ses.items():
                for path in paths:
                    result[ColumnNames.PARTICIPANT_ID].append(map_id)
                    result[ColumnNames.SESSION_ID].append(DataExtraction.guess_sess_id_from_path(path))
                    result[ColumnNames.DATA_PATH].append(path)

        df = pandas.DataFrame.from_dict(result)
        df.to_csv(report_path, index = False)

        
    
