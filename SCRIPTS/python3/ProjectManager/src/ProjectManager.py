import os
import pandas
import pymongo
from bson.objectid import ObjectId

from src.Subject import Subject
import src.Utils.CustomFlatten as CustomFlatten
import src.DataExtraction as DataExtraction
import src.DataModels.Definitions as Definitions
class ProjectManager(object):
    def __init__(self, database_name: str) -> None:
        
        #This is the ID of the projects info document which stores all the entrypoint
        #information. This ID should never change and is where all project related information 
        #is stored.
        projects_info_id = ObjectId('662bd60a8b564a24fc2202d8') 

        #Keeps track of the state of the project manager.
        # 0 -> No errors.
        # 1 -> Could not load manifest entrypoint.
        # 2 -> Entry point not formed correctly.
        # 3 -> Write error.
        # 4 -> Could not open subject DB entry.
        # 5 -> Subject file not formed correctly.
        self.error_state = 0
        
        #Load in the projects entrypoint. This is the jumping off point for everything.
        #the projects_data_queue is a list of update actions that are performed on projects_data.
        #whenever a modification is made to projects_data the appropriate database action is appended
        #to the projects_data_queue. An update can be performed at any time and each item in the
        #queue will be applied to projects_data in order.
        self.__projects_data = {}

        #Now lets attempt to connect to the DB.
        try:
            client = pymongo.MongoClient('mongodb://localhost:27017/')
            self.__database = client[database_name]

            #Load the project information document.
            projects_info = self.__database[Definitions.PROJECTS_INFO]
            self.__projects_data = projects_info.find_one({'_id':projects_info_id})
            
            self.__projects_dir  = os.path.join(Definitions.PROJECTS_HOME, Definitions.PROJECTS_DIR)
            self.__scans_dir     = os.path.join(Definitions.PROJECTS_HOME, Definitions.SCANS_DIR)


        except Exception as e:
            print(f'An error connecting to the database {database_name} failed with error {e}.')
            self.error_state = 1

    #Finds all the dirs with the name sub-x_ses-y and returns their paths.
    def __find_subject(self, root_dir: str, target_subject_id: str) -> list:
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
            if found_match:
                return matching

            #Otherwise we need to keep looking.
            found_files = []
            for dir in dirs:
                os.chdir(current_dir) #Make sure we are at the right dir.
                found_files += recursively_find_sub_ses(os.path.abspath(dir))
            
            return found_files

        print(f'Finding all subject/session pairs starting at root dir: {root_dir} matching {target_subject_id} ...')
        current_dir = os.getcwd()
        all_sub_ses = recursively_find_sub_ses(os.path.join(self.__projects_dir, root_dir))
        os.chdir(current_dir)
            
        print(f'Done finding subject/session pairs at root dir: {root_dir} matching {target_subject_id}')

        return all_sub_ses

    #Finds all the dirs with the name sub-x_ses-y and returns their paths.
    def __find_all_sub_ses(self, project_dir: str) -> list:
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
            for dir in dirs:
                if 'sub' in dir and 'ses' in dir:
                    matching.append(os.path.abspath(dir))

            #Now if we have found some subject sessions return those.
            if len(matching) > 0:
                return matching

            #Otherwise we need to keep looking.
            found_files = []
            for dir in dirs:
                os.chdir(current_dir) #Make sure we are at the right dir.
                found_files += recursively_find_sub_ses(os.path.abspath(dir))
            
            return found_files

        #Ensure that we keep executing at the correct location in the filesystem. 
        print(f'Finding all subject/session pairs starting at root dir: {project_dir}...')
        current_dir = os.getcwd()
        all_sub_ses = recursively_find_sub_ses(os.path.join(self.__projects_dir, project_dir))
        os.chdir(current_dir)
            
        print(f'Done finding subject/session pairs at root dir: {project_dir}')

        return all_sub_ses

        
    #The point of this function is to take a list of all found sources and organize them.
    #The following is the organizational structure which will be used:
    #   -project_name
    #       -subject
    #           +path to sources (list)
    def __consolidate_subjects(self, sub_ses_list: list) -> dict:
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
    
    #This is a generator that loops through all the subjects in a given project and returns a subject object
    #for that subject
    def __generate_subject_by_project(self, project:str):
            
        project_cursor = self.__database[project].find({})
        for document in project_cursor:
            subject = Subject(self.__projects_data, self.__database)
            subject.load_by_uid(project, document['_id'])

            yield subject


    def __get_duplicate_sessions_dataframe_by_project(self, project: str, separate_subjects: bool) -> pandas.DataFrame:
        result = pandas.DataFrame()

        if not project in self.__projects_data[Definitions.PROJECTS]:
            print(f'Could not find the project {project} in ProjectsData. Ensure that this is a real project and has been specified correctly.')
            return result 
        
        for subject in self.__generate_subject_by_project(project):
            subject_df = subject.get_expanded_duplicate_dataframe()

            result = self.__concatenate_dataframe_with_separation(result, subject_df, separate_subjects)
       
        return result

    def __get_sessions_by_status_in_project(self, project: str, status:str, separate_subjects: bool) -> pandas.DataFrame:
        result = pandas.DataFrame()

        if not project in self.__projects_data[Definitions.PROJECTS]:
            print(f'Could not find the project {project} in ProjectsData. Ensure that this is a real project and has been specified correctly.')
            return result 
        
        for subject in self.__generate_subject_by_project(project):
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

     
            subject_df = CustomFlatten.expanded_subject_to_dataframe(expanded_data)

            result = self.__concatenate_dataframe_with_separation(result, subject_df, separate_subjects)
       
        return result

    #----------------- Update, Build, and Duplicate detection functions ------------------
    
    def update_subjects(self, 
                        project: str, 
                        map_ids: list, 
                        prompt_missing_data: bool,
                        force_update: bool) -> None:

        subject = Subject(self.__projects_data, self.__database)
        for id in map_ids: 
            #Find all the paths that are associated with this subject.
            subject_data_paths = []
            for project_alias in self.__projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ALIASES]:
                subject_data_paths += self.__find_subject(project_alias, id)
            
            subject.update(project, id, subject_data_paths, {}, force_update)
            subject.prompt(project, prompt_missing_data, force_update)
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

        all_sub_ses = self.__find_all_sub_ses(project_alias)

        #Now consolidate the information into the project, session, path format.
        if consolidated == None:
            try:
                consolidated = self.__consolidate_subjects(all_sub_ses)
            except KeyError:
                print(f'There was an error trying to build the project alias {project_alias}. Skipping...')
                return
        
        #Initialize the subject object.
        subject = Subject(self.__projects_data, self.__database)
        #Now lets go through each subject and update them.
        for map_id in consolidated:
            subject.update(project, map_id, consolidated[map_id], {}, force_update)
            subject.prompt(project, prompt_missing_data, force_update)
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

        for project_alias in self.__projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ALIASES]:
            self.build_project_alias(project, project_alias, prompt_missing_data, force_update, consolidated)

    #This function builds the full DB for every subject and session relating to a project 
    #If a subject does exist then it updates that subjects data. If a subject does not exist 
    #then it creates it.
    def build_all_projects(self,
                           prompt_missing_data: bool,
                           force_update: bool) -> None:

        for project in self.__projects_data[Definitions.PROJECTS]:
            self.build_project(project, prompt_missing_data, force_update)
            print(f'Done building project: {project}')

    def update_project_alias(self,
                             project: str,
                             project_alias: str,
                             prompt_missing_data: bool,
                             force_update: bool) -> None:

        all_sub_ses = self.__find_all_sub_ses(project_alias)

        #Now consolidate the information into the project, session, path format.
        try:
            consolidated = self.__consolidate_subjects(all_sub_ses)
        except KeyError:
            print(f'There was an error trying to build the project alias {project_alias}. Skipping...')
            return

        found_ids = set(consolidated.keys())
        
        #Now build the project for all the found keys.
        self.build_project(project, prompt_missing_data,  force_update, consolidated = consolidated)
        
        #Now go through all the ids that werent touched by the build procecss and check that they still exist.
        not_modified = set(self.__database[project].distinct(Definitions.MAP_ID)) - found_ids
        
        subject = Subject(self.__projects_data, self.__database)
        for map_id in not_modified:
            if subject.load_by_map_id(project, map_id):
                subject.check_fs_existance(project)

    
    #This function is very similar to the build_project function. The only difference is that it
    #also scans through the file system at the project level and updates all subjects, not just those that were found
    #(removes data that no longer exists).
    def update_project(self, 
                       project: str,
                       prompt_missing_data: bool,
                       force_update: bool) -> None:

        for project_alias in self.__projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ALIASES]:
            self.update_project_alias(project, project_alias, prompt_missing_data, force_update)
        
    
    def update_all_projects(self,
                            prompt_missing_data: bool,
                            force_update: bool) -> None:

        for project in self.__projects_data[Definitions.PROJECTS]:
            self.update_project(project, prompt_missing_data, force_update)
            print(f'Done updating project: {project}')

    #----------------- Report functions ------------------
    
    def get_project_wide_report(self, 
                                project: str, 
                                report_path: str, 
                                separate_subjects: bool) -> None:

        result = pandas.DataFrame()
        
        #Create a subject object to use to load and generate data.
        subject = Subject(self.__projects_data, self.__database)
        
        #Get all the uids in the given project.
        uids = self.__database[project].distinct('_id')

        for uid in uids:
            subject.load_by_uid(project, uid)
            subject_df = subject.get_expanded_dataframe()
            
            result = self.__concatenate_dataframe_with_separation(result, subject_df, separate_subjects)

            subject.clear()

        result.to_csv(report_path, index = False)

    #Given the project to look in, the map_ids to look for, and a path to save the report to,
    def get_subject_report_by_map_ids(self, 
                                      project: str, 
                                      map_ids: list, 
                                      report_path: str,
                                      separate_subjects: bool) -> None:

        result = pandas.DataFrame()
        subject = Subject(self.__projects_data, self.__database)
        
        for map_id in map_ids:
            subject.load_by_map_id(project, map_id)
            subject_df = subject.get_expanded_dataframe()
            subject.clear()

            result = self.__concatenate_dataframe_with_separation(result, subject_df, separate_subjects)


        result.to_csv(report_path, index = False)

    #Gets information about a subject by, project, map ID, and session ID. Additionally takes a
    #fuzzy level parameter which specifies how far away the session id can be to be considered a match (0
    #is an exact match and higher is less strict.)
    def get_subject_report_by_sub_ses(self, project: str, map_id: str, sess_id: str, report_path: str, fuzzy_level) -> None:
        
        #create a new dataframe 
        #Load in the subject.
        subject = Subject(self.__projects_data, self.__database)
        subject.load_by_map_id(project, map_id)
    
        result = subject.get_session_by_session_id(sess_id, fuzzy_level)
        result.to_csv(report_path, index = False)

    def get_duplicate_sessions_report_by_project(self, project: str, report_path: str, separate_subjects: bool) -> None:

        result = self.__get_duplicate_sessions_dataframe_by_project(project, separate_subjects)
        result.to_csv(report_path, index = False)
    
    def get_all_duplicate_sessions_report(self, report_path: str, separate_subjects: bool) -> None:
        result = pandas.DataFrame()

        for project in self.__projects_data[Definitions.PROJECTS]:
            result = pandas.concat([result, self.__get_duplicate_sessions_dataframe_by_project(project, separate_subjects)])
        
        result.to_csv(report_path, index = False)
                
    #Generate a report which gets all the subjects which match a given processing status. 
    def get_project_report_by_processing_status(self, 
                                                project: str, 
                                                proc_status: str, 
                                                report_path: str,
                                                separate_subjects: bool) -> None:
        #Check that the given processing status is an option defined in the projects_data.
        valid_status = list(self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.ALLOWED_PROC_STATUSES].values())

        found_status = False
        for status in valid_status:
            if status.lower() == proc_status.lower():
                found_status = True
                break
        
        if not found_status:
            print(f'The processing status "{proc_status}" was not matched to any of the options defin in ProjectsInfo: {valid_status}')
            return

        result = self.__get_sessions_by_status_in_project(project, proc_status.lower(), separate_subjects)
        result.to_csv(report_path, index = False)

    
    def get_all_processing_status_report(self, 
                                         proc_status: str, 
                                         report_path: str, 
                                         separate_subjects: bool) -> None:
        
        result = pandas.DataFrame()
        #Iterate through each project and generate the report that way.
        for project in list(self.__projects_data[Definitions.PROJECTS].keys()):
            result = pandas.concat([result, self.__get_sessions_by_status_in_project(project, proc_status.lower(), separate_subjects)])
            print(f'Done searching {project}.')

        result.to_csv(report_path, index = False)
        
         
