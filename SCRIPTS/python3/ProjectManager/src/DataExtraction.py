import os
import glob
import json
import regex
from datetime import datetime
import src.DataModels.Definitions as Definitions

#Attempts to guess what the map_id is from the path. Assumes that the naming convention is sub-<MAP_ID>_ses-<SES_ID>.
#Returns -1 if no map_id is found.
def guess_map_id_from_path(sub_ses_path: str) -> str: 
    map_id = '' 
    
    #find the index for 'sub-'.
    try:
        sub_index = sub_ses_path.index('sub-')
        ses_index = sub_ses_path.index('_ses-')
        map_id = sub_ses_path[sub_index + 4 : ses_index] # cut out 'sub_' from the id
    except ValueError:
        print(f'Could not find a map id for the path {sub_ses_path}')

    return map_id 

#Attempts to guess what the map_id is from the path. Assumes that the naming convention is sub-<MAP_ID>_ses-<SES_ID>.
#Returns -1 if no map_id is found.
def guess_sess_id_from_path(sub_ses_path: str) -> str: 
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
    dicom_files = []
    for ext in Definitions.NIFTI_EXTENSIONS:
        full_paths = glob.glob(os.path.join(sub_ses_path, f'dicom/*.{ext}'))
        dicom_files += [ os.path.basename(path) for path in full_paths ]

    return dicom_files

#Returns a list of NIFTI files which do not appear in the original dicom folder.
#Takes in a list of found files as an argument.
def get_unlinked_dicom_files_from_path(sub_ses_path: str, found_files: list) -> list:
    
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

#Attempts to determine the modality based on the given analysis path.
#Returns '' if no modality can be determined.
def guess_modality_from_path(analysis_path: str) -> str:
    modality = ''
    for mod in Definitions.ANALYSIS_FILE_TYPES:
        for flag in Definitions.ANALYSIS_FILE_TYPES[mod]:
            if flag in analysis_path:
                modality = mod
                break

        if modality != '':
            break

    return modality

def guess_session_id_from_analysis_path(analysis_path: str) -> str:
    session_id = ''
    ses_and_ext = guess_sess_id_from_path(analysis_path)
    #Now loop through and check if any of the file endings and extensions match.
    for mod in Definitions.ANALYSIS_FILE_TYPES:
        for flag in Definitions.ANALYSIS_FILE_TYPES[mod]:
            for ext in Definitions.ANALYSIS_FILE_EXTENSIONS[mod]:
                ending = flag+ext
                if ses_and_ext.endswith(ending):
                    return ses_and_ext.replace(f'_{ending}','')


    return session_id
                

