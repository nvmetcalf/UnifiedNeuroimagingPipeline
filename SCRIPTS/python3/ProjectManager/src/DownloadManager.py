import os
import io
import tqdm
import zipfile
import shutil
import subprocess
from csv import DictReader

import pydicom
import pyxnat

import src.Utils.DatabaseManager as DBM
import src.DataModels.Definitions as Definitions
import src.DataModels.ColumnNames as ColumnNames 
import src.InformationPrompter as IP 
import src.Subject as Subject

class DownloadManager(DBM.DatabaseManager):
    '''Handles downloading from XNAT servers. Primarily used with CNDA.
    
    Interfaces with the XNAT API to download imaging data. Additionally extract and organize data so that it can be
    used directly with UNP. Additionally manages adding additional database metadata (accession values) to DB which
    is not found in imaging metadata. Download and extraction/propagation are seperated into two different steps.

    Attributes:
        __download_dir (str)              : The directory to download imaging data to.
        __csv_file     (file)             : The file object for the download CSV file.
        __csv_parser   (DictReader)       : The dict reader object for parsing the download CSV file.
        __server       (str)              : The address for the XNAT server to download from.
        __xnat         (pyxnat.Interface) : The Interface object used to interact with XNAT projects.

    Requirements:
        Outside of the python dependancies this class uses the 'propagate_scans' UNP script. It is required that this
        is in your environment path and functional with the -L and -S options (used to specify a single session to
        propagate).
    '''

    def __init__(self,
                 database_name: str,
                 server: str,
                 project: str,
                 download_csv: str,
                 download_dir: str | None,
                 log_file: str | None) -> None:
        '''Initialize the DownloadManager object.

        Initialize variables and opten the download_csv file for reading. Additionally connect to the PM DB with
        the DatabaseManager.

        Parameters:
            database_name (str)        : The name of the PM DB to connect to.
            server        (str)        : The http address of the XNAT server to connect to.
            project       (str)        : The project to operate on.
            download_csv  (str)        : The path to the CSV file to read from.
            download_dir  (str | None) : The path to the location to download to. Will be set to the default location 
                                         in the Definitions file if None.
            log_file      (str | None) : The path to the file to log to if not None.
        '''
        
        super().__init__(database_name, project, log_file)
        
        self.__download_dir = download_dir

        if download_dir == None:
            self.__download_dir = os.path.join(Definitions.SCRATCH_DIR, Definitions.DEFAULT_DOWNLOAD_DIR)
        
        self.__csv_file = open(download_csv, 'r')
        
        self.__csv_entries = sum(1 for _ in self.__csv_file) - 1
        self.__csv_file.seek(0)

        self.__csv_parser = DictReader(self.__csv_file) 
        
        self.__server = server
        self.__xnat = None

        self.__logged_in = False

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        '''Called when exiting the DownloadManager object with block.
        
        Closes the download CSV file then calls the exit function in the logger parent class.

        Parameters:
            Default __exit__ parameters.
        '''

        super().__exit__(exc_type, exc_value, traceback)
        self.__csv_file.close()

    def __download_data(self, sub_id: str, 
                        experiment_accession: str, 
                        fs_accession: str) -> bool:
        '''Download data from XNAT using pyxnat. 

        Downloads data from the given URI to the download_destination. The data has to be downloaded as a ZIP file
        and should contain DICOM data. 

        Parameters:
            sub_id               (str) : The subject id for the subject in the project to specifiy. 
            experiment_accession (str) : The experiment accession value.
            fs_accession         (str) : The fs accession value.
            download_destination (str) : The path to the parent directory to download to.

        Returns:
            status (bool) : Returns true on success and false on failure.
        '''
       
        if sub_id == '' or experiment_accession == '' or fs_accession == '':
            self.log('Not all relevant accession information has not been specified.')
            return False
        
        if self.__xnat == None:
            self.log('Cannot initiate download, accession not specified.')
            return False
        
        if not os.path.isdir(self.__download_dir):
            self.log((f'The path: {self.__download_dir} is not a directory. Please specify a directory to download '
                       'to.'))
            return False

        final_session_path = os.path.join(self.__download_dir, f'{experiment_accession}.zip')
        final_fs_path      = os.path.join(self.__download_dir, f'{fs_accession}.zip')

        if os.path.isfile(final_session_path) or os.path.isfile(final_fs_path):
            self.log('This download appears to already exist, skipping this download...')
            return False
        
        try:
            #Try to download imaging data.
            projects_info  = self._projects_data[Definitions.PROJECTS][self._project]
            xnat_project = self.__xnat.select.project(projects_info[Definitions.PROJECT_ID])

            session = xnat_project.subject(sub_id).experiment(experiment_accession)

            if not session.exists():
                self.log((f'Cannot download the experiment accession "{experiment_accession}", it does not exist for '
                          f'the subject "{sub_id}".'))
                return False
            
            self.log(f'Beginning MR download {experiment_accession}...')
            experiment_path = session.scans().download(self.__download_dir)
            os.rename(experiment_path, final_session_path)
            self.log('Completed downloading the MR session.')

            #Try to download FS data.
            try:
                #Otherwise download the FS session.
                fs_session = session.assessor(fs_accession)
                if not fs_session.exists():
                    self.log((f'Cannot download the FS accession "{fs_accession}", it does not exist for the session  '
                              f'"{experiment_accession}".'))
                    return False

                #Now determine where the actual FS data is in the session.
                for out_resource in fs_session.out_resources():
                    if not out_resource.label() == Definitions.FS_DATA:
                        continue
                    
                    self.log(f'Beginning FS download {fs_accession}...')
                    extracted_path = out_resource.get(self.__download_dir)
                    os.rename(extracted_path, final_fs_path)
                    self.log('Completed downloading the FS session.')
                    break

            except Exception as e:
                self.log(f'Could not download the FS session "{fs_accession}", error: {e}.')
                return False

        except Exception as e:
            self.log(f'Could not download the MR accession value "{experiment_accession}", error: {e}.')
            return False

        return True

    def __extract_root_to(self,
                        archive: zipfile.ZipFile,
                        root_path: str,
                        destination_path: str) -> bool:
        '''A helper function which extracts a downloaded archive from root_path IN THE ARCHIVE to destination_path.

        Extracts from a common root_path in the archive to a destination_path. Additionally displays a progress bar for
        the extraction process.

        Parameters:
            archive (zipfile.ZipFile) : The zip archive object to extract from.
            root_path (str) : The common path in the archive to extract from.
            desination_path (str) The path to the directory to extract to.

        Returns:
            status (bool) : Returns true on success and false on failure.
        '''

        #Lets try to find the scan source based on the header metadata from one of the dcm files.
        #Compile a list of all relevant paths.
        relevant_paths = []
        for path in archive.namelist():
            if path.startswith(root_path):
                relevant_paths.append(path)
        
        if len(relevant_paths) == 0:
            return False
        
        self.set_tqdm_print()
        for path in tqdm.tqdm(relevant_paths, 
                              total = len(relevant_paths), 
                              desc  = f'Extracting {os.path.basename(archive.filename)}: '):

            common_path = os.sep.join(os.path.relpath(path, root_path).split(os.sep)[1:])
            if common_path == '':
                continue

            member_target_path = os.path.join(destination_path, common_path)

            os.makedirs(os.path.dirname(member_target_path), exist_ok=True)

            # Read the file from the archive and write it to the target location
            with archive.open(path) as source, open(member_target_path, 'wb') as target:
                shutil.copyfileobj(source, target)
        self.unset_tqdm_print()

        return True

    def __prompt_scan_location(self) -> str:
        '''Prompt yes or no for a scan location.

        Returns:
            scan_location (str) : Returns an empty string if the scan location is not accepted otherwise a string which
                                  contains the new scan location.
        '''

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


    def __update_source2scanners(self, scan_source: str, scanner: str) -> None:
        '''Update the scanner in the DB with new scan sources. 

        Checks if a scan_source is associated with a scanner in the DB. If not then update the DB with the new scan
        source.

        Parameters:
            scan_source (str) : The source directory in the UNP Scans location.
            scanner     (str) : The scanner the source directory belongs to.
        '''

        #First check if the scan source is even a current key:
        scan_locations = self._projects_data[Definitions.PROJECTS][self._project][Definitions.SCAN_LOCATIONS]
        update_string = f'{Definitions.PROJECTS}.{self._project}.{Definitions.SCAN_LOCATIONS}.{scan_source}'
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

    def login(self, user_name: str) -> None:
        '''Log in to the xnat server.

        Logs in to an xnat server and sets the internal __logged_in flag accordingly. Additionally performs a check
        to see if the log in was successful or not.

        Parameters:
            user_name (str) : The xnat user name.

        '''
        print(f'Please enter you password for {self.__server}')
        self.__xnat = pyxnat.Interface(server = self.__server, user = user_name)

        #Now check if the user is logged in.
        if len(self.__xnat.select.projects().get()) == 0:
            self.log('Login failed or you have access to no projects.')
            self.__logged_in = False
            return

        self.__logged_in = True

    def logout(self) -> None:
        '''Log out of the xnat server.
        
        Logs out of the xnat server if possible. Sets the __logged_in flag to false.
        '''

        if self.__xnat != None:
            self.__xnat.disconnect()

        self.__logged_in = False
    
    def download_all_data(self,
                          subject_id_column: str,
                          session_accession_column: str,
                          fs_accession_column: str) -> None:
        '''Download imaging and fs data from the xnat server.

        Parameters:
            subject_id_column (str) : The column name of the subject id.
            session_accession_column (str) : The column name of the xnat experiment accession value.
            fs_accession_column (str) : The column name of the xnat freesurfer accession value.
        '''
        
        if not self.__logged_in:
            self.log('Cannot initiate download, you are not logged in')
            return 

        self.set_tqdm_print()
        for row in tqdm.tqdm(self.__csv_parser, 
                             total = self.__csv_entries,
                             desc  = 'Downloading imaging data: '):

            if not (subject_id_column in row and session_accession_column in row and fs_accession_column in row):
                continue
            
            subject_id   = row[subject_id_column]
            mr_accession = row[session_accession_column] 
            fs_accession = row[fs_accession_column]

            if self.__download_data(subject_id, mr_accession, fs_accession):
                self.log((f'Successfully downloaded the MR accession value {mr_accession} and FS '
                          f'accession {fs_accession}'))

        self.unset_tqdm_print()
    
    def extract_and_propagate_mr(self,
                                 subject_id_column : str,
                                 subject_accession_column: str,
                                 session_id_column : str,
                                 session_accession_column : str,
                                 target_destination: str | None,
                                 target_in_csv: bool,
                                 source_destination_column: str,
                                 clean_up) -> None:
        '''Extract and propagate downloaded imaging data.

        Parameters:
            subject_id_column         (str)        : The column name of the subject id.
            subject_accession_column  (str)        : The column name of the xnat subject accession value.
            session_id_column         (str)        : The column name of the session id.
            session_accession_column  (str)        : The column name of the xnat experiment accession value.
            target_destination        (str | None) : The target project alias to extract to. If set to None then 
                                                     project alias will be set based on the scanner type.
            target_in_csv             (bool)       : A flag specififying if the target_destination is set in the 
                                                     supplied csv file.
            source_destination_column (str)        : The column specifying the target destination for each row (if 
                                                     target_in_csv is set).
            clean_up                  (bool)       : A flag specififying if downloaded files should be deleted after 
                                                     successful extraction.
        '''

        if not target_in_csv and target_destination == None:
            self.log('No project alias was specified in the target csv file and no global project alias was set. Cannot propagate data.')
            return
        
        target_project_column = None if not target_in_csv else target_destination
        
        for row_num, row in enumerate(self.__csv_parser, start = 1):

            if not (subject_id_column in row and subject_accession_column and session_id_column in row and session_accession_column in row):
                self.log(f'Row number: {row_num} does not have all necessary information. Cannot extract and propagate, Skipping ...')
                self.log(f'ID: {row[subject_id_column]}, session: {row[session_id_column]}, session_accession: {row[session_accession_column]}')
                continue

            id                = row[subject_id_column]
            id_accession      = row[subject_accession_column]
            session           = row[session_id_column]
            session_accession = row[session_accession_column]

            #If the target_project_alias was set in the csv then no big deal otherwise it must have been specified
            #explicitly in target_destination.
            target_project_alias = target_destination
            if target_project_column in row: 
                target_project_alias = row[target_project_column]
            

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
            if source_destination_column in row:
                #The destination has been specified in the csv file. We just need to determine the extraction location based on that.
                parent_destination = os.path.join(self._scans_dir, row[source_destination_column])
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
                    except:
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
                        scan_sources = list(self._projects_data[Definitions.PROJECTS][self._project][Definitions.SCAN_LOCATIONS].keys())
                        parent_destination_candidates = list(self._projects_data[Definitions.PROJECTS][self._project][Definitions.SCAN_LOCATIONS].values())

                        scan_source_index = None
                        for index,candidate in enumerate(parent_destination_candidates):
                            if scanner_name in candidate:
                                scan_source_index = index
                                break
                        if scan_source_index != None:
                            parent_destination = scan_sources[scan_source_index]

                        else:
                            prompter = IP.ExtractionInformationPrompter(self._projects_data, self._project)
                            scan_location = prompter.prompt_scan_source(scanner_name)
                            if scan_location == '':
                                self.log(f'Could not determine the scanner name for the mr session {id}, row: {row_num}')
                                continue

                            #Otherwise we need to update with this new mapping.
                            parent_destination = scan_location
                            self.__update_source2scanners(scan_location, scanner_name)
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
            source = os.path.join(self._scans_dir, parent_destination)
            
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

            custom_prop = subprocess.Popen(command_string.split(), 
                                           stdout = subprocess.PIPE, 
                                           stderr = subprocess.PIPE,
                                           universal_newlines = True)

            stdout, stderr = custom_prop.communicate()
            if stdout != '':
                self.log(f'Command output:{stdout}')
            if stderr != '':
                self.log(f'Command error:{stderr}')
            
            custom_prop.wait()

            if custom_prop.returncode:
                self.log(f'Custom propagation {command_string} failed.')
                continue

            #Do a double check that the right destination path to extract to exists.
            target_sub_ses_path = os.path.join(self._projects_dir, target_project_alias, Definitions.IN_PROCESS, f'sub-{id}_ses-{session}')
            if not os.path.isdir(target_sub_ses_path):
                self.log(f'The subject/session pair {target_sub_ses_path} does not exist. Propagation must not have completed. Skipping...')
                continue
            
            print('Adding session to database.')
            subject = Subject.Subject(self._projects_data, self._database, self._project, self)
            subject.update(id, [target_sub_ses_path], [], {}, False, '' if id_accession == None else id_accession)

            session_object = subject.get_session_by_session_id(session)
            if session == None:
                self.log(f'Something went wrong, there is no session matching {session} for the subect {id}. Cannot update session information.')
                continue

            session_object.update({ColumnNames.SESSION_ACCESSION : session_accession}, force_update = True)
            
            self.log(f'COMPLETED: extraction and propagation of {target_sub_ses_path}, row {row_num}')
            if clean_up:
                os.remove(mr_source_file)

    #Could be parallel to increase efficiency.
    def extract_fs(self,
                   subject_id_column : str,
                   session_id_column : str,
                   fs_accession_column: str,
                   clean_up) -> None:
        '''Extract FS data into existing sessions.

        For each session specified in the provided data file, find the corresponding session and extract the FS data
        to the corresponding data_path if a FS session is not happening.

        Parameters:
            subject_id_column         (str)        : The column name of the subject id.
            session_id_column         (str)        : The column name of the session id.
            fs_accession              (str)        : The fs accession value.
            clean_up                  (bool)       : A flag specififying if downloaded files should be deleted after 
                                                     successful extraction.
        '''

        for row_num, (id, session, fs_accession) in enumerate(
                self.__csv_parser.generate_csv_data((subject_id_column, session_id_column, fs_accession_column)), 
                start = 1
        ):
            if (id == None or session == None or fs_accession == None):
                print((f'Row number: {row_num} does not have all necessary information. Cannot extract and propagate'
                       ', Skipping ...'))
                continue
            
            #First load in the subject in the database.
            subject = Subject.Subject(self._projects_data, self._database, self._project, self)
            subject.load_by_map_id(id, False)
            session_object = subject.get_session_by_session_id(session)
            #Then get the data path.

            if session_object == None:
                self.log(f'Could load not the session object for {session} for participant {id}.')
                continue

            #Do a double check that the right destination path to extract to exists.
            target_sub_ses_path = session_object.data[ColumnNames.DATA_PATH]
            if not os.path.isdir(target_sub_ses_path):
                self.log((f'The subject/session pair {target_sub_ses_path} does not exist. Propagation must not have '
                          'completed. Skipping...'))
                continue
            
            #Otherwise propagation was good.
            #Check if a fs_zipfile exists.
            fs_source_file = os.path.join(self.__download_dir, f'{fs_accession}.zip')
            if not os.path.isfile(fs_source_file):
                self.log((f'The downloaded file {fs_source_file} does not exist, this download must have failed. '
                          'Skipping...'))
                continue

            #The place to extract fs_data to.
            destination_dir = os.path.join(target_sub_ses_path, Definitions.FS_PATH_NAME)
            if os.path.isdir(destination_dir):
                self.log(f'It appears that the target destination for download {destination_dir} already exists. '
                         'Please check the location and manually resolve conflicts.')
                continue
            
            archive = None
            try:
                archive = zipfile.ZipFile(fs_source_file)
            except Exception as e:
                self.log(f'An error occured when trying to extract downloaded file {fs_source_file}.\n'
                         f'Error:\n{e}\nSkipping this download...')
                continue
            
            archive_path = f'{fs_accession}/out/resources/DATA/files'
            if not self.__extract_root_to(archive, archive_path, destination_dir):
                self.log(f'Extraction failed, no files found in the archive at the archive path {archive_path}. '
                         'Ensure this is the correct FS data.')
                continue

            archive.close()

            self.log('Adding session FS data to database.')
            session_object.update({ColumnNames.FS_ACCESSION : fs_accession}, force_update = True)
            
            self.log(f'COMPLETED: extraction of {fs_source_file}, row {row_num}')

            if clean_up:
                os.remove(fs_source_file)

    def extract_and_propagate_all(self,
                                  subject_id_column : str,
                                  subject_accession_column: str,
                                  session_id_column : str,
                                  session_accession_column : str,
                                  fs_accession_column: str,
                                  target_destination: str | None,
                                  target_in_csv: bool,
                                  source_destination_column: str,
                                  clean_up) -> None:
        '''Extract and propagate downloaded MR and FS data.

        Parameters:
            subject_id_column         (str)        : The column name of the subject id.
            subject_accession_column  (str)        : The column name of the xnat subject accession value.
            session_id_column         (str)        : The column name of the session id.
            session_accession_column  (str)        : The column name of the xnat experiment accession value.
            fs_accession              (str)        : The fs accession value.
            target_destination        (str | None) : The target project alias to extract to. If set to None then 
                                                     project alias will be set based on the scanner type.
            target_in_csv             (bool)       : A flag specififying if the target_destination is set in the 
                                                     supplied csv file.
            source_destination_column (str)        : The column specifying the target destination for each row (if 
                                                     target_in_csv is set).
            clean_up                  (bool)       : A flag specififying if downloaded files should be deleted after 
                                                     successful extraction.
        '''

        self.extract_and_propagate_mr(subject_id_column ,
                                      subject_accession_column,
                                      session_id_column ,
                                      session_accession_column ,
                                      target_destination,
                                      target_in_csv,
                                      source_destination_column,
                                      clean_up)


        self.extract_fs(subject_id_column,
                        session_id_column,
                        fs_accession_column,
                        clean_up)

