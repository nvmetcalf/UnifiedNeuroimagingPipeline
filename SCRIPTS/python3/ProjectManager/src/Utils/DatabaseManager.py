import os
import pymongo
from bson.objectid import ObjectId

import src.DataModels.Definitions as Definitions
import src.Subject as Subject

class DatabaseManager(object):
    def __init__(self, database_name: str) -> None:

        #This is the ID of the projects info document which stores all the entrypoint
        #information. This ID should never change and is where all project related information 
        #is stored.
        projects_info_id = ObjectId('662bd60a8b564a24fc2202d8') 
        
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
            self._projects_data = projects_info.find_one({'_id':projects_info_id})
            
            self._projects_dir  = os.path.join(Definitions.PROJECTS_HOME, Definitions.PROJECTS_DIR)
            self._scans_dir     = os.path.join(Definitions.PROJECTS_HOME, Definitions.SCANS_DIR)

        except Exception as e:
            print(f'An error connecting to the database {database_name} failed with error {e}.')
            raise RuntimeError
    
    def _get_total_subjects_in_project(self, project: str) -> int:
        return self._database[project].count_documents({})

    #This is a generator that loops through all the subjects in a given project and returns a subject object
    #for that subject
    def _generate_subject_by_project(self, project:str, extend_data: bool):

        project_cursor = self._database[project].find({})
        for document in project_cursor:
            subject = Subject.Subject(self._projects_data, self._database, project)

            subject.load_by_uid(document['_id'], extend_data)
            yield subject