class DataExtractor(object):
    def __init__(self, 
                 projects_data: dict,
                 data_path: str):

        self.__projects_data = projects_data
        self.__data_path     = data_path
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
                    print(f'It appears the file {file} is not formed correctly. Attempting to guess scanner from path.')
                
                
                #Now attempt to find the data source for this data.
                try:
                    json_source = os.readlink(file)
                    self.metadata_source = os.path.abspath(os.path.dirname(json_source))
                    found_data_source = True
                except OSError:
                    print(f'The file {file} does not appear to be a symlink, trying a different json file.')


                scan_file.close()
            except FileNotFoundError:
                print(f'It appears that the file {file} was found but does not exist. Check symbolic link health. Checking next file...')

            #If we have found all the keys by now then we are good.
            if found_data_source and (set(self.dicom_metadata.keys()) == set(Definitions.DICOM_TAGS.keys())):
                break

        if not found_file:
            print(f'Could not find any json metadata at {os.path.join(data_path, "dicom")}.')

        #Now lets parse the params file and store associated data.
        self.__parameter_data = {
            'RULES'      : {},
            'MODALITIES' : {}
        }

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
            print(f'Could not resolve the file names at: {line} due to catastrophic backtracking with regex: {regex_string}')
        except FileNotFoundError:
            print(f'Could not find a params file at the location {params_path}, could not check collected modalities')

    #Attempts to guess what the scanner is from the path. Looks at the project file for
    #predefined naming conventions.
    #Returns an empy string if no substring closely matches what is defined in the naming conventions.
    def guess_scanner_from_path(self) -> str:

        if 'MODEL_NAME' in self.dicom_metadata:
            return self.dicom_metadata['MODEL_NAME']

        print(f'Cannot determine the scanner from json metadata, attempting to guess scanner from path.')
        
        scanner = ''
        keys_to_check = []
        try:
            keys_to_check = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.SCANNER_NAMES].keys()
        except KeyError:
            print(f'Could not find a Scanner_Names definition in the database projects information. Make sure this is defined.')
        
        for key in keys_to_check:
            if key.lower() in self.__data_path.lower(): #Ignore case for an easier match.
                scanner = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.SCANNER_NAMES][key]
                break

        return scanner 

    #Attempts to guess what the freesurfer version is from the path. Looks at the project file for
    #predefined naming conventions.
    #Returns an empy string if no substring closely matches what is defined in the naming conventions.
    def guess_fs_version_from_path(self) -> str: 
        stamp_path = os.path.join(self.__data_path, 'Freesurfer/scripts/build-stamp.txt')

        #First try to scrape this data from the freesurfer logs. Specifically from ./Freesurfer/scripts/build-stamp.txt
        try:
            log_file = open(stamp_path, 'r')
            lines = log_file.readlines()
            log_file.close()

            if len(lines) > 0:
                #Extract the FS version.
                build_stamp = lines[0].split('-')
                fs_version = ''
                for segment in build_stamp:
                    if '.' in segment:
                        return segment.replace('v','')

        except FileNotFoundError:
            pass
        
        #If we couldnt find it in the logs then try to find it in the path.
        print(f'Could not find a freesufer build stamp at: {stamp_path}, attempting to guess FS version from file path.')
        fs_version = ''
        keys_to_check = []
        try:
            keys_to_check = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.FS_VERSION_TAGS].keys()
        except KeyError:
            print(f'Could not find a Freesurfer_Version_Tags definition in projects database information. Make sure this is defined.')
        
        for key in keys_to_check:
            if key.lower() in self.__data_path.lower(): #Ignore case for an easier match.
                fs_version = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.FS_VERSION_TAGS][key].replace('v','')
                break

        return fs_version 

    def check_modalities(self) -> dict:
        mods_collected = {}
        
        for key in self.__parameter_data['MODALITIES']:
            mods_collected[key] = len(self.__parameter_data['MODALITIES'][key].group(5).replace('(','').replace(')','').split()) #This gets the number of files specified

        return mods_collected
    
    def get_MB_level(self) -> int:
        if 'MB_FACTOR' in self.__parameter_data['RULES']:
            return int(self.__parameter_data['RULES']['MB_FACTOR'].group(5))

        return 0

    def guess_processing_status_from_path(self) -> str:
        processing_status = ''
        
        keys_to_check = []
        try:
            keys_to_check = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.ALLOWED_PROC_STATUSES].keys()
        except KeyError:
            print(f'Could not find a Processing_Status definition in the projects data path. Make sure this is defined.')
        
        for key in keys_to_check:
            if key.lower() in self.__data_path.lower(): #Ignore case for an easier match.
                processing_status = self.__projects_data[Definitions.NAMING_CONVENTIONS][Definitions.ALLOWED_PROC_STATUSES][key]
                break
        
        return processing_status
    
    def guess_date_acquired_from_path(self) -> str:

        if 'ACQUISITION_TIME' in self.dicom_metadata:
            date_acquired = self.dicom_metadata['ACQUISITION_TIME']
           
            #Check if the format is what we expect.
            if 'T' in date_acquired:
                #Split on the 'T'
                date_obj = datetime.strptime(date_acquired.split('T')[0], '%Y-%m-%d')
                return date_obj.strftime('%m/%d/%Y')

        return ''

    def get_metadata_source_directory(self) -> str:
        
        if self.metadata_source == '':
            print(f'Could not extract find data source')
            return ''
        return self.metadata_source 

    def guess_software_version_from_path(self) -> str:
        
        if not 'SOFTWARE_VERSION' in self.dicom_metadata:
            print('Could not extract software version from json metadata.')
            return ''
        
        return self.dicom_metadata['SOFTWARE_VERSION']

    def guess_pipeline_version_from_path(self) -> str:
        
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
                print(f'It appears that the file {proc_params_paths[0]} was found but does not exist. Check symbolic link health.')
        else:
            print(f'No processing parameters found at {self.__data_path}, could not determine the software version used.')

        return ''
    
    def get_analysis_information(self, session_id,  analysis_paths: list) -> dict:
        analysis = {}
        
        for path in analysis_paths:
            analysis_session_id = guess_session_id_from_analysis_path(path)
            if session_id != analysis_session_id:
                continue
            
            modality = guess_modality_from_path(path)
            if modality != '':
                if not modality in analysis:
                    analysis[modality] = [ path ]
                else:
                    analysis[modality].append(path)
        
        return analysis

    def check_for_session_bpass_smoothing(self, sub_ses: str) -> bool:

        if os.path.isfile(os.path.join(self.__data_path, 'Functional/Volume', f'{sub_ses}_rsfMRI_uout_bpss_resid_sm7.nii.gz')):
            return True

        return False
    
    def check_for_session_resid_smoothing(self, sub_ses: str) -> bool:

        if os.path.isfile(os.path.join(self.__data_path, 'Functional/Volume', f'{sub_ses}_rsfMRI_uout_resid_resid_sm7.nii.gz')):
            return True

        return False

    # ------------------------- SUBJECT and SESSION data models -------------------------
    def generate_session_data(self,
                              discovered_analysis: list) -> dict:

        session_id = guess_sess_id_from_path(self.__data_path) 
        sub_ses = os.path.basename(self.__data_path)

        if session_id == '':
            print(f'Unable to determine the session id from the path {self.__data_path}, skipping...')
            return {}
        

        #There may be a way to do this dynamically which would be cool for extensibility.
        #For now lets just hard code in the data we get here.
        session_metadata_to_update = {
            Definitions.SESSION_ID           : session_id,
            Definitions.SESSION_ACCESSION    : '',
            Definitions.DATA_PATH            : self.__data_path,
            Definitions.FS_VERSION           : self.guess_fs_version_from_path(),
            Definitions.FS_ACCESSION         : '',
            Definitions.SCANNER              : self.guess_scanner_from_path(),
            Definitions.PIPELINE_VERSION     : self.guess_pipeline_version_from_path(),
            Definitions.SOFTWARE_VERSION     : self.guess_software_version_from_path(),
            Definitions.DATE_COLLECTED       : self.guess_date_acquired_from_path(),
            Definitions.PROC_STATUS          : self.guess_processing_status_from_path(),
            Definitions.MODS_COLLECTED       : self.check_modalities(),
            Definitions.BOLD_MB_FACTOR       : self.get_MB_level(),
            Definitions.BOLD_BPASS_SMOOTHING : self.check_for_session_bpass_smoothing(sub_ses),
            Definitions.BOLD_RESID_SMOOTHING : self.check_for_session_resid_smoothing(sub_ses),
            Definitions.ANALYSIS             : self.get_analysis_information(session_id, discovered_analysis)
        }
        

        return session_metadata_to_update
