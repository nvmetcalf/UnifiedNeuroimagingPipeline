import os
import glob
import json
import regex

import src.DataModels.Definitions as Definitions
import src.DataModels.ColumnNames as ColumnNames 
import src.DataModels.AnalysisDefinitions as AnalysisDefinitions
import src.Utils.Logger as Logger

def guess_map_id_from_path(sub_ses_path: str) -> str: 
    '''Try to extract the map ID from a given path to a subject/session pair.

    Attempts to guess what the map_id is from the path. Assumes that the naming convention is 
    sub-<MAP_ID>_ses-<SES_ID>.

    Parameters:
        sub_ses_path (str) : The path to extract a MAP ID from. 
    
    Returns:
        map_id (str) : The ID extracted from the string. Returns '' if fails.
    '''

    map_id = '' 
    
    #find the index for 'sub-'.
    try:
        sub_index = sub_ses_path.index('sub-')
        ses_index = sub_ses_path.index('_ses-')
        map_id = sub_ses_path[sub_index + 4 : ses_index] # cut out 'sub_' from the id
    except ValueError:
        print(f'Could not find a map id for the path {sub_ses_path}')

    return map_id 

def guess_sess_id_from_path(sub_ses_path: str) -> str: 
    '''Try to extract the session ID from a given path to a subject/session pair.

    Attempts to guess what the session_id is from the path. Assumes that the naming convention is 
    sub-<MAP_ID>_ses-<SES_ID>.

    Parameters:
        sub_ses_path (str) : The path to extract a session ID from. 
    
    Returns:
        session_id (str) : The session ID extracted from the string. Returns '' if fails.
    '''

    sess_id = '' 
    strings_to_search = sub_ses_path.split(os.sep) 
    

    #find the index for '_ses-'.
    for dir in strings_to_search:
        if not '_ses-' in dir:
            continue

        ses_index = dir.index('_ses-')
        sess_id = dir[ses_index + 5:] #cut out the '_ses-' from the id
        break
    return sess_id

def get_dicom_files_from_path(sub_ses_path: str) -> list:
    '''Extract the dicom files found in a given subject/session folder.

    Parameters:
        sub_ses_path (str) : The path to the subject/session folder. 
    
    Returns:
        dicom_files (list[str]) : The list of the dicom files that match the allowed extensions found in 
                                  Definitions.NIFTI_EXTENSIONS
    '''

    dicom_files = []
    for ext in Definitions.NIFTI_EXTENSIONS:
        full_paths = glob.glob(os.path.join(sub_ses_path, f'dicom/*.{ext}'))
        dicom_files += [ os.path.basename(path) for path in full_paths ]

    return dicom_files

def get_unlinked_dicom_files_from_path(sub_ses_path: str, found_files: list) -> list:
    '''Return the dicom files that do not appear in the subject/session folder.

    Find all the files found in the source location (Scans) that are not present in the dicom folder of the given 
    subject/session folder.

    Parameters:
        sub_ses_path (str)       : The path to the subject/session folder. 
        found_files  (list[str]) : A list of the files present in the given subject/session folder.
    
    Returns:
        dicom_files (list[str]) : The list of dicom files that were not present in the subject/session folder.
    '''
    
    #Now lets find the scan source files.
    source_dir = ''
    for nifti_file in found_files:
        try:
            source_dir = os.path.dirname(os.readlink(os.path.join(sub_ses_path, 'dicom', nifti_file)))
            break
        except OSError:
            pass

    if source_dir == '':
        return []

    #Otherwise we need to find all the files not in the found_file list.
    source_nifti_files = []
    for ext in Definitions.NIFTI_EXTENSIONS:
        found_files = glob.glob(os.path.join(source_dir, f'*.{ext}'))
        source_nifti_files += [ os.path.basename(file) for file in found_files ]

    return list(set(source_nifti_files) - set(found_files))

def guess_session_id_from_analysis_path(analysis_path: str) -> str:
    '''Attempt to extract the session ID from the provided analysis path.

    Parameters:
        analysis_path (str) : The path to the analysis file.
    
    Returns:
        session_id (str) : The session_id extracted from the analysis path. Returns '' if fails.
    '''
    
    session_id = ''
    ses_and_ext = guess_sess_id_from_path(analysis_path)

    #Now loop through and check if any of the file endings and extensions match.
    for analysis_type in AnalysisDefinitions.ANALYSIS_TYPES:
        for file_type in AnalysisDefinitions.ANALYSIS_TYPES[analysis_type]:
            for flag in AnalysisDefinitions.ANALYSIS_TYPES[analysis_type][file_type]['FILE_TYPE']:
                for ext in AnalysisDefinitions.ANALYSIS_TYPES[analysis_type][file_type]['FILE_EXTENSIONS']:
                    ending = f'{flag}.{ext}'
                    if ses_and_ext.endswith(ending):
                        return ses_and_ext.replace(f'_{ending}','')

    return session_id

