import requests
import os
import io
import tqdm
import zipfile
import shutil
import subprocess
import pydicom

import src.Utils.XNATAuthenticator as XNAT
import src.DataModels.Definitions as Definitions
import src.InformationPrompter as IP 
import src.Utils.ParseCSV as ParseCSV
import src.Subject as Subject

import pdb

class DownloadManager(XNAT.XNATAuthenticator):
    def __init__(self,
                 database_name: str,
                 server: str,
                 download_csv,
                 download_chunk_size: int,
                 download_dir: str | None,
                 log_file: str | None) -> None:
        
        super().__init__(database_name, server)
        
        self.__csv_parser = ParseCSV.ParseCSV(download_csv, match_col = '')
            
        self.__projects_dir  = os.path.join(Definitions.PROJECTS_HOME, Definitions.PROJECTS_DIR)
        self.__scans_dir     = os.path.join(Definitions.PROJECTS_HOME, Definitions.SCANS_DIR)
        self.__download_chunk_size = download_chunk_size
        self.__download_dir = download_dir
        if download_dir == None:
            self.__download_dir = os.path.join(Definitions.SCRATCH_DIR, Definitions.DEFAULT_DOWNLOAD_DIR)

        self.__log_file = None
        if log_file != None:
            try:
                self.__log_file = open(log_file, 'w')
            except Exception as e:
                print(f'Could not open file {log_file} for writting, {e}')
    

    
    #These are used for context management. This is to get the logger to work.
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        if not self.__log_file == None:
            self.__log_file.close()
    
    #Downloads a zip folder containing the MR and FS information from CNDA. Returns a True if the download succeeded otherwise false.
    def __download_data(self, download_url: str, download_destination: str) -> bool:
        
        if download_url == '':
            print(f'Cannot initiate download, accession not specified.')
            return False

        if os.path.isfile(download_destination):
            print(f'The file: {download_destination} already exists. Please delete this file and try again to re-download.')
            return False

        try:
            self._mutex.acquire()
            response = requests.get(download_url, stream=True, cookies = self._cookie.get_dict())
            print(f'Downloading file: {download_destination}...')
            self._mutex.release()

            response.raise_for_status()
            with open(download_destination, 'wb') as f:
                total_chunks = int((len(response.content) / self.__download_chunk_size) + 1)
                for chunk in tqdm.tqdm(response.iter_content(chunk_size=self.__download_chunk_size), total=total_chunks):
                    f.write(chunk)

        except requests.exceptions.RequestException as e:
            print(f'Error downloading the file {download_destination}\n', e)
            #If we failed before releasing the lock we must release it.
            if self._mutex.locked():
                self._mutex.release()

            return False

        print(f'File {download_destination} downloaded successfully!')
        return True

    #This is a helper function that extracts a root path in an archive to a destination folder.
    #The function takes the archive, the root path in the archive, and the destination path to
    #extract to.
    #Returns true if extraction completed. False if no extraction was performed.
    def __extract_root_to(self,
                        archive: zipfile.ZipFile,
                        root_path: str,
                        destination_path: str) -> bool:
        #Lets try to find the scan source based on the header metadata from one of the dcm files.
        #Compile a list of all relevant paths.
        relevant_paths = []
        for path in archive.namelist():
            if path.startswith(root_path):
                relevant_paths.append(path)
        
        if len(relevant_paths) == 0:
            return False

        for path in tqdm.tqdm(relevant_paths, total=len(relevant_paths), desc = f'Extracting {os.path.basename(archive.filename)}: '):
            common_path = os.sep.join(os.path.relpath(path, root_path).split(os.sep)[1:])
            
            if common_path == '':
                continue

            member_target_path = os.path.join(destination_path, common_path)

            os.makedirs(os.path.dirname(member_target_path), exist_ok=True)
            # Read the file from the archive and write it to the target location

            with archive.open(path) as source, open(member_target_path, 'wb') as target:
                shutil.copyfileobj(source, target)

        return True

    def __prompt_scan_location(self) -> str:
        scan_location = ''
        valid_responses = ['y', 'yes', 'n', 'no']
        while True:
            response = ''
            while not response.lower() in valid_responses:
                response = input('Would you like to enter a custom extraction location ([Y]es /[N]o)? ')

                if response.lower() in ['n', 'no']:
                    return ''
            
            response = ''
            while True:
                scan_location = input('Enter the location in scans you want to extract to: ')

                while not response.lower() in valid_responses + ['a', 'abort']:
                    response = input(f'Is the extraction location {scan_location} correct ([Y]es /[N]o/ [A]bort)? ')
                
                if response.lower() in ['y', 'yes', 'a', 'abort']:
                    break

            if response.lower() in ['a','abort']:
                continue

            break 

        return scan_location


    def __update_source2scanners(self, project: str, scan_source: str, scanner: str):
        #First check if the scan source is even a current key:
        scan_locations = self._projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS]
        update_string = f'{Definitions.PROJECTS}.{project}.{Definitions.SCAN_LOCATIONS}.{scan_source}'
        if not scan_source in scan_locations:
            #Then we just need to add a new array key value pair to the scan locations array in the database.

            scan_locations[scan_source] = scanner
            self._database[Definitions.PROJECTS_INFO].update_one({'_id': self._projects_info_id},
                                                                 {'$set': {update_string: [scanner]}})

            return

        #otherwise we need to push to an existing scanner
        scan_locations[scan_source].append(scanner)
        self._database[Definitions.PROJECTS_INFO].update_one({'_id': self._projects_info_id},
                                                             {'$push': {update_string: scanner}})

    def log(self, message):
        print(message)
        if self.__log_file != None: 
            self.__log_file.write(message + '\n')

    def download_mr(self, mr_accession_column: str) -> None:
        
        for mr_accession in self.__csv_parser.get_column_as_list(mr_accession_column):
            if mr_accession == '':
                continue

            mr_destination = os.path.join(self.__download_dir, f'{mr_accession}.zip')
            mr_url = f'{self._server}data/experiments/{mr_accession}/scans/ALL/files?format=zip'
            
            if self.__download_data(mr_url, mr_destination):
                self.log(f'Successfully downloaded the file: {mr_destination}')
                continue

            self.log(f'Could not download the mr_accession value: {mr_accession}')
    
    def download_fs(self, fs_accession_column: str) -> None:

        for fs_accession in self.__csv_parser.get_column_as_list(fs_accession_column):
            if fs_accession == '':
                continue

            fs_destination = os.path.join(self.__download_dir, f'{fs_accession}.zip')
            fs_url = f'{self._server}data/experiments/{fs_accession}/assessors/{fs_accession}/files?format=zip'
            
            if self.__download_data(fs_url, fs_destination):
                self.log(f'Successfully downloaded the file: {fs_destination}')
                continue

            self.log(f'Could not download the fs_accession value: {fs_accession}')

    
    def download_all_data(self,
                          session_accession_column: str,
                          fs_accession_column: str) -> None:

        self.download_mr(session_accession_column)
        self.download_fs(fs_accession_column)
    
    def extract_and_propagate_mr(self,
                                 project: str,
                                 subject_id_column : str,
                                 subject_accession_column: str,
                                 session_id_column : str,
                                 session_accession_column : str,
                                 target_destination: str | None,
                                 target_in_csv: bool,
                                 source_destination_column: str,
                                 clean_up) -> None:

        if not target_in_csv and target_destination == None:
            print('No project alias was specified in the target csv file and no global project alias was set. Cannot propagate data.')
            return
        
        target_project_column = None if not target_in_csv else target_destination

        for row_num, (destination, id, id_accession,  session, session_accession, target_project_alias) in enumerate(self.__csv_parser.generate_csv_data((
                                                                                                                                           source_destination_column,
                                                                                                                                           subject_id_column,
                                                                                                                                           subject_accession_column,
                                                                                                                                           session_id_column,
                                                                                                                                           session_accession_column,
                                                                                                                                           target_project_column)), start = 1):
             
            if (id == None or session == None or session_accession == None):
                print(f'Row number: {row_num} does not have all necessary information. Cannot extract and propagate, Skipping ...')
                continue

            #If the target_project_alias was set in the csv then no big deal otherwise it must have been specified
            #explicitly in target_destination.
            if target_project_alias == None:
                target_project_alias = target_destination

            #Extract scan data to the right location.
            #Check that the source file exists.
            mr_source_file = os.path.join(self.__download_dir, f'{session_accession}.zip')
            if not os.path.isfile(mr_source_file):
                self.log(f'The downloaded file {mr_source_file} does not exist, this download must have failed. Skipping...')
                continue
            
            archive = None
            try:
                archive = zipfile.ZipFile(mr_source_file)
            except Exception as e:
                self.log(f'An error occured when trying to extract downloaded file {mr_source_file}.\nError:\n{e}\nSkipping this download...')
                continue
            
            #The first step is to attempt find the scanner and attempt to map that to the projects scan location.
            parent_destination = ''
            if destination:
                #The destination has been specified in the csv file. We just need to determine the extraction location based on that.
                parent_destination = os.path.join(self.__scans_dir, destination)
                if not os.path.isdir(parent_destination):
                    self.log(f'Could not find the target directory {parent_destination}, skipping extraction...')
                    continue

            else:
                #The destination has not been specified. We will try to associate the scanner type with the location.
                #Load in the first dicom file we can find.
                dicom_fname = ''
                for path in archive.namelist():
                    if path.endswith(Definitions.DICOM_EXTENSION):
                        dicom_fname = path
                        break

                if dicom_fname == '':
                    print(f'It appears there are no ".dcm" files in the archive {mr_source_file}. Cannot automatically determine the scan source from the scanner name.')
                    parent_destination = self.__prompt_scan_location()

                else:
                    #We have the dicom path. Lets check the metadata with pydicom.
                    dicom_object = None
                    try:
                        dicom_object = pydicom.dcmread(io.BytesIO(archive.read(dicom_fname)))
                    except Exception as e:
                        self.log('The dicom file {dicom_fname} could not be read. Skipping...')
                        continue

                    #Attempt to get the scanner.
                    scanner_name = ''
                    for variation in Definitions.DICOM_TAGS['MODEL_NAME']:
                        try:
                            scanner_name = dicom_object[variation].value
                            break
                        except KeyError:
                            pass
                    
                    if scanner_name != '':
                        #Now try to associate the scanner name to the location.
                        scan_sources = list(self._projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS].keys())
                        parent_destination_candidates = list(self._projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS].values())

                        scan_source_index = None
                        for index,candidate in enumerate(parent_destination_candidates):
                            if scanner_name in candidate:
                                scan_source_index = index
                                break
                        if scan_source_index != None:
                            parent_destination = scan_sources[scan_source_index]

                        else:
                            prompter = IP.ExtractionInformationPrompter(self._projects_data, project)
                            scan_location = prompter.prompt_scan_source(scanner_name)
                            if scan_location == '':
                                self.log(f'Could not determine the scanner name for the mr session {id}, row: {row_num}')
                                continue

                            #Otherwise we need to update with this new mapping.
                            parent_destination = scan_location
                            self.__update_source2scanners(project, scan_location, scanner_name)
                    else:
                        print('Could not find a model name tag in the specified dicom file. Cannot associate a model name with a scan location.')
                        print(f'Could not automatically determine scan location for {mr_source_file}.')
                        parent_destination = self.__prompt_scan_location()
                
            #At the end check if we have determined a location for this and if not we need to skip extraction for this subject.
            if parent_destination == '':
                self.log('Could not resolve the scan location, skipping...')
                continue

            #Check that the destination does not exist.
            #check if a raw_data intermediary folder exists. This is historical.
            source = os.path.join(self.__scans_dir, parent_destination)
            
            raw_data_dir = os.path.join(source, Definitions.RAW_DATA)
            if os.path.isdir(raw_data_dir):
                source = raw_data_dir
            

            destination_dir = os.path.join(source, f'sub-{id}', f'ses-{session}')

            if os.path.isdir(destination_dir):
                self.log(f'It appears that the target destination for download {destination_dir} already exists. Please check the location and manually resolve conflicts.')
                continue
            
            archive_path = session
            if not self.__extract_root_to(archive, archive_path, destination_dir):
                self.log(f'Extraction failed, no files found in the archive at the archive path {archive_path}. Ensure this is the correct FS data.')
                continue
            self.log('COMPLETED: extraction of MR data, attempting to propagate session.')
            archive.close()
            

            #Now lets attempt to run the propagation script.
            #Execute the command to attempt to propagate this session over.
            command_string = f'propagate_scans {target_project_alias} -P {parent_destination} -L sub-{id} -S ses-{session}'
            custom_prop = subprocess.Popen(command_string.split())
            custom_prop.wait()

            if custom_prop.returncode:
                self.log(f'Custom propagation {command_string} failed.')
                continue

            #Do a double check that the right destination path to extract to exists.
            target_sub_ses_path = os.path.join(self.__projects_dir, target_project_alias, Definitions.IN_PROCESS, f'sub-{id}_ses-{session}')
            if not os.path.isdir(target_sub_ses_path):
                self.log(f'The subject/session pair {target_sub_ses_path} does not exist. Propagation must not have completed. Skipping...')
                continue
            
            print('Adding session to database.')
            subject = Subject.Subject(self._projects_data, self._database, project)
            subject.update(id, [target_sub_ses_path], [], {}, False, '' if id_accession == None else id_accession)

            session_object = subject.get_session_by_session_id(session)
            if session == None:
                self.log(f'Something went wrong, there is no session matching {session} for the subect {id}. Cannot update session information.')
                continue

            session_object.update({Definitions.SESSION_ACCESSION : session_accession}, force_update = False)
            
            self.log(f'COMPLETED: extraction and propagation of {target_sub_ses_path}, row {row_num}')
            if clean_up:
                os.remove(mr_source_file)

    #Could be parallel to increase efficiency.
    def extract_fs(self,
                   project: str,
                   subject_id_column : str,
                   session_id_column : str,
                   fs_accession_column: str,
                   clean_up) -> None:

        for row_num, (id, session, fs_accession) in enumerate(self.__csv_parser.generate_csv_data((subject_id_column,
                                                                                                   session_id_column,
                                                                                                   fs_accession_column)), start = 1):
            if (id == None or session == None or fs_accession == None):
                print(f'Row number: {row_num} does not have all necessary information. Cannot extract and propagate, Skipping ...')
                continue
            
            #First load in the subject in the database.
            subject = Subject.Subject(self._projects_data, self._database, project)
            subject.load_by_map_id(id, False)
            session_object = subject.get_session_by_session_id(session)
            #Then get the data path.

            if session_object == None:
                self.log(f'Could not the session object for {session} for participant {id}.')
                continue

            #Do a double check that the right destination path to extract to exists.
            target_sub_ses_path = session_object.data[Definitions.DATA_PATH]
            if not os.path.isdir(target_sub_ses_path):
                self.log(f'The subject/session pair {target_sub_ses_path} does not exist. Propagation must not have completed. Skipping...')
                continue
            
            #Otherwise propagation was good.
            #Check if a fs_zipfile exists.
            fs_source_file = os.path.join(self.__download_dir, f'{fs_accession}.zip')
            if not os.path.isfile(fs_source_file):
                self.log(f'The downloaded file {fs_source_file} does not exist, this download must have failed. Skipping...')
                continue

            #The place to extract fs_data to.
            destination_dir = os.path.join(target_sub_ses_path, Definitions.FS_PATH_NAME)
            if os.path.isdir(destination_dir):
                self.log(f'It appears that the target destination for download {destination_dir} already exists. Please check the location and manually resolve conflicts.')
                continue
            
            archive = None
            try:
                archive = zipfile.ZipFile(fs_source_file)
            except Exception as e:
                self.log(f'An error occured when trying to extract downloaded file {fs_source_file}.\nError:\n{e}\nSkipping this download...')
                continue
            
            archive_path = f'{fs_accession}/out/resources/DATA/files'
            if not self.__extract_root_to(archive, archive_path, destination_dir):
                self.log(f'Extraction failed, no files found in the archive at the archive path {archive_path}. Ensure this is the correct FS data.')
                continue

            archive.close()

            self.log(f'Adding session FS data to database.')
            session_object.update({Definitions.FS_ACCESSION : fs_accession}, force_update = False)
            
            self.log(f'COMPLETED: extraction of {fs_source_file}, row {row_num}')

            if clean_up:
                os.remove(fs_source_file)

    
    #Could be parallel to increase efficiency.
    def extract_and_propagate_all(self,
                                  project: str,
                                  subject_id_column : str,
                                  subject_accession_column: str,
                                  session_id_column : str,
                                  session_accession_column : str,
                                  fs_accession_column: str,
                                  target_destination: str | None,
                                  target_in_csv: bool,
                                  source_destination_column: str,
                                  clean_up) -> None:

        self.extract_and_propagate_mr(project,
                                      subject_id_column ,
                                      subject_accession_column,
                                      session_id_column ,
                                      session_accession_column ,
                                      target_destination,
                                      target_in_csv,
                                      source_destination_column,
                                      clean_up)


        self.extract_fs(project,
                        subject_id_column ,
                        session_id_column ,
                        fs_accession_column,
                        clean_up)

