import pymongo
from bson.objectid import ObjectId
import os
import copy

import src.DataModels.Definitions as Definitions
from src.InformationPrompter import SessionInformationPrompter 


class Session(object):
    def __init__(self, collection: pymongo.collection.Collection, uid = None) -> None:
        self.__collection   = collection

        #If the session document cant be found then create it.
        if  uid == None:
            self.data = {}
            self.__uid = self.__collection.insert_one(self.data).inserted_id
            return

        self.data = self.__collection.find_one({'_id' : uid})

        if self.data == None:
            print(f'Unable to find session document with _id: {str(uid)} in database ')
            self.__uid = None
            return

        self.__uid = self.data['_id']

    def __copy__(self):
        session_copy = Session(self.__collection, self.__uid) 
        session_copy.data = copy.copy(self.data)
        return session_copy
   
    #Validates data to ensure that all the required fields are present.
    def __validate_data(self) -> bool:
        required_keys = {
            Definitions.SESSION_ID          : str,
            Definitions.FS_VERSION          : str,
            Definitions.SCANNER             : str,
            Definitions.PIPELINE_VERSION    : str,
            Definitions.SOFTWARE_VERSION    : str,
            Definitions.DATE_COLLECTED      : str,
            Definitions.DATA_PATH           : str,
            Definitions.PROC_STATUS         : str,
            Definitions.MODS_COLLECTED      : list
        }


        matching = True

        for key in required_keys:
            if type(required_keys[key]) == self.data[key]:
                matching = False
                break

        return matching

    def get_data_path(self) -> str:
        if self.data != None:
            return self.data[Definitions.DATA_PATH]

        return ''

    def get_uid(self) -> ObjectId:
        return self.__uid
    
    def update(self, metadata: dict, force_update) -> None:
        #Iterate through the loaded data and the metadata. If the loaded data
        #at a given key matches the metadata at that key then we dont need to update
        #it. If the loaded data doesnt exist for a key in the metadata then we need
        #To copy the key from the metadata over to the internal data and update it.
        #If there is empty data at a given key one either side but not on the other
        #Then we should copy the data that exists and use that. Finally if non-empty data
        #exists both internally and in the metadata for the same key then we need to either
        #   1) If force_update is true then use the metadata version.
        #   2) If force_udpate is false then prompt the user that there is conflicting information
        #      and ask them what info they want to keep.
        
        #First start by setting the data_to_update to be a copy of the internal data we already have.
        data_to_update     = {}
        conflicting_fields = {} 

        #Now go through each key in the metadata
        for key in metadata:
            if not key in self.data:
                self.data[key]      = metadata[key] #Update data internally
                data_to_update[key] = metadata[key] #We need this updated in the DB as well.
                continue
            
            #Otherwise the key exists in both places. Any empty keys that exist internally 
            #but not in the metadata have already been added to the data_to_update by the 
            #initial copy. All thats left is that the data exists on both sides.
            
            #If the data matches on both sides then we dont need to update it.
            if self.data[key] == metadata[key]:
                continue
            
            if metadata[key] == Definitions.MISSING_BY_TYPE[type(metadata[key])]:
                continue
            
            if self.data[key] == Definitions.MISSING_BY_TYPE[type(self.data[key])]:
                #Then we need to set it to the metadata value.
                self.data[key]      = metadata[key] #Update data internally
                data_to_update[key] = metadata[key] #We need this updated in the DB as well.
                continue
           
            #Otherwise we have hit the most difficult case where plausable data exists both 
            #internally and in the new data. Now we need to check if we are forcing updates
            #or if we want to prompt the user to choose what data they want to keep.
            if force_update:
                self.data[key]      = metadata[key] #Update data internally
                data_to_update[key] = metadata[key] #We need this updated in the DB as well.
                continue
            
            #We have hit the final case where we need to ask the user what field they want to keep.
            #Collect all the confliting fields into a dictionary so that we can prompt that information
            #later.
            conflicting_fields[key] = metadata[key]
        
        #If there are conflicting fields we need to deal with them.
        if conflicting_fields != {}:
            session_info_prompt = SessionInformationPrompter(self)
            conflicting_fields = session_info_prompt.prompt_conflicting_information(conflicting_fields)

            #Now add all the resolved conflicts to teh final data to update.
            for key in conflicting_fields:
                data_to_update[key] = conflicting_fields[key]
                self.data[key]      = conflicting_fields[key]

        if data_to_update == {}:
            return

        if self.__validate_data():
            #We just need to update it.
            self.__collection.update_one({ '_id' : self.__uid },
                                         { '$set': data_to_update },
                                         upsert = True)
        else:
            print(f'Unable to validate the data for Session {str(self.__uid.inserted_id)}\nData: {self.data}\nEnsure that all required feilds are present.')

    #This removes the session from the database entirely.
    def remove(self):
        #Remove the document from the DB.
        self.__collection.delete_one({'_id' : self.__uid})

        #Now clear out the internal data so it cant be used.
        self.data = {}
        self.__uid = None
    

    #This function just checks if the current session exists on the file system.
    #Returns T/F accordingly.
    def fs_existance(self) -> bool:
        if self.get_data_path() == '':
            print(f'The session object was not loaded, no data path exists.')
            return False

        return os.path.isdir(self.get_data_path())