def get_analysis_information_from_path(analysis_path: str) -> tuple | None:
    '''Given a path to an analysis file, return the matched session_id, the analysis type, and the file type.

    Parameters:
        analysis_path (str) : The path to the analysis file.
    
    Returns:
        info (tuple[str, str, str]) : A tuple containing the extracted session_id, the analysis type, and the type
                                      of analysis file.
    '''
    
    base_name = os.path.basename(analysis_path)
    analysis_type = ''
    file_type = ''
    matched_sub_string = ''
    matched_extension = ''

    for possible_type, file_groups in AnalysisDefinitions.ANALYSIS_TYPES.items():
        for possible_file_type, file_group in file_groups.items():
            for file_name in file_group['FILE_TYPE']:
                if file_name in base_name:
                    analysis_type = possible_type
                    file_type = possible_file_type
                    matched_sub_string = file_name
                    
                    for ext in file_group['FILE_EXTENSIONS']:
                        if base_name.endswith(ext):
                            matched_extension = ext
                            break
                    break
    
    if analysis_type == '' or matched_extension == '':
        return None
    
    #Otherwise we have found the extension and sub string. 
    base_name = base_name.replace(f'_{matched_sub_string}.{matched_extension}','')
    
    #Return the session_id, analysis_type, and file_type.
    return (guess_sess_id_from_path(base_name), analysis_type, file_type)

