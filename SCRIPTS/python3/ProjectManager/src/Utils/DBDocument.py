import pymongo
import copy
import os
from abc import ABC, abstractmethod

from bson.objectid import ObjectId
import src.DataModels.Definitions as Definitions

import src.Utils.Logger as Logger

class DBDocument(ABC):
    '''Used to interact with single documents in the mongoDB database, handles database synchronization.
    
    Used as a template for single document synchronzation and enforces specific datastructures by requiring the
    implmentation of a validate_data function.

    Attributes:
        _collection (pymongo.collection) : The collection this document resides in.
        _logger     (Logger)             : The logger class responsible for logging messages.
        _uid        (ObjectId)           : The BSON ObjectId for this document.
        data        (dict)               : The dictionary containing the document's data.

    Requirements:
        The _validate_data function must be implemented as this is an abstract function.
    '''

    def __init__(self, 
                 collection: pymongo.collection.Collection, 
                 logger: Logger,
                 uid = None) -> None:
        '''Initize the DBDDocument class.

        Initializes this class with appropriate collection and logger information. Additionally attempts to load in
        remote data from the PM DB using the collection and uid provided. If the uid is None then a new document will
        be created.

        Parameters:
            collection (pymongo.collection) : The collection this document resides in.
            logger     (Logger)             : The logger class for this document.
            uid        (ObjectId | None )   : The ObjectId to associate with this class. If None then a new document 
                                              will be created.
        '''

        self._collection   = collection
        self._logger       = logger

        #If the session document cant be found then create it.
        if  uid == None:
            self.data = {}
            self._uid = self._collection.insert_one(self.data).inserted_id
            return

        self.data = self._collection.find_one({'_id' : uid})
        if self.data == None:
            self._logger.log(f'Unable to find session document with _id: {str(uid)} in database.')
            self._uid = None
            return

        self._uid = self.data['_id']

    def __copy__(self):
        '''Defines copying behavior for this class.

        Copies the internal data attribute correctly.
        '''
        session_copy = DBDocument(self._collection, self._logger, self._uid) 
        session_copy.data = copy.copy(self.data)
        return session_copy
   
    #Validates data to ensure that all the required fields are present.
    @abstractmethod
    def _validate_data(self) -> bool:
        '''The data validation function. Used to ensure that the data member has correct attributes.

        This function confirms that the data class contains all expected fields for this document type. if this 
        function retuns false then internal data will not be uploaded to the db. must be implemented in child classes.

        returns:
            status (bool) : t/f if the data structure is valid.
        '''

        pass
    
    def get_uid(self) -> ObjectId:
        '''Returns the ObjectId for this document.

        Returns:
            uid (ObjectId) : The uid for this document.
        '''

        return self._uid
    
    def update(self, metadata: dict, conflict_behavior = None) -> None:
        '''Updates the PM DB to reflect internal data.

        This is the main update function, all data passes through here in order to be updated to the DB.

        For every field in the metadata to update do the following:
            1. If the incoming field does not exist in the current data, add it.

            2. Compare the incoming field to remote field. If either is the empty value (as defined by the Definitions 
               file) replace the empty field with the populated one.

            3. If both fields are populated with non-empty values then we have a conflict (incoming data is trying to
               overwrite old data). In this case do one of the following actions.
                a. If the conflict_behavior function is not set, then overwrite the old data with incoming data.

                b. Otherwise collect the conflict into a dictionary of all conflicting_fields. Finally call the 
                   conflict_behavior function on this dictionary. The conflict_behavior function must return a 
                   dictionary of the resulting values to set.

        Parameters:
            metadata (dict) : The dictonary of incoming fields.
            conflict_behavior (function( dict ) -> dict | None) : The function which defines how to deal with incoming
                                                                  data conflicts. If None, then force overwite old data
                                                                  with incoming data.

        '''
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
            if conflict_behavior == None:
                self.data[key]      = metadata[key] #Update data internally
                data_to_update[key] = metadata[key] #We need this updated in the DB as well.
                continue
            
            #We have hit the final case where we need to ask the user what field they want to keep.
            #Collect all the confliting fields into a dictionary so that we can prompt that information
            #later.
            conflicting_fields[key] = metadata[key]
        
        #If there are conflicting fields we need to deal with them.
        if conflicting_fields != {} and conflict_behavior != None:
            conflicting_fields = conflict_behavior(conflicting_fields)

            #Now add all the resolved conflicts to teh final data to update.
            for key in conflicting_fields:
                data_to_update[key] = conflicting_fields[key]
                self.data[key]      = conflicting_fields[key]

        if data_to_update == {}:
            return

        if self._validate_data():
            #We just need to update it.
            self._collection.update_one({ '_id' : self._uid },
                                        { '$set': data_to_update },
                                        upsert = True)
        else:
            self._logger.log((f'Unable to validate the data for document {str(self._uid)}\nData: '
                              f'{self.data}\nEnsure that all required feilds are present.'))

    
    def append_to_list(self, field: str, value_to_append, conflict_behavior = None) -> None:
        '''Append a value to a list in the documents data. Additionally update the database to have the new value.
        
        If the field does not exist, use the existing update function to add the new value. Otherwise do a DB push 
        operation in order to not have to reset the whole array every time.

        Parameters:
            field             (str)                             : The name of the field to update.
            value_to_append   (Any)                             : The value to add to the array.
            conflict_behavior (function( dict ) -> dict | None) : The function which defines how to deal with incoming
                                                                  data conflicts. If None, then force overwite old data
                                                                  with incoming data.
        '''
        
        #If it doesnt already exist create an array with one element.
        if not field in self.data:
            self.update( { field : [ value_to_append ] }, conflict_behavior)
            return
        
        if type(self.data[field]) != list:
            self._logger.log(f'Cannot append {value_to_append} to {field} because {field} is not a list.')
            raise ValueError
            return

        #Otherwise we need to push the value.
        self.data[field].append(value_to_append)
        self._collection.update_one({ '_id' : self._uid},
                                    { '$push': { field : value_to_append} })
    

    #This removes the document from the database entirely.
    def remove(self):
        '''Remove a document from the database, additionally clear data.

        '''
        #Remove the document from the DB.
        self._collection.delete_one({'_id' : self._uid})

        #Now clear out the internal data so it cant be used.
        self.data = {}
        self._uid = None
