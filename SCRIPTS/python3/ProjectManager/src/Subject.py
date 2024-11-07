import pandas
import pymongo
from bson.objectid import ObjectId
import sys
import copy

import src.Session as Session
import src.InformationPrompter as IP 
import src.DataModels.SubjectData as SubjectData
import src.DataModels.Definitions as Definitions
import src.Utils.CustomFlatten as CustomFlatten
import src.DataExtraction as DataExtractor

#This function will see if two session names could potentially match each other. This is because in the software
#pipeline session names can be condensed by exluding the underscores. For example a session named "aaa_bbb_ccc"
#might be saved as "aaabbbccc". Additionally it is possible that some of the groups seperated by underscores
#may be omited but still be the same session. For instance sometimes the map id is in the session id but is omited
#on the pipline. In this case the session id would be something of the form "aaa_MAPID_bbb" would be
#saved as "aaa_bbb". The point of this function is to check if subgroups seperated by underscores are
#a subset of either ids. If they are matching within a threshold of subgroups return true, otherwise false.
def fuzzy_match_session_ids(session_one: str, session_two: str, max_distance = 1) -> bool:
    #If the max_distance is 0 then we just want to do a straight up match.
    if not max_distance:
        return session_one == session_two

    #first if the two sessions are the same then its an automatic match.
    if session_one == session_two:
        return True
    
    #Returns how many subgoups from str1 are not in str2
    # sys.maxint indicates that nothing matches.
    def count_groups_not_in(str1: str, str2:str) -> int:
        ngroups = 0
        
        groups = str1.split('_')
        
        #If there are no groups then definitely there are no groups in common.
        if groups[0] == str1:
            return sys.maxsize

        for group in groups:
            if not group in str2:
                ngroups += 1
        
        if ngroups == len(groups):
            ngroups = sys.maxsize #No groups matched

        return ngroups
    
    groups_from_one_not_in_two = count_groups_not_in(session_one, session_two)
    groups_from_two_not_in_one = count_groups_not_in(session_two, session_one)

    #Now if one of these values is less than the max distance then we are good to go (the max). Otherwise 
    #it is not a fuzzy match.
    if groups_from_one_not_in_two <= max_distance or groups_from_two_not_in_one <= max_distance:
        return True

    return False

