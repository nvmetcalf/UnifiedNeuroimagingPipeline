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
    strings_to_search = sub_ses_path.split('/') #Assumes a unix style FS.
    

    #find the index for '_ses-'.
    for dir in strings_to_search:
        if not '_ses-' in dir:
            continue

        ses_index = dir.index('_ses-')
        sess_id = dir[ses_index + 5:] #cut out the '_ses-' from the id
        break
    return sess_id

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

    def check_modalities(self) -> list:
        mods_collected = []
        
        #The easiest way is probably to check the params file because that will store only the usable bold (Hopefully if its set up
        #correctly).
        regex_string = ''
        line = ''
        params_path = os.path.join(self.__data_path, f'{os.path.basename(os.path.normpath(self.__data_path))}.params')
        try:
            params_file = open(params_path, 'r')
            for line in params_file:
                
                for key in Definitions.REGEX_RULES["MODALITIES"]:
                    regex_string = rf'{Definitions.REGEX_RULES["MODALITIES"][key]}'
                    match = regex.match(regex_string, line, timeout = 1)
                    if match and len(match.group(5).replace('(','').replace(')','')): #This will trigger if there is a regex match and that match has file names in the list.
                        mods_collected.append(key)
                        break
                        
            params_file.close()
        except TimeoutError:
            print(f'Could not resolve the file names at: {line} due to catastrophic backtracking with regex: {regex_string}')
            return []
        except FileNotFoundError:
            print(f'Could not find a params file at the location {params_path}, could not check collected modalities')
            return [] 

        return mods_collected
    

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
    
    def guess_date_acquired_from_path(self, 
                                      project: str, 
                                      subject_id: str, 
                                      session_id: str) -> str:

        if 'ACQUISITION_TIME' in self.dicom_metadata:
            date_acquired = self.dicom_metadata['ACQUISITION_TIME']
           
            #Check if the format is what we expect.
            if 'T' in date_acquired:
                #Split on the 'T'
                date_obj = datetime.strptime(date_acquired.split('T')[0], '%Y-%m-%d')
                return date_obj.strftime('%m/%d/%Y')

        print('Could not extract a date from json metadata. Attempting to extract from DICOM file names.')
        #If the date could not be extracted from the metadata, then we can try to scrape it from the DCM file names.
        
        project_scan_locations = self.__projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS]
        dicom_ext_length = len(Definitions.DICOM_EXTENSION)
        def find_dcm_starting_at_dir(current_dir: str) -> str:
            #Switch the directory to the one we are looking in.
            os.chdir(current_dir)

            #Get the immediate subdirectories and files.
            files = []
            dirs  = []
            for path in os.listdir():
                if os.path.isdir(path):
                    dirs.append(path)
                if os.path.isfile(path):
                    files.append(path)

            #Check if any files have the DICOM extension.
            for fname in files:
                if len(fname) > dicom_ext_length and fname[dicom_ext_length * -1:] == Definitions.DICOM_EXTENSION:
                    #We found what we are looking for!
                    return fname
            
            #We have checked all the files that exist and done of them are dicoms.
            if len(dirs) == 0:
                return '' 

            #Otherwise look through all the subfolders and see if any of them have dicoms.
            for folder in dirs:
                fname = find_dcm_starting_at_dir(os.path.join(current_dir, folder)) 
                if fname == '':
                    continue

                return fname

            #There werent any dicoms here.
            return ''

        for scan_source in project_scan_locations:
            scan_root_dir = os.path.join(Definitions.PROJECTS_HOME, Definitions.SCANS_DIR, scan_source)
            
            #At the very least, the scan_root_dir should exist, otherwise we have a problem.
            if not os.path.isdir(scan_root_dir):
                print(f'Could not find the path {scan_root_dir}, moving on...')
                continue

            #Check if there is a rawdata folder that we need to look in.
            raw_data_path = os.path.join(scan_root_dir, 'rawdata')
            if os.path.isdir(raw_data_path):
                scan_root_dir = raw_data_path
            
            #Now we should have the right path for looking for the correct subject folder.
            #Get all the folder names.
            dcm_root = os.path.join(scan_root_dir, f'sub-{subject_id}', f'ses-{session_id}')
            
            if not os.path.isdir(dcm_root):
                print(f'Could not find a matching subject/session pair in {scan_source}, moving on...')
                continue

            #Otherwise we have to find a single .dcm file and extract the date from it.
            current_dir = os.getcwd()
            dcm_fname = find_dcm_starting_at_dir(dcm_root)
            os.chdir(current_dir)
            
            if dcm_fname == '':
                continue

            #Otherwise we found a suitable dicom file.
            split_on_dot = dcm_fname.split('.')
            for fname_chunk in split_on_dot:
                try:
                    date_obj = datetime.strptime(fname_chunk, '%Y%m%d')
                    if int(date_obj.strftime('%Y')) > 2000: #Really hacky, basically if the year is older than 2000 then we trust it.
                        return date_obj.strftime('%m/%d/%Y')
                except ValueError:
                    pass

        
        print(f'Unable to find any DICOM files associated with subject {subject_id} session {session_id}. Could not determine date acquired.')
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

    # ------------------------- SUBJECT and SESSION data models -------------------------
    def generate_session_data(self,
                              project: str, 
                              subject_id: str) -> dict:

        session_id = guess_sess_id_from_path(self.__data_path) 
        if session_id == '':
            print(f'Unable to determine the session id from the path {self.__data_path}, skipping...')
            return {}
        

        #There may be a way to do this dynamically which would be cool for extensibility.
        #For now lets just hard code in the data we get here.
        session_metadata_to_update = {
            Definitions.SESSION_ID          : session_id,
            Definitions.DATA_PATH           : self.__data_path,
            Definitions.FS_VERSION          : self.guess_fs_version_from_path(),
            Definitions.SCANNER             : self.guess_scanner_from_path(),
            Definitions.PIPELINE_VERSION    : self.guess_pipeline_version_from_path(),
            Definitions.SOFTWARE_VERSION    : self.guess_software_version_from_path(),
            Definitions.DATE_COLLECTED      : self.guess_date_acquired_from_path(project, subject_id, session_id),
            Definitions.PROC_STATUS         : self.guess_processing_status_from_path(),
            Definitions.MODS_COLLECTED      : self.check_modalities()
        }
        

        return session_metadata_to_update