class DataExtractor(object):
    '''Handles the extraction of data from the local file system and UNP.

    Attributes:
        __projects_data  (dict) : The projects_data dict extracted from the mongoDB database.
        __data_path      (str)  : The path pointing to the current sub/ses folder to extract from.
        __parameter_data (dict) : Extracted data from the ".params" file for the sub/ses. Data extracted based on the 
                                  regex rules definted in Definitions.REGEX_RULES.
        metadata_source  (str)  : The path pointing to a nifti json header from the associated session.
        dicom_metadata   (dict) : The extracted metadata from the "metadata_source" json file. Keys are chosen from 
                                  Definitions.DICOM_TAGS.
    Requirements:
        This class uses the "regex" module rather than the default "re" module. The reason for this is that there is a
        bug in the regex parsing which causes catestrophic bracktracking to occur. This causes the program to hang and
        eventually for a stack overflow to occur (I think if I am remembering right). Anyways the "regex" module 
        allows for timeout options. Ideally this would eventually be fixed and would move back to "re".
    '''

    def __init__(self, 
                 projects_data: dict, 
                 data_path: str,
                 logger: Logger):
        '''Initialize the data extractor class.

        Set relevant attributes and initialize relevant data. Data which is used for multiple extraction methods is
        extracted once here first. Namely, all relevant DICOM header information and params file data is extracted
        here based on the definitions in Definitions.DICOM_TAGS and Definitions.REGEX_RULES respectively.

        Parameters:
            projects_data (str)    : The projects_data dictionary found in the mongoDB database.
            data_path     (str)    : The path to the sub/ses folder of interest.
            logger        (Logger) : A logger object.
        '''

        self.__projects_data = projects_data
        self.__data_path     = data_path
        self.__logger        = logger
        self.metadata_source = ''
        self.dicom_metadata  = {}
        
        #Okay now try to find a suitable json file which has all the data we need.
        json_files = glob.glob(os.path.join(data_path, 'dicom/*.json'))
        found_file        = False 
        found_data_source = False
        for file in json_files:
            try:
                scan_file = open(file, 'r')
                 
                try:
                    json_data = json.load(scan_file)

                    for field in Definitions.DICOM_TAGS:
                        for tag_to_extract in Definitions.DICOM_TAGS[field]:
                            if (not tag_to_extract in self.dicom_metadata) and tag_to_extract in json_data:
                                self.dicom_metadata[field] = json_data[tag_to_extract]
                    
                    #We found at least one file
                    found_file = True
                    
                except json.decoder.JSONDecodeError:
                    self.__logger.log((f'It appears the file {file} is not formed correctly. '
                           f'Attempting to guess scanner from path.'))
                
                #Now attempt to find the data source for this data.
                try:
                    json_source = os.readlink(file)
                    self.metadata_source = os.path.abspath(os.path.dirname(json_source))
                    found_data_source = True
                except OSError:
                    self.__logger.log(f'The file {file} does not appear to be a symlink, trying a different json file.')


                scan_file.close()
            except FileNotFoundError:
                self.__logger.log((f'It appears that the file {file} was found but does not exist. '
                       f'Check symbolic link health. Checking next file...'))

            #If we have found all the keys by now then we are good.
            if found_data_source and (set(self.dicom_metadata.keys()) == set(Definitions.DICOM_TAGS.keys())):
                break

        if not found_file:
            self.__logger.log(f'Could not find any json metadata at {os.path.join(data_path, "dicom")}.')

        #Now lets parse the params file and store associated data.
        self.__parameter_data = {
            'RULES'      : {},
            'MODALITIES' : {},
        }

        self.__parameter_file_lists = {}

        params_path = os.path.join(self.__data_path, f'{os.path.basename(os.path.normpath(self.__data_path))}.params')
        regex_string = ''
        line = ''

        try:
            params_file = open(params_path, 'r')
            for line in params_file:
                found_match = False
                for category in Definitions.REGEX_RULES: 
                    for key in Definitions.REGEX_RULES[category]:
                        regex_string = rf'{Definitions.REGEX_RULES[category][key]}'
                        match = regex.match(regex_string, line, timeout = 1)
                        if match:
                            self.__parameter_data[category][key] = match
                            found_match = True
                            break

                    if found_match:
                        break
                        
            params_file.close()
        except TimeoutError:
            self.__logger.log((f'Could not resolve the file names at: {line} '
                   f'due to catastrophic backtracking with regex: {regex_string}'))
        except FileNotFoundError:
            self.__logger.log((f'Could not find a params file at the location {params_path}, could not check '
                               'collected modalities'))

        #Go through and actually expand the parsed modality lists into real file lists.
        for mod, re_match in self.__parameter_data['MODALITIES'].items():
            self.__parameter_file_lists[mod] = regex.sub(r'[\(\)\'"]', '',  re_match.group(5)).split()


    def guess_scanner(self) -> str:
        '''Try to determine the scanner name.

        First tries to extract the scanner name from the dicom metadata. If this is not successful then fall back to
        guessing the scanner name based on the data path. Generally the scanner name is included in the project
        alias name.
        
        Returns:
            scanner (str) : The scanner extracted. Returns '' if fails.
        '''

        if Definitions.MODEL_NAME in self.dicom_metadata:
            return self.dicom_metadata[Definitions.MODEL_NAME]

        self.__logger.log('Cannot determine the scanner from json metadata, attempting to guess scanner from path.')
        
        scanner = ''
        keys_to_check = []
        try:
            keys_to_check = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.SCANNER_NAMES].keys()
        except KeyError:
            self.__logger.log(('Could not find a Scanner_Names definition in the database projects information. '
                   'Make sure this is defined.'))
        
        for key in keys_to_check:
            if key.lower() in self.__data_path.lower(): #Ignore case for an easier match.
                scanner = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.SCANNER_NAMES][key]
                break

        return scanner 
    
    def extract_fs_build_stamp(self) -> str:
        '''Extract the Freesurfer build stamp.

        Attempts to read the build stamp from the Freesurfer logs, specifically from the file
        `Freesurfer/scripts/build-stamp.txt`. If the file is not found, returns an empty string.

        Returns:
            build_stamp (str) : The extracted build stamp or '' if fails.
        '''

        stamp_path = os.path.join(self.__data_path, 'Freesurfer/scripts/build-stamp.txt')

        #First try to scrape this data from the freesurfer logs. Specifically from ./Freesurfer/scripts/build-stamp.txt
        try:
            log_file = open(stamp_path, 'r')
            build_stamp = log_file.readline().rstrip()
            log_file.close()

            return build_stamp

        except FileNotFoundError:
            return '' 

    def check_modalities(self) -> dict:
        '''Check the available imaging modalities.

        Iterates through params data to count the number of files available for each modality.

        Returns:
            mods_collected (dict) : A dictionary where keys are modality names and values are the corresponding file 
                                    counts.
        '''

        mods_collected = {}
        for key, file_list in self.__parameter_file_lists.items():
            mods_collected[f'NUM_{key}'] = len(file_list) 

        return mods_collected
    
    def get_MB_level(self) -> int:
        '''Retrieve the multi-band factor (MB level).

        Checks if the MB factor is defined in the parameter data and extracts it if available.

        Returns:
            factor (int) : The MB factor value, or 0 if it is not defined.
        '''

        if 'MB_FACTOR' in self.__parameter_data['RULES']:
            return int(self.__parameter_data['RULES']['MB_FACTOR'].group(5))

        return 0

    def get_BOLD_params(self) -> dict:
        '''Gather important BOLD variables from the BOLD sessions.
            
        Extract the BOLD TR, TE, voxel size from the BOLD sessions. 
        '''
        
        if not 'BOLD' in self.__parameter_file_lists:
            return {}

        bold_files = self.__parameter_file_lists['BOLD']
        extracted_params = {
            AnalysisDefinitions.BOLD_TR         : 0,
            AnalysisDefinitions.BOLD_TE         : 0,
        }

        #Go through each BOLD file and extract these files from the JSON metadata.
        #If a value cannot be found then try to get it from the other files metadata.
        #Load in each json file, filling in params as needed. If params are not found, go to the next file.
        extracted_values = 0
        for fname in bold_files:

            json_fname = ''
            for extension in Definitions.NIFTI_EXTENSIONS:
                if fname.endswith(extension):
                    json_fname = f'{fname[:(len(fname) - len(extension))]}json'
                    break

            if json_fname == '':
                continue
            
            #Check that the found json metadata file actually exists.
            json_metadata_path = os.path.join(self.__data_path, Definitions.DICOM_DIR, json_fname)
            if not os.path.exists(json_metadata_path):
                continue
            
            try:
                json_file = open(json_metadata_path, 'r')
                json_data = json.load(json_file) 
                json_file.close()
            except Exception as e:
                self.log(f'Could not load the json metadata at {json_metadata_path}, Error {e}')

            for key in extracted_params:
                #Skip if we already extracted it.
                if extracted_params[key] != Definitions.MISSING_BY_TYPE[type(extracted_params[key])]:
                    continue

                json_key = AnalysisDefinitions.BOLD_METADATA_KEYS[key]
                
                #Parse the json_key.
                json_key_data = None
                access_level = json_data
                parsed_keys = json_key.split('.')

                for index, parsed_key in enumerate(parsed_keys):
                    if parsed_key in access_level:

                        #Check if we are at the end
                        if index == len(parsed_keys) - 1:
                            json_key_data = access_level[parsed_key]
                            break

                        #Otherwise move up the access level
                        access_level = access_level[parsed_key]
                
                if json_key_data != None:
                    extracted_params[key] = json_key_data
                    extracted_values += 1

            if extracted_values == len(extracted_params):
                break
        
        #Remove values that could not be extracted. 
        
        keys_to_remove = set()
        for key, value in extracted_params.items():
            if value == Definitions.MISSING_BY_TYPE[type(value)]:
                keys_to_remove.add(key) 

        for key in keys_to_remove:
            del extracted_params[key]

        return extracted_params

    def guess_processing_status_from_path(self) -> str:
        '''Determine the processing status from the data path.

        Attempts to identify the processing status by searching for known keywords in the data path.
        Falls back to an empty string if no match is found.

        Returns:
            status (str) : The guessed processing status or '' if fails.
        '''

        processing_status = ''
        try:
            allowed = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.ALLOWED_PROC_STATUSES]
            keys_to_check = allowed.keys()
        except KeyError:
            self.__logger.log(('Could not find a Processing_Status definition in the projects data path. '
                   'Make sure this is defined.'))

        for key in keys_to_check:
            if key.lower() in self.__data_path.lower(): #Ignore case for an easier match.
                processing_status = allowed[key]
                break
        
        return processing_status

    def get_metadata_source_directory(self) -> str:
        '''Retrieve the metadata source directory.

        Returns:
            metadata_source (str) : The metadata source directory, or '' if fails.
        ''' 

        if self.metadata_source == '':
            self.__logger.log('Could not extract find data source.')
            return ''
        return self.metadata_source 

    def guess_software_version_from_path(self) -> str:
        '''Determine the software version from metadata.

        Extracts the software version from DICOM metadata. If the software version is not available, returns an empty 
        string.

        Returns:
            version (str) : The extracted software version, or an empty string if unavailable.
        ''' 

        if not 'SOFTWARE_VERSION' in self.dicom_metadata:
            self.__logger.log('Could not extract software version from json metadata.')
            return ''
        
        return self.dicom_metadata['SOFTWARE_VERSION']

    def guess_pipeline_version_from_path(self) -> str:
        '''Determine the pipeline version from processing parameters.

        Searches for processing parameter files in the data path and extracts the pipeline version.
        If no valid file is found, self.__logger.logs an error message and returns an empty string.

        Requirements:
            For the processing params file to have been generated UNP must have been run already to generate it.

        Returns:
            pipeline_version (str) : The extracted pipeline version, or an empty string if unavailable.
        ''' 

        proc_params_paths = glob.glob(os.path.join(self.__data_path, 'Processing*.params')) 

        #Try to scrape this data from the freesurfer logs. Specifically from ./Processing*.params
        if len(proc_params_paths):
            #Get the first one and attempt to read in the ManufacturersModelName.
            try:
                params_file = open(proc_params_paths[0], 'r')
                pipeline_version = '' 

                #Go through each line and try to find the path to the pipeline version.
                for line in params_file:
                    if Definitions.PIPELINE_VERSION_TAG in line:
                        path = line.replace(Definitions.PIPELINE_VERSION_TAG, '').strip()
                        pipeline_version = os.path.basename(path)
                        break

                params_file.close()
                return pipeline_version 

            except FileNotFoundError:
                self.__logger.log((f'It appears that the file {proc_params_paths[0]} was found but does not exist. '
                       f'Check symbolic link health.'))
        else:
            self.__logger.log((f'No processing parameters found at {self.__data_path}, '
                   f'could not determine the software version used.'))

        return ''

    def check_for_session_bpass_smoothing(self, sub_ses: str) -> bool:
        '''Check if bold bandpass smoothing was performed for a session.

        Looks for the existence of the smoothed rsfMRI file in the current sub/ses folder.

        Arguments:
            sub_ses (str) : The subject session identifier.

        Returns:
            bandpass (bool) : True if the bandpass smoothing file is found, otherwise False.
        '''

        if os.path.isfile(os.path.join(self.__data_path, 
                                       'Functional/Volume', 
                                       f'{sub_ses}{AnalysisDefinitions.BOLD_BANDPASS_EXTENSION}')):
            return True

        return False
    
    def check_for_session_resid_smoothing(self, sub_ses: str) -> bool:
        '''Check if bold resid smoothing was performed for a session.

        Looks for the existence of the residual smoothing rsfMRI file in the current sub/ses folder.

        Arguments:
            sub_ses (str) : The subject session identifier.

        Returns:
           resid (bool) : True if the residual smoothing file is found, otherwise False.
        '''

        if os.path.isfile(os.path.join(self.__data_path, 
                                       'Functional/Volume', 
                                       f'{sub_ses}{AnalysisDefinitions.BOLD_RESID_EXTENSION}')):
            return True

        return False

    # ------------------------- SUBJECT and SESSION data models -------------------------
    def generate_session_data(self) -> dict:
        '''Generate a dictionary containing session metadata.

        This function gathers various metadata attributes related to the session by extracting information
        from the data path, DICOM metadata, and other processing logs.

        Arguments:
            discovered_analysis (list): A list of analysis paths to be included in the session metadata.

        Returns:
            session_metadata_to_update (dict)      : A dictionary containing session metadata with the following keys:
                - SESSION_ID           (str)       : Extracted session ID from the data path.
                - SESSION_ACCESSION    (str)       : Placeholder for session accession.
                - DATA_PATH            (str)       : Path to the session data.
                - FS_VERSION           (str)       : FreeSurfer version extracted from logs.
                - FS_ACCESSION         (str)       : Placeholder for FreeSurfer accession.
                - SCANNER              (str)       : Scanner name extracted from metadata or guessed from path.
                - PIPELINE_VERSION     (str)       : Pipeline version from processing logs.
                - SOFTWARE_VERSION     (str)       : Software version extracted from metadata.
                - PROC_STATUS          (str)       : Processing status guessed from data path.
                - MODS_COLLECTED       (dict)      : Collected imaging modalities and counts.
                - ANALYSIS             (list[str]) : Analysis information based on provided paths.
        '''

        session_id = guess_sess_id_from_path(self.__data_path) 
        if session_id == '':
            self.__logger.log(f'Unable to determine the session id from the path {self.__data_path}, skipping...')
            return {}

        #There may be a way to do this dynamically which would be cool for extensibility.
        #For now lets just hard code in the data we get here.
        session_metadata_to_update = {
            ColumnNames.SESSION_ID                   : session_id,
            ColumnNames.SESSION_ACCESSION            : '',
            ColumnNames.DATA_PATH                    : self.__data_path,
            Definitions.FS_VERSION                   : self.extract_fs_build_stamp(),
            ColumnNames.FS_ACCESSION                 : '',
            Definitions.SCANNER                      : self.guess_scanner(),
            Definitions.PIPELINE_VERSION             : self.guess_pipeline_version_from_path(),
            Definitions.SOFTWARE_VERSION             : self.guess_software_version_from_path(),
            Definitions.PROC_STATUS                  : self.guess_processing_status_from_path(),
            Definitions.MODS_COLLECTED               : self.check_modalities(),
            AnalysisDefinitions.ANALYSIS             : []
        }

        return session_metadata_to_update
