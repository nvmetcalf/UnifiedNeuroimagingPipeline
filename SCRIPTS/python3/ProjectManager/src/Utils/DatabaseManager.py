import os
import pymongo
import pandas
from bson.objectid import ObjectId

import src.DataModels.Definitions as Definitions
import src.DataExtraction as DataExtractor
import src.Subject as Subject
import src.Utils.Logger as Logger

class DatabaseManager(Logger.Logger):
    '''Handles basic connection to the MongoDB database and the storage of important related values.

    Attributes:
        _project       (str)                       : The name of the ProjectManager project.
        _projects_data (dict)                      : Stored project information for all projects. Includes local 
                                                     filesystem mappings.
        _database      (pymongo.database.Database) : The mongoDB database for project manager.
        _projects_dir  (str)                       : The path to the UNP directory containing project aliases.
        _scans_dir     (str)                       : The path to the UNP directory raw scan information.

    Requirements:
        A mongoDB database must be running and have the following collections:
            1. Definitions.PROJECTS_INFO: Must contain a "projects_info" document with the OID:
               662bd60a8b564a24fc2202d8

        The "projects_info" document must contain:
            1. Definitions.PROJECTS_HOME (str) : The UNP project home directory.
            2. Definitions.PROJECTS_DIR  (str) : The UNP directory within the home directory for projects.
            3. Definitions.SCANS_DIR     (str) : The UNP directory within the home directory for raw scans.
    '''

    def __init__(self, database_name: str, project: str, log_file = '') -> None:
        '''Initialize the DatabaseManager object.

        Store common local attributes and additionally connect to the mongoDB database. Also call the Logger class
        if a log_file path is specified.

        Parameters:
            database_name (str) : The name of the mongoDB database.
            project       (str) : The project name.
            log_file      (str) : An optional path to the log file.
        '''
        
        super().__init__(log_file)

        #Store the project name
        self._project = project

        #This is the ID of the projects info document which stores all the entrypoint
        #information. This ID should never change and is where all project related information 
        #is stored.
        self._projects_info_id = ObjectId('662bd60a8b564a24fc2202d8') 
        
        #Load in the projects entrypoint. This is the jumping off point for everything.
        #the projects_data_queue is a list of update actions that are performed on projects_data.
        #whenever a modification is made to projects_data the appropriate database action is appended
        #to the projects_data_queue. An update can be performed at any time and each item in the
        #queue will be applied to projects_data in order.
        self._projects_data = {}

        #Now lets attempt to connect to the DB.
        try:
            client = pymongo.MongoClient('mongodb://localhost:27017/')
            self._database = client[database_name]

            #Load the project information document.
            projects_info = self._database[Definitions.PROJECTS_INFO]
            self._projects_data = projects_info.find_one({'_id': self._projects_info_id})
            
            self._projects_dir  = os.path.join(Definitions.PROJECTS_HOME, Definitions.PROJECTS_DIR)
            self._scans_dir     = os.path.join(Definitions.PROJECTS_HOME, Definitions.SCANS_DIR)

        except Exception as e:
            print(f'An error connecting to the database {database_name} failed with error {e}.')
            raise RuntimeError
    
    def _concatenate_dataframe_with_separation(self, 
                                                original_df: pandas.DataFrame, 
                                                new_dataframe: pandas.DataFrame, 
                                                separate_subjects: bool) -> pandas.DataFrame:
        '''Concatenates two dataframes together. Additionally optionally separate entries by whitespace.

        Parameters:
            original_df       (pandas.DataFrame) : The main df to concatenate too.
            new_dataframe     (pandas.DataFrame) : The new df to concatentate. 
            separate_subjects (bool)             : If separatation should be included.

        Returns:
            result (pandas.DataFrame) : The concatenated df.
        '''

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
    
    def _get_total_subjects_in_project(self) -> int:
        '''Get the total number of subjects that exist in a project in the mongoDB database.

        Returns:
            number (int) : The number of subjects found in a project.
        '''

        return self._database[self._project].count_documents({})

    #This is a generator that loops through all the subjects in a given project and returns a subject object
    #for that subject
    def _generate_subject_by_project(self, extend_data: bool):
        '''Generate each subject object in a project.

        Arguments:
            extend_data (bool) : A flag which fetches local data for given subject object.
        
        Yeilds:
            subject (Subject) : The current subject object in a project.
        '''

        project_cursor = self._database[self._project].find({})
        for document in project_cursor:
            subject = Subject.Subject(self._projects_data, self._database, self._project, self)

            subject.load_by_uid(document['_id'], extend_data)
            yield subject

    def _generate_sessions_by_sub_ses_strings(self, sub_ses_strings: list):
        '''Generate each subject object in a project.

        Arguments:
            sub_ses_strings    : The list of sub/ses strings of interest.
            extend_data (bool) : A flag which fetches local data for given subject object.
        
        Yeilds:
            session (Session) : The current subject object in a project.
        '''

        for sub_ses in sub_ses_strings:
            #First try to determine the sub id and sess id from the string.
            sub = DataExtractor.guess_map_id_from_path(sub_ses)
            ses = DataExtractor.guess_sess_id_from_path(sub_ses)
            if sub == '' or ses == '':
                self.log(f'Could not determine the subject or session id for {sub_ses}.')
                yield None 

            #Now load in the specific session based on the session id in the string.
            subject = Subject.Subject(self._projects_data, self._database, self._project, self)
            if not subject.load_by_map_id(sub, False):
                self.log(f'Could not load in a matching subject for {sub}')
                yield None 

            yield subject.get_session_by_session_id(ses)
            


