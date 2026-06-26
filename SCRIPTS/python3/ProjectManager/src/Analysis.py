import copy
import os
import pymongo

import src.Utils.DBDocument as DBDocument
import src.DataModels.AnalysisDefinitions as AnalysisDefinitions
import src.Utils.Logger as Logger

class Analysis(DBDocument.DBDocument):
    '''Responsible for interfacing with project manager DB analysis documents.

    Attributes:
        data (dict) : all related metadata. The data dictionary is required to contain the following:
            AnalysisDefinitions.ANALYSIS_TYPE  (str) : What type of analsysis this is (only BOLD 
                                                       is available right now but this structure 
                                                       can be expanded for any type of analysis).

    '''
    
    def __init__(self, 
                 collection: pymongo.collection.Collection, 
                 logger: Logger,
                 uid = None,
                 initialize = {}) -> None:
        
        super().__init__(collection, logger, uid)

        #Now set the internal metadata based on the initialize keys/values.
        if self.data != None:
            self.data.update(initialize)
            self._collection.update_one({'_id' : self._uid}, {'$set': initialize}, upsert = True)

        
    def __remove_analysis_path(self, group: str, path: str) -> None:
        if not group in self.data: 
            return 
        
        local_list = self.data[group]
        if not path in local_list:
            return
        
        #Remove locally and in the database.
        local_list.remove(path)
        self._collection.update_one(
            {'_id' : self._uid},
            {'$pull' : { group : path }}
        )

    def _validate_data(self) -> bool:
        '''Implementation of which validates that the internal data contains required fields.
        '''

        #This should validate the data based on the analysis type.
        required_keys = {
            AnalysisDefinitions.ANALYSIS_TYPE  : str,
        }

        matching = True

        for key, value in required_keys.items():
            if not key in self.data or value != type(self.data[key]):
                matching = False
                break

        return matching
    
    def get_report_ready_data(self) -> dict:

        report_data = copy.deepcopy(self.data)
        if self.data[AnalysisDefinitions.ANALYSIS_TYPE] == AnalysisDefinitions.BOLD:
            #Simply remove the bold seed corr paths because this info is already captured in the bold network means dict.
            if AnalysisDefinitions.BOLD_SEED_CORR_ANALYSIS in report_data:
                del report_data[AnalysisDefinitions.BOLD_SEED_CORR_ANALYSIS]

        return report_data

    def get_type(self) -> str:
        return self.data[AnalysisDefinitions.ANALYSIS_TYPE]
    
    def check_fs_existance(self) -> None:
        for group in AnalysisDefinitions.ANALYSIS_TYPES:
            for group_name in AnalysisDefinitions.ANALYSIS_TYPES[group].keys():
                if not group_name in self.data: 
                    continue
                
                for path in self.data[group_name]:
                    if not os.path.isfile(path):
                        self.__remove_analysis_path(group_name, path)

    def clean_keys(self, keys_to_remove: set) -> None:
        for key in keys_to_remove:

            if key in self.data:
                #Remove remotely.
                self._collection.update_one(
                    {'_id' : self._uid},
                    {'$unset' : { key : 1}}
                )
        
                #Remove locally.
                del self.data[key]


