import pymongo
import os
import copy

import src.DataModels.AnalysisDefinitions as AnalysisDefinitions
import src.DataModels.Definitions as Definitions
import src.DataModels.ColumnNames as ColumnNames
import src.InformationPrompter as IP 
import src.DataExtraction as DataExtraction 
import src.Analysis as Analysis
import src.Utils.Logger as Logger
import src.Utils.DBDocument as DBDocument

class Session(DBDocument.DBDocument):
    '''Interacts with the mongoDB database. Used to interact with Session level data.
    
    '''

    def __init__(self, 
                 collection: pymongo.collection.Collection, 
                 analysis_collection: pymongo.collection.Collection,
                 logger: Logger,
                 uid = None, 
                 load_extended_data = False) -> None:
        '''Initalizes the session object using the DBDcoument as a base class.

        Parameters:
            collection (pymongo.collection) : The collection this document resides in.
            logger     (Logger)             : The logger class for this document.
            uid        (ObjectId | None )   : The ObjectId to associate with this class. If None then a new document 
                                              will be created.
            load_extended_data (bool)       : A flag which will cause extended data to be loaded from the FS.
        
        Attrributes:
            extended_data (dict) : A dictionary storing used source files and unlinked source files found in Scans.
            analysis      (dict[str -> Analysis]) : A dictionary storing the analysis type (str) and the Analysis
                                                    object.
        '''
        

        super().__init__(collection, logger, uid)
        
        self.extended_data = {}
        if load_extended_data:
            found_files = DataExtraction.get_dicom_files_from_path(self.data[ColumnNames.DATA_PATH])
            self.extended_data[Definitions.DICOM_LIST] = found_files

            self.extended_data[Definitions.UNLINKED_DICOM_LIST] = DataExtraction.get_unlinked_dicom_files_from_path(
                self.data[ColumnNames.DATA_PATH], 
                found_files
            )
        
        self.__analysis_collection = analysis_collection
        self.analysis = {}
        self.__load_analysis()

    def __load_analysis(self) -> None:

        if self.data == None:
            return
        
        if not AnalysisDefinitions.ANALYSIS in self.data:
            return
            
        for uid in self.data[AnalysisDefinitions.ANALYSIS]:

            #Load in the session objects
            analysis_object = Analysis.Analysis(self.__analysis_collection,
                                                self._logger,
                                                uid=uid)

            self.analysis[analysis_object.get_type()] = analysis_object
    
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

    #Validates data to ensure that all the required fields are present.
    def _validate_data(self) -> bool:
        '''Implementation of which validates that the internal data contains required fields.
        '''
        required_keys = {
            ColumnNames.SESSION_ID           : str,
            ColumnNames.SESSION_ACCESSION    : str,
            ColumnNames.FS_ACCESSION         : str,
            ColumnNames.DATA_PATH            : str,
            Definitions.FS_VERSION           : str,
            Definitions.SCANNER              : str,
            Definitions.PIPELINE_VERSION     : str,
            Definitions.SOFTWARE_VERSION     : str,
            Definitions.PROC_STATUS          : str,
            Definitions.MODS_COLLECTED       : dict,
            AnalysisDefinitions.ANALYSIS     : list
        }

        matching = True
        for key, value in required_keys.items():
            if not key in self.data or value != type(self.data[key]):
                matching = False
                break

        return matching

    def get_report_ready_data(self, include_analysis: bool) -> dict:
        
        #Get the session data.
        session_data = copy.deepcopy(self.data)
        
        #If we want to load in the extended data do it here.
        if len(self.extended_data) > 0:
            session_data.update(self.extended_data)

        self.__format_modalities_list(session_data)
        
        del session_data[AnalysisDefinitions.ANALYSIS]
    
        if include_analysis and len(self.analysis) > 0:
            session_data[AnalysisDefinitions.ANALYSIS] =  {}

            for analysis_type, analysis in self.analysis.items():
                session_data[AnalysisDefinitions.ANALYSIS][analysis_type] = analysis.get_report_ready_data()
        
        return session_data

    def get_data_path(self) -> str:
        '''Returns the data path for the current session.
        '''

        if self.data != None:
            return self.data[ColumnNames.DATA_PATH]

        return ''
    
    def update(self, metadata: dict, force_update : bool) -> None:
        '''Defines the update function for the session document.

        If force_update False is then use the SessionInformationPrompter prompt_conflicting_information function to 
        resolve conflicts (ask the user). If True then force overwrite data with incoming data.

        Parameters:
            metadata (dict) : Incoming metadata.
            force_update (bool) : Force the update of incoming data if True, ask for user confirmation otherwise.
        '''

        conflict_behavior = None
        if not force_update:
            session_info_prompt = IP.SessionInformationPrompter(self)
            conflict_behavior = session_info_prompt.prompt_conflicting_information

        super().update(metadata, conflict_behavior)
            

    #This function just checks if the current session exists on the file system.
    #Returns T/F accordingly.
    def fs_existance(self) -> bool:
        '''Check if this session exists on the UNP filesystem.

        Returns:
            existance (bool) : Returns T/F based on if the session exists on the filesystem.
        '''

        if self.get_data_path() == '':
            self._logger.log('The session object was not loaded, no data path exists.')
            return False

        return os.path.isdir(self.get_data_path())


    def set_analysis_paths(self, possible_analysis_files: set) -> None:
        '''This function takes a list of possible analysis paths and distrubutes them to the right analysis.

        This function takes a list of possible analysis files which pertain to this session and distrubutes them to 
        the correct analysis object. The way this is determined is by the analysis type. This is found out through
        the file name and string matching based on file extension and "contains" patterns defined in
        AnalysisDefinitions.

        Parameters:
            possible_analysis_files (list[str]) : The list of analysis files pertaining to this session.
        '''
        #First sort out what each analysis everything goes to.
        sorted = {}
        for path in possible_analysis_files:
            
            analysis_info = DataExtraction.get_analysis_information_from_path(path)
            if analysis_info == None:
                continue
            
            #Unpack values
            session_id, analysis_type, file_type = analysis_info
            
            #Sort the values out.
            if not analysis_type in sorted:
                sorted[analysis_type] = {
                    file_type : { path }
                }
                continue
            
            if not file_type in sorted[analysis_type]:
                sorted[analysis_type][file_type] = { path }
                continue

            sorted[analysis_type][file_type].add(path)
        
        #Now find the right analysis and add this path to it.
        for analysis_type, file_groups in sorted.items():
            
            #If it doesnt exist, create it.
            if not analysis_type in self.analysis:
                
                #Set the initial values for the analysis document.
                initial_values = { 
                    AnalysisDefinitions.ANALYSIS_TYPE : analysis_type,
                }
                for group, paths in file_groups.items():
                    initial_values[group] = list(paths)

                self.analysis[analysis_type] = Analysis.Analysis(self.__analysis_collection, 
                                                                 self._logger,
                                                                 initialize = initial_values)

                self.append_to_list(AnalysisDefinitions.ANALYSIS, self.analysis[analysis_type]._uid)
                continue
            
            #Update the file groups. Go through all possible groups. If the group isnt hit make sure each of the
            #files still exist.
            
            for group in AnalysisDefinitions.ANALYSIS_TYPES[analysis_type]:
                if group in file_groups:
                    self.analysis[analysis_type].update({group : list(file_groups[group])})
                else:
                    self.analysis[analysis_type].check_fs_existance()