class Subject(object):

    #The data stored in the subject doument
    def __init__(self, 
                 projects_data: dict, 
                 database: pymongo.database.Database, 
                 parent_project: str) -> None:

        self.__database      = database
        self.__projects_data = projects_data
        self.parent_project = parent_project
        self.data = {}

        #These are objects which correspond to individual sessions. the key value pairs are ObjectId:session_object
        self.sessions = {} 
        self.__cols_to_remove = [
            Definitions.DUPLICATES,
            '_id',
            f'{Definitions.SESSION_DATA}._id'
        ]

        
        
    
    #Creates a shallow copy of the subject object. 
    def __copy__(self):
        subject_copy = Subject(self.__projects_data, self.__database, self.parent_project) 

        subject_copy.data = copy.deepcopy(self.data)
        for session_uid in self.sessions:
            subject_copy.sessions[session_uid] = copy.copy(self.sessions[session_uid])
        
        return subject_copy

    def __load_sessions(self, extend_data: bool) -> None:
        for uid in self.data[Definitions.SESSION_DATA]:
            #Load in the session objects

            self.sessions[uid] = Session.Session( self.__database[Definitions.SESSIONS],uid=uid, load_extended_data = extend_data)
    
    #A helper function to remove a session both from the database and internally in the data structure.
    #returns if a session was removed or not.
    def __remove_session_if_not_on_fs(self, map_id:str , session_uid: ObjectId) -> None:
        session_object = self.sessions[session_uid]
        if session_object.fs_existance():
            return 

        print(f'Could not find session data at {session_object.get_data_path()}, removing...')
        
        session_object.remove()
        del self.sessions[session_uid]
        
        
        self.__database[self.parent_project].update_one({Definitions.MAP_ID : map_id},
                                            {'$pull'  : {Definitions.SESSION_DATA: session_uid}})

        #Now we need to remove it from the duplicates and/or the longitunidal data as well.
        #First check if the current session_uid is a parent of either the lon. or dup. data.
        long = self.data[Definitions.LONGITUDINAL]
        
        skip_child_search = False
        if session_uid in long:
            del long[session_uid]
            
            #Remove the session from the longitudinal object in the database.
            self.__database[self.parent_project].update_one({Definitions.MAP_ID : map_id},
                                                {'$unset'  : {f'{Definitions.LONGITUDINAL}.{session_uid}': 1}})
            skip_child_search = True
        
        #Now if it didnt happen to be a parent key lets check all the children.
        if not skip_child_search:
            for parent_uid in long:
                #Remove the session from the subject array as well in the database.
                if session_uid in long[parent_uid]:
                    long[parent_uid].remove(session_uid)
                    
                    #Check if we deleted all the children
                    if long[parent_uid] == []:
                        self.__database[self.parent_project].update_one({Definitions.MAP_ID : map_id},
                                                            {'$unset'  : {f'{Definitions.LONGITUDINAL}.{parent_uid}': 1}})
                        break
                    
                    #Otherwise just delete the single element.
                    self.__database[self.parent_project].update_one({Definitions.MAP_ID : map_id},
                                                        {'$pull'  : {f'{Definitions.LONGITUDINAL}.{parent_uid}': session_uid}})
        
    #This is used to make the modalities list more readable in a csv format when
    #using json normalize. Basically just splits the list into a bunch of T/F variables
    #for if that modaility was collected or not.
    def __format_modalities_list(self, session_data: dict) -> None:
        mods_collected = session_data[Definitions.MODS_COLLECTED]
        del session_data[Definitions.MODS_COLLECTED]

        #Now lets create bools for everything collected.
        all_modalities = Definitions.REGEX_RULES["MODALITIES"].keys()
        for modality in all_modalities:
            if modality in mods_collected:
                session_data[modality] = mods_collected[modality]
                continue
            
            session_data[modality] = 0
    
    def __create_subject(self, 
                         map_id: str, 
                         data_sources: list, 
                         analysis_sources: list,
                         subject_metadata: dict,
                         cnda_id = '') -> None:

        #What we need to do is fill out the data object as best as possible
        self.data = SubjectData.generate_subject_data(map_id, cnda_id)

        for key in subject_metadata:
            self.data[key] = subject_metadata[key]
        
        potential_duplicates = {}

        #Now lets create all the Sessions from the data sources.
        for data_source in data_sources:
            
            extractor = DataExtractor.DataExtractor(self.__projects_data, data_source)

            session_data = extractor.generate_session_data(analysis_sources) 
            if session_data == {}:
                continue
            
            #This line will create the session object because it does not exist in the database.
            session_object = Session.Session(self.__database[Definitions.SESSIONS], uid = None)

            #Finally update the data. We shouldnt have to force update anything because this data
            #is new.
            session_object.update(session_data, force_update = False)

            #Add it to the sessions this object manages.
            self.sessions[session_object.get_uid()] = session_object
            
            #Now update the duplicate map.
            metadata_source_path = extractor.get_metadata_source_directory()
            if metadata_source_path == '':
                continue

            #Otherwise we will catalog it and see if there are any duplicates later.
            if not metadata_source_path in potential_duplicates:
                potential_duplicates[metadata_source_path] = [session_object.get_uid()]
                continue

            potential_duplicates[metadata_source_path].append(session_object.get_uid())
        
        #Now go through each of the potential duplicates and add the ones with more than one entry to the duplicates.
        for session_id in potential_duplicates:
            duplicate_list = potential_duplicates[session_id]
            if len(duplicate_list) == 1:
                continue

            self.data[Definitions.DUPLICATES].append(duplicate_list)

        #Now that the object has been populated internally. Lets update the data in the actual database.
        print(f'Creating subject {map_id}')
        self.data[Definitions.SESSION_DATA] = list(self.sessions.keys())
        self.__database[self.parent_project].update_one({Definitions.MAP_ID : map_id},
                                            {'$set'   : self.data},
                                            upsert = True)

    def __set_all_sessions_value(self, key: str, value) -> None:
        for session_uid in self.sessions:
            self.sessions[session_uid].update({key: value}, force_update = True)
    

    #Must be called after a subject is created.
    def set_cnda_id(self, cnda_id: str) -> None:
        self.data[Definitions.SUBJECT_ACCESSION] = cnda_id
        self.__database[self.parent_project].update_one({Definitions.MAP_ID : self.data[Definitions.MAP_ID]},
                                            {'$set'   : self.data},
                                            upsert = True)

    def set_extend_session_report(self) -> None:
        self.__extend_session_data = True
        self.__cols_to_remove = []


    def prompt(self, 
               prompt_missing_data: bool, 
               force_update: bool) -> None:
        
        if not prompt_missing_data:
            return

        info_prompt = IP.SubjectInformationPrompter(self)
        update_session_data = {}

        if prompt_missing_data and info_prompt.subject_incomplete():
            update_session_data = info_prompt.prompt_missing_information()
                
        self.db_update(update_session_data, force_update)   
                    
    #This simply updates the database to be consistant with internal data fields.
    def db_update(self, 
                  new_data: dict, 
                  force_update: bool) -> None:
    
        #Check if the data has been populated:
        if self.data == {}:
            print('The subject has not been loaded. Cannot perform an internal update')
            return

        if new_data == {}:
            return

        print(f'Updating subject {self.data[Definitions.MAP_ID]}')
        
        #Update MAP_ID
        #Now that the object has been populated internally. Lets update the data in the actual database.
        self.__database[self.parent_project].update_one({Definitions.MAP_ID : self.data[Definitions.MAP_ID]},
                                            {'$set'   : self.data},
                                            upsert = True)
        
       
        #Now simply go through each session and update it in the database based on its metadata.
        for session in self.sessions:
            if session in new_data:
                self.sessions[session].update(new_data[session], force_update)
    
    #Creates a new subject object and adds it to the database. If it finds that this subject already
    #exists then it updates it instead.
    def update(self, 
               map_id: str,
               data_sources: list, 
               analysis_sources: list,
               subject_metadata: dict, 
               force_update: bool,
               cnda_accession = '') -> None:

        #Check if the subject already exists in the given project.
        subject_exists = self.load_by_map_id(map_id, False)

        if subject_exists:
            self.update_from_fs(data_sources, analysis_sources, subject_metadata, force_update)
        else:
            #The subject does not exist, therefore we need to create it and add it to the DB.
            self.__create_subject(map_id, data_sources, analysis_sources, subject_metadata, cnda_accession)

        #Finally we should update the accession information for this subject.
        self.update_duplicate_accession(force_update)

    def update_metadata(self, metadata: dict, force_update) -> None:
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
            subject_info_prompt = IP.SubjectInformationPrompter(self)
            conflicting_fields = subject_info_prompt.prompt_conflicting_information(conflicting_fields)

            #Now add all the resolved conflicts to teh final data to update.
            for key in conflicting_fields:
                data_to_update[key] = conflicting_fields[key]
                self.data[key]      = conflicting_fields[key]

        if data_to_update == {}:
            return

        #We just need to update it.
        self.__database[self.parent_project].update_one({Definitions.MAP_ID : self.data[Definitions.MAP_ID]},
                                                        {'$set'   : self.data},
                                                        upsert = True)

    def update_duplicate_accession(self, force_update: bool) -> None:
        subject_ip = IP.SubjectInformationPrompter(self)

        #Populate the duplicate list.
        for dup_list in self.data[Definitions.DUPLICATES]:
            found_values = {
                Definitions.SESSION_ACCESSION : [],
                Definitions.FS_ACCESSION      : []
            }
            duplicate_session_id_list = []
            for duplicate_uid in dup_list:
                session_object = self.sessions[duplicate_uid]
                duplicate_session_id_list.append(session_object.data[Definitions.SESSION_ID])
                for key in found_values:
                    if session_object.data[key] != Definitions.MISSING_BY_TYPE[type(session_object.data[key])]:
                        found_values[key].append(session_object.data[key])

            #Now check that the current accession information is synthesized with the found data.
            for key in found_values:
                unique_values = set(found_values[key])
                if len(unique_values) == 0:
                    continue
            
                if len(unique_values) == 1 or force_update:
                    #propagate this value to every session.
                    self.__set_all_sessions_value(key, next(iter(unique_values)))
                    continue

                #Otherwise we have multiple values and we want to choose.
                prompt_info = f'Updating duplicate sessions: {duplicate_session_id_list}'
                self.__set_all_sessions_value(key, subject_ip.choose_value(key, list(unique_values), additional_info = prompt_info))

    #The point of this function is to update as much relevant information from the file system as possible
    #given a list of data sources which pertain to the subject.
    def update_from_fs(self, data_sources: list, analysis_sources: list, subject_metadata: dict, force_update: bool) -> None: 

        print(f'Updating subject {self.data[Definitions.MAP_ID]}')

        #update any additional metadata which may exist.
        for key in subject_metadata:
            self.data[key] = subject_metadata[key]
        
        subject_id = self.data[Definitions.MAP_ID] 
        #Now that the object has been populated internally. Lets update the data in the actual database.
        self.__database[self.parent_project].update_one({Definitions.MAP_ID : subject_id},
                                            {'$set'   : self.data},
                                            upsert = True)

        #Now build up a session_id reference table which relates the objectIds to the
        #session ids for this session.
        data2uids = {}
        for uid in self.sessions:
            data2uids[self.sessions[uid].data[Definitions.DATA_PATH]] = uid

        #Now for each data source we need to update the particular session which corresponds
        #with this data also keep track of which ids were updated, we will check the remaining ones
        #which were neither created nor updated to check for existance.
        updated_or_added_paths = set() 
        potential_duplicates = {}
        
        for data_source in data_sources:
            extractor = DataExtractor.DataExtractor(self.__projects_data, data_source)
            #Extract relevant information from the data paths.
            session_data = extractor.generate_session_data(analysis_sources) 
            if session_data == {}: 
                print(f'Was not able to determine the session id from path {data_source}, skipping...')
                continue

            #If we get here then the session_id will be either updated or added.
            updated_or_added_paths.add(session_data[Definitions.DATA_PATH])
            
            #Now update the duplicate map.
            metadata_source_path = extractor.get_metadata_source_directory()
            
            if session_data[Definitions.DATA_PATH] in data2uids:
                #Now lets update the sessions metadata and links.
                session_object = self.sessions[data2uids[session_data[Definitions.DATA_PATH]]]
                session_object.update(session_data, force_update)
                
                #Now add it to the potential_duplicates
                if metadata_source_path != '':
                    if not metadata_source_path in potential_duplicates:
                        potential_duplicates[metadata_source_path] = [session_object.get_uid()]
                    else:
                        potential_duplicates[metadata_source_path].append(session_object.get_uid())
                continue

            #Otherwise we need to create a new session object and add it ot the list.
            session_object = Session.Session(self.__database[Definitions.SESSIONS], uid = None)
            session_object.update(session_data,force_update = False)
            session_uid = session_object.get_uid()
            self.sessions[session_uid] = session_object

            #We also need to update that we added the a new session to the list.
            self.__database[self.parent_project].update_one({Definitions.MAP_ID : self.data[Definitions.MAP_ID]},
                                                {'$push'   : {Definitions.SESSION_DATA : session_uid}})
                
            #Now add it to the potential_duplicates
            if metadata_source_path != '':
                if not metadata_source_path in potential_duplicates:
                    potential_duplicates[metadata_source_path] = [session_object.get_uid()]
                else:
                    potential_duplicates[metadata_source_path].append(session_object.get_uid())
        
        #Now we need to add the new groups that have been created based on new data on the system.
        existing_dups = self.data[Definitions.DUPLICATES]
        for session_id in potential_duplicates:
            duplicate_list = potential_duplicates[session_id]
            duplicate_set = set(duplicate_list)
            if len(duplicate_list) == 1:
                continue

            #Otherwise now we need to check if the duplicate list already exists.
            duplicates_added = False
            duplicates_removed = False
            for index, old_duplicate_list in enumerate(existing_dups):
                old_duplicate_set = set(old_duplicate_list)
                
                #First check if a item has been removed from the known duplicates.
                #if so update the data to reflect this and move on.
                if duplicate_set.issubset(old_duplicate_set):
                    self.data[Definitions.DUPLICATES][index] = duplicate_list
                    duplicates_removed = True
                    break
                
                #If the old duplicate_set is not a subset of the new duplicates, then we can move on to the next one
                if not old_duplicate_set.issubset(duplicate_set):
                    continue

                #If the two lists are the same (disregarding order) then we dont need to add anything.
                if old_duplicate_set == duplicate_set:
                    duplicates_added = True
                    break

                #Otherwise we are at the situation where the new duplicate set contains elements
                #that the old set does not. In this case we just need to add the new elements.
                #(set the old one to the new one.
                self.data[Definitions.DUPLICATES][index] = duplicate_list
                duplicates_added = True
            
            #If this duplicate list wasnt added to an existing list nor
            #was a previously existing list modified then we need add a
            #new duplicate list.
            if not duplicates_added and not duplicates_removed:
                self.data[Definitions.DUPLICATES].append(duplicate_list)


        #Now lets go through all the uids and figure out which ones havent been updated or added and check that they all still
        #exist.
        to_check = set(data2uids.keys()) - updated_or_added_paths
        #Now check all the session ids we didnt hit.
        for data_path in to_check:
            session_uid = data2uids[data_path]
            self.__remove_session_if_not_on_fs(self.data[Definitions.MAP_ID], session_uid)
    
        #Now check that all the duplicates are still apart of the session list. If not we need to remove them. 
        duplicate_removal_indexes = [[] for i in range(len(self.data[Definitions.DUPLICATES]))]
        for group_index, duplicate_group in enumerate(self.data[Definitions.DUPLICATES]):
            for session_index, uid in enumerate(duplicate_group):
                if not uid in self.sessions:
                    duplicate_removal_indexes[group_index].append(session_index)


        #Now go through each of the indexes to remove backwards and remove them.
        for group_index in range(len(duplicate_removal_indexes) - 1, -1, -1):
            removal_group = duplicate_removal_indexes[group_index]

            #If there is only going to be one item left in the group, then remove the whole thing. 
            if len(self.data[Definitions.DUPLICATES][group_index]) - len(removal_group) <= 1:
                del self.data[Definitions.DUPLICATES][group_index]
                continue
            
            #Otherwise just remove the indexes from the group.
            for index_to_remove in reversed(removal_group):
                del self.data[Definitions.DUPLICATES][group_index][index_to_remove]

        self.__database[self.parent_project].update_one({Definitions.MAP_ID : self.data[Definitions.MAP_ID]},
                                            {'$set' : {Definitions.DUPLICATES: self.data[Definitions.DUPLICATES]}})
                
   
    #This session iterates through all the sessions that this subect owns currently in the database. 
    #If the sessions no longer exist then remove it from the database. If all the sessions were removed
    #Then delete this subject from the database.
    def check_fs_existance(self) -> None:
        #First check that the subject has been populated and the project has been set.
        if self.parent_project == '' or self.data == {}:
            print(f'The current subject has not had any data populated, cannot check fs existance.')
            return
        
        uids_to_check = list(self.sessions.keys()) #Copy this so we can iterate over these keys and delete them.
        for uid in uids_to_check:
            self.__remove_session_if_not_on_fs(self.data[Definitions.MAP_ID], uid)

        #Now check if all the sessions were removed.
        if self.sessions == {}:
            map_id = self.data[Definitions.MAP_ID]
            print(f'All data for subject with MAP ID: {map_id} no longer exists, removing...')
            #Remove the subject from the database.
            self.__database[self.parent_project].delete_one({Definitions.MAP_ID : map_id})

            del self.data
            self.data = {}

    #Load in subject data by uid.
    #Returns true if the subject was found and false otherwise.
    def global_load_by_uid(self, uid: ObjectId, extend_data: bool) -> bool:
        loaded = False 
        #To do this we have to search each collection until we find a resut that matches the given uid
        for project in self.__projects_data[Definitions.PROJECTS]:
            subject_data = self.__database[project].find_one({'_id':uid})

            if subject_data != None:
                self.data = subject_data
                loaded = True
                break

        if loaded:
            #Load in session information.
            self.__load_sessions(extend_data)

        return loaded
    
    def load_by_uid(self,  uid: ObjectId, extend_data: bool) -> bool:
        loaded = False 
        #To do this we have to search each collection until we find a resut that matches the given uid
        subject_data = self.__database[self.parent_project].find_one({'_id':uid})

        if subject_data != None:
            self.data = subject_data
            loaded = True

        if loaded:
            #Load in session information.
            self.__load_sessions(extend_data)

        return loaded

    def load_by_map_id(self, map_id: str, extend_data: bool) -> bool:

        subject_data = self.__database[self.parent_project].find_one({Definitions.MAP_ID:map_id})

        if subject_data == None:
            return False

        self.data = subject_data
        #Load in session information.
        self.__load_sessions(extend_data)
        return True
    
    def load_by_cnda_id(self, cnda_id: str, extend_data: bool) -> bool:

        subject_data = self.__database[self.parent_project].find_one({Definitions.SUBJECT_ACCESSION:cnda_id})

        if subject_data == None:
            return False

        self.data = subject_data
        #Load in session information.
        self.__load_sessions(extend_data)
        return True
    
    #This simply clears out the subject specific data. Good if you want to reuse the same subject object for multiple people
    #in a loop or something.
    def clear(self) -> None:
        del self.data
        del self.sessions
        
        self.data     = {}
        self.sessions = {}
    
    #Returns the existing data. Formats the session object_ids so that they are represented as their session_ids instead.
    def get_data(self) -> dict:
        #Check if the data for this subject has been populated yet.
        if self.data == {}:
            return {}
        
        all_data = self.data.copy()
        del all_data[Definitions.SESSION_DATA]
        all_data[Definitions.SESSION_DATA] = []

        #Now lets populate the Session_Data entry with the data from each session object.
        for uid in self.sessions:
            session_id = self.sessions[uid].data[Definitions.SESSION_ID]
            all_data[Definitions.SESSION_DATA].append(session_id)
        
        return all_data
    
    #Return a Session object based on a session id.
    def get_session_by_session_id(self, session_id: str) -> Session.Session | None:
        if self.data == {}:
            return None

        for uid in self.sessions:
            if self.sessions[uid].data[Definitions.SESSION_ID] == session_id:
                return self.sessions[uid] 
        
        return None

    
    #This function returns the expanded representation of its internal data. 
    def get_expanded_data(self) -> dict:
        #Check if the data for this subject has been populated yet.
        if self.data == {}:
            return {}
        
        all_data = self.data.copy()
        del all_data[Definitions.SESSION_DATA]
        all_data[Definitions.SESSION_DATA] = {}
        

        #Now lets populate the Session_Data entry with the data from each session object.
        for uid in self.sessions:
            session_data = self.sessions[uid].data.copy()
            session_data.update(self.sessions[uid].extended_data.copy())
            
            self.__format_modalities_list(session_data)
            all_data[Definitions.SESSION_DATA][str(uid)] = session_data
        
        return all_data
    
    def get_expanded_duplicate_dataframe(self) -> pandas.DataFrame:
        if self.data == {}:
            return pandas.DataFrame()
        
        all_data = self.data.copy()
        del all_data[Definitions.SESSION_DATA]
        all_data[Definitions.SESSION_DATA] = {}

        for duplicate_group in self.data[Definitions.DUPLICATES]:
            for session_uid in duplicate_group:
                session_data = self.sessions[session_uid].data.copy()
                session_data.update(self.sessions[session_uid].extended_data.copy())

                self.__format_modalities_list(session_data)
                all_data[Definitions.SESSION_DATA][str(session_uid)] = session_data

        return CustomFlatten.dict_to_dataframe(all_data, exclude_columns = self.__cols_to_remove)

    def get_expanded_dataframe(self) -> pandas.DataFrame:
        return CustomFlatten.dict_to_dataframe(self.get_expanded_data(), exclude_columns = self.__cols_to_remove)

    def get_session_dataframe_by_session_id(self, session_id: str, fuzzy_match_level: int) -> pandas.DataFrame:


        if self.data == {}:
            return pandas.DataFrame()
        
        #Copy over the subject specific information
        all_data = self.data.copy()
        del all_data[Definitions.SESSION_DATA]
        all_data[Definitions.SESSION_DATA] = {}

        for uid in self.sessions:
            sess_id_to_check = self.sessions[uid].data[Definitions.SESSION_ID]
            if fuzzy_match_session_ids(sess_id_to_check, session_id, fuzzy_match_level):
                
                all_data[Definitions.SESSION_DATA][str(uid)] = self.sessions[uid].data
                return CustomFlatten.dict_to_dataframe(all_data, exclude_columns = self.__cols_to_remove)
        
        #If we dont find it return an empty dataframe.
        return pandas.DataFrame()
