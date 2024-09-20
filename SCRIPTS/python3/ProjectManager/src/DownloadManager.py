import requests
import time
import threading
import getpass
import os
import io
import tqdm
import pymongo
import zipfile
import shutil
import subprocess
import pydicom
from bson.objectid import ObjectId
import src.DataModels.Definitions as Definitions
from src.InformationPrompter import ExtractionInformationPrompter
from src.Utils.ParseCSV import ParseCSV

import pdb

class DownloadManager(object):
    def __init__(self,
                 database_name: str,
                 server: str, 
                 download_chunk_size: int,
                 download_dir: str | None,
                 log_file: str | None) -> None:

        #This is the ID of the projects info document which stores all the entrypoint
        #information. This ID should never change and is where all project related information 
        #is stored.
        self.__projects_info_id = ObjectId('662bd60a8b564a24fc2202d8') 

        #Check that the server looks valid.
        if not ('https://' in server and server[-1] == '/'):
            print(f'The server {server} is not formatted correctly.')
            raise ValueError
        
        try:
            client = pymongo.MongoClient('mongodb://localhost:27017/')
            self.__database = client[database_name]

            #Load the project information document.
            projects_info = self.__database[Definitions.PROJECTS_INFO]
            self.__projects_data = projects_info.find_one({'_id':self.__projects_info_id})

            self.__projects_dir  = os.path.join(Definitions.PROJECTS_HOME, Definitions.PROJECTS_DIR)
            self.__scans_dir     = os.path.join(Definitions.PROJECTS_HOME, Definitions.SCANS_DIR)
            
            self.__download_dir = download_dir
            if download_dir == None:
                self.__download_dir = os.path.join(Definitions.SCRATCH_DIR, Definitions.DEFAULT_DOWNLOAD_DIR)

        except Exception as e:
            print(f'An error connecting to the database {database_name} failed with error {e}.')
            raise ValueError
            
        
        self.__server = server
        self.__download_chunk_size = download_chunk_size
        
        self.__mutex = threading.Lock()
        self.__heart_beat = None
        self.__logged_in = False
        self.__cookie = None

        #Success and failure lists.
        self.__logging = {
            'failures' : {
                'download' : [],
                'propagation' : []
            },
            'successes' : {
                'download' : [],
                'propagation' : []
            }
        }

        self.__log_file = log_file
    
    #Log data if logging is happening.
    def __log_output(self) -> None:
        if self.__log_file:
            #Check if we are logging or not.
            with open(self.__log_file, 'w') as f:
                f.write(f'Created log file {os.path.basename(self.__log_file)}.\n')

                f.write('Downloads: \n')
                f.write('\tThe following downloads completed successfully:\n')
                for id in self.__logging['successes']['download']:
                    f.write(f'\t\t{id}\n')
                f.write('\tThe following downloads failed:\n')
                for id in self.__logging['failures']['download']:
                    f.write(f'\t\t{id}\n')
            
                f.write('Extraction and Propagation: \n')
                f.write('\tThe following propagations completed successfully:\n')
                for id in self.__logging['successes']['propagation']:
                    f.write(f'\t\t{id}\n')
                f.write('\tThe following propagations failed:\n')
                for id in self.__logging['failures']['propagation']:
                    f.write(f'\t\t{id}\n')
    
    #This function gets a download cookie that allows http requests to authenticate correctly on CNDA.
    #lasts 15 minutes.
    def __get_session_cookie(self) -> requests.cookies.RequestsCookieJar | None:
        http_position = self.__server.find('https://') + 8
        url = f'https://{self.__user}:{self.__pass}@{self.__server[http_position:]}data/JSESSION'
        print(f'Acquiring new cookie for {self.__server}...')
        cookie_response = requests.get(url)

        if not cookie_response.ok:
            self.__mutex.acquire()
            print(f'Authentication failed for user {self.__user} on server {self.__server}.')
            self.__mutex.release()
            self.__logged_in = False
            return None

        #Otherwise return the cookejar
        return cookie_response.cookies
    
    #Keeps the current connection alive by requesting a new log in cookie every time interval.
    #Requires the number of minutes to send a refresh response.
    def __keep_connection_alive(self, refresh_rate :int):
        keep_alive_time = refresh_rate * 60 #Every 10 minutes get a new cookie from xnat to keep the session alive.
        def get_login_cookie():
            start_time = time.perf_counter()
            while True:
                #Check if the user is still logged in.
                self.__mutex.acquire()
                if not self.__logged_in:
                    self.__mutex.release()
                    break
                
                self.__mutex.release()

                #Check how much time has elapsed
                current_time = time.perf_counter()
                if current_time - start_time >= keep_alive_time:
                    start_time = current_time 
                    
                    self.__mutex.acquire()
                    self.__cookie = self.__get_session_cookie()
                    if self.__cookie == '':
                        print(f'Could not refresh login cookie for user, logging out...')
                        self.__logged_in = False
                        self.__mutex.release()
                        break

                    self.__mutex.release()


                time.sleep(1)

        self.__heart_beat = threading.Thread(target=get_login_cookie)
        self.__heart_beat.start()
    
    #Downloads a zip folder containing the MR and FS information from CNDA. Returns a tuple of two output_paths.
    #which signify if the mr and fs data downloaded respectively.
    def __download_data(self, mr_accession: str, fs_accession: str)  -> tuple:
        mr_destination = os.path.join(self.__download_dir, f'{mr_accession}.zip')
        fs_destination = os.path.join(self.__download_dir, f'{fs_accession}.zip')
        mr_url = f'https://cnda.wustl.edu/data/experiments/{mr_accession}/scans/ALL/files?format=zip'
        fs_url = f'https://cnda.wustl.edu/data/experiments/{mr_accession}/assessors/{fs_accession}/files?format=zip'
        
        success = []
        for destination, url in zip([mr_destination, fs_destination], [mr_url, fs_url]):
            try:
                self.__mutex.acquire()
                response = requests.get(url, stream=True, cookies = self.__cookie.get_dict())
                print(f'Downloading file: {destination}...')
                self.__mutex.release()

                response.raise_for_status()
                with open(destination, 'wb') as f:
                    total_chunks = int((len(response.content) / self.__download_chunk_size) + 1)
                    for chunk in tqdm.tqdm(response.iter_content(chunk_size=self.__download_chunk_size), total=total_chunks):
                        f.write(chunk)

                print(f'File {destination} downloaded successfully!')
                success.append(destination)
            except requests.exceptions.RequestException as e:
                print(f'Error downloading the file {destination}\n', e)
                success.append('')

                #If we failed before releasing the lock we must release it.
                if self.__mutex.locked():
                    self.__mutex.release()
        

        return tuple(success)

    #This is a helper function that extracts a root path in an archive to a destination folder.
    #The function takes the archive, the root path in the archive, and the destination path to
    #extract to.
    def __extract_root_to(self,
                        archive: zipfile.ZipFile,
                        root_path: str,
                        destination_path: str) -> None:
        #Lets try to find the scan source based on the header metadata from one of the dcm files.
        #Compile a list of all relevant paths.
        relevant_paths = []
        for path in archive.namelist():
            if path.startswith(root_path):
                relevant_paths.append(path)

        for path in tqdm.tqdm(relevant_paths, total=len(relevant_paths), desc = f'Extracting {os.path.basename(archive.filename)}: '):
            member_target_path = os.path.join(destination_path, os.path.relpath(path, root_path))
            os.makedirs(os.path.dirname(member_target_path), exist_ok=True)
            # Read the file from the archive and write it to the target location
            with archive.open(path) as source, open(member_target_path, 'wb') as target:
                shutil.copyfileobj(source, target)

    def __prompt_scan_location(self,session_accession: str, fs_accession: str) -> str:
        scan_location = ''
        valid_responses = ['y', 'yes', 'n', 'no']
        while True:
            response = ''
            while not response.lower() in valid_responses:
                response = input('Would you like to enter a custom extraction location ([Y]es /[N]o)? ')

                if response.lower() in ['n', 'no']:
                    print(f'Skipping extraction for {session_accession}.zip, {fs_accession}.zip...')
                    return ''
            
            response = ''
            while True:
                scan_location = input('Enter the location in scans you want to extract to: ')

                while not response.lower() in valid_responses + ['a', 'abbort']:
                    response = input(f'Is the extraction location {scan_location} correct ([Y]es /[N]o/ [A]bbort)? ')
                


                if response.lower() in ['y', 'yes', 'a', 'abbort']:
                    break

            if response.lower() in ['a','abbort']:
                continue

            
            break 

        return scan_location


    def __update_source2scanners(self, project: str, scan_source: str, scanner: str):
        #First check if the scan source is even a current key:
        scan_locations = self.__projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS]
        update_string = f'{Definitions.PROJECTS}.{project}.{Definitions.SCAN_LOCATIONS}.{scan_source}'
        if not scan_source in scan_locations:
            #Then we just need to add a new array key value pair to the scan locations array in the database.

            scan_locations[scan_source] = scanner
            self.__database[Definitions.PROJECTS_INFO].update_one({'_id': self.__projects_info_id},
                                                                  {'$set': {update_string: [scanner]}})

            return

        #otherwise we need to push to an existing scanner
        scan_locations[scan_source].append(scanner)
        self.__database[Definitions.PROJECTS_INFO].update_one({'_id': self.__projects_info_id},
                                                              {'$push': {update_string: scanner}})

    
    def login(self, user_name: str) -> bool:
        self.__user = user_name
        self.__pass = getpass.getpass(f'Please enter your password for the xnat server {self.__server}: ')

        self.__cookie = self.__get_session_cookie() 
        if self.__cookie:
            self.__logged_in = True
            self.__keep_connection_alive(refresh_rate = 10)

        return self.__logged_in

    def logout(self) -> None:
        self.__mutex.acquire()
        self.__logged_in = False
        self.__mutex.release()
        self.__heart_beat.join()

    def download_from_csv(self,
                          download_csv: str,
                          session_accession_column: str,
                          fs_accession_column: str) -> None:

        csv_parser = ParseCSV(download_csv)


        for mr_accession, fs_accession in csv_parser.generate_csv_data((session_accession_column, fs_accession_column)):
            mr_path, fs_path = self.__download_data(mr_accession, fs_accession)
            
            log_string = f'MR Accession: {mr_accession}, FS Accession: {fs_accession}'
            if mr_path == '' or fs_path == '':
                self.__logging['failures']['download'].append(log_string)
                continue

            self.__logging['successes']['download'].append(log_string)

        self.__log_output()
    
    #Could be parallel to increase efficiency.
    def extract_and_propagate_from_csv(self,
                                       project: str,
                                       download_csv : str,
                                       subject_id_column : str,
                                       session_id_column : str,
                                       session_accession_column : str,
                                       fs_accession_column: str,
                                       target_destination: str | None,
                                       target_in_csv: bool,
                                       source_destination_column: str,
                                       clean_up) -> None:
        
        target_project_column = None if not target_in_csv else target_destination

        csv_parser = ParseCSV(download_csv)

        for destination, id, session, session_accession, fs_accession, target_project_alias in csv_parser.generate_csv_data((
                                                                                                   source_destination_column,
                                                                                                   subject_id_column,
                                                                                                   session_id_column,
                                                                                                   session_accession_column,
                                                                                                   fs_accession_column,
                                                                                                   target_project_column)):

            log_string = f'Subject ID: {id}, Session ID: {session}'
             
            if (id == None or session == None or session_accession == None or fs_accession == None):
                print('The csv file provided does not have the necissary information. Cannot extract and propagate.')
                return

            #If the target_project_alias was set in the csv then no big deal otherwise it must have been specified
            #explicitly in target_destination.
            if target_project_alias == None:
                target_project_alias = target_destination

            #Extract scan data to the right location.
            #Check that the source file exists.
            mr_source_file = os.path.join(self.__download_dir, f'{session_accession}.zip')
            if not os.path.isfile(mr_source_file):
                print(f'The downloaded file {mr_source_file} does not exist, this download must have failed. Skipping...')
                self.__logging['failures']['propagation'].append(log_string)
                continue

            
            archive = None
            try:
                archive = zipfile.ZipFile(mr_source_file)
            except Exception as e:
                print(f'An error occured when trying to extract downloaded file {mr_source_file}.\nError:\n{e}\nSkipping this download...')
                self.__logging['failures']['propagation'].append(log_string)
                continue
            
            #The first step is to attempt find the scanner and attempt to map that to the projects scan location.
            
            parent_destination = ''
            if destination:
                #The destination has been specified in the csv file. We just need to determine the extraction location based on that.
                parent_destination = os.path.join(self.__scans_dir, destination)
                if not os.path.isdir(parent_destination):
                    print(f'Could not find the target directory {parent_destination}, skipping extraction...')
                    self.__logging['failures']['propagation'].append(log_string)
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
                    parent_destination = self.__prompt_scan_location(session_accession, fs_accession)

                else:
                    #We have the dicom path. Lets check the metadata with pydicom.
                    dicom_object = None
                    try:
                        dicom_object = pydicom.dcmread(io.BytesIO(archive.read(dicom_fname)))
                    except Exception as e:
                        print('The dicom file {dicom_fname} could not be read. Skipping...')
                        self.__logging['failures']['propagation'].append(log_string)
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
                        scan_sources = list(self.__projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS].keys())
                        parent_destination_candidates = list(self.__projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS].values())

                        scan_source_index = None
                        for index,candidate in enumerate(parent_destination_candidates):
                            if scanner_name in candidate:
                                scan_source_index = index
                                break
                        if scan_source_index:
                            parent_destination = scan_sources[scan_source_index]

                        else:
                            prompter = ExtractionInformationPrompter(self.__projects_data, project)
                            scan_location = prompter.prompt_scan_source(scanner_name)
                            parent_destination = scan_location

                            
                            if scan_location == '':
                                self.__logging['failures']['propagation'].append(log_string)
                                continue
 
                            #Otherwise we need to update with this new mapping.
                            self.__update_source2scanners(project, scan_location, scanner_name)
                    else:
                        print('Could not find a model name tag in the specified dicom file. Cannot associate a model name with a scan location.')
                        print(f'Could not automatically determine scan location for {mr_source_file}.')
                        parent_destination = self.__prompt_scan_location(session_accession, fs_accession)

                
                    #At the end check if we have determined a location for this and if not we need to skip extraction for this subject.
                    if parent_destination == '':
                        self.__logging['failures']['propagation'].append(log_string)
                        continue
            #Check that the destination does not exist.
            #check if a raw_data intermediary folder exists. This is historical.
            source = os.path.join(self.__scans_dir, parent_destination)
            
            raw_data_dir = os.path.join(source, Definitions.RAW_DATA)
            if os.path.isdir(raw_data_dir):
                source = raw_data_dir
            

            destination_dir = os.path.join(source, f'sub-{id}', f'ses-{session}')

            if os.path.isdir(destination_dir):
                print(f'It appears that the target destination for download {destination_dir} already exists. Please check the location and manually resolve conflicts.')
                self.__logging['failures']['propagation'].append(log_string)
                continue
            
            self.__extract_root_to(archive, f'{session}/scans', destination_dir)
            print('Completed extraction of MR data, attempting to propagate session.')
            archive.close()
            
            if clean_up:
                os.remove(mr_source_file)

            
            #Now lets attempt to run the propagation script.
            #Execute the command to attempt to propagate this session over.
            command_string = f'propagate_scans {target_project_alias} -P {parent_destination} -L sub-{id} -S ses-{session}'
            custom_prop = subprocess.Popen(command_string.split())

            custom_prop.wait()
            if custom_prop.returncode:
                print(f'Custom propagation {command_string} failed.')
                self.__logging['failures']['propagation'].append(log_string)
                continue

            #Do a double check that the right destination path to extract to exists.
            target_sub_ses_path = os.path.join(self.__projects_dir, target_project_alias, Definitions.IN_PROCESS, f'sub-{id}_ses-{session}')
            if not os.path.isdir(target_sub_ses_path):
                print(f'The subject/session pair {target_sub_ses_path} does not exist. Propagation must not have completed. Skipping...')
                self.__logging['failures']['propagation'].append(log_string)
                continue
            
            #Otherwise propagation was good.
            #Check if a fs_zipfile exists.
            fs_source_file = os.path.join(self.__download_dir, f'{fs_accession}.zip')
            if not os.path.isfile(fs_source_file):
                print(f'The downloaded file {fs_source_file} does not exist, this download must have failed. Skipping...')
                self.__logging['failures']['propagation'].append(log_string)
                continue

            #The place to extract fs_data to.
            destination_dir = os.path.join(target_sub_ses_path, Definitions.FS_PATH_NAME)
            if os.path.isdir(destination_dir):
                print(f'It appears that the target destination for download {destination_dir} already exists. Please check the location and manually resolve conflicts.')
                self.__logging['failures']['propagation'].append(log_string)
                continue
            
            archive = None
            try:
                archive = zipfile.ZipFile(fs_source_file)
            except Exception as e:
                print(f'An error occured when trying to extract downloaded file {fs_source_file}.\nError:\n{e}\nSkipping this download...')
                self.__logging['failures']['propagation'].append(log_string)
                continue
            
            self.__extract_root_to(archive, f'{fs_accession}/out/resources/DATA/files/{session}', destination_dir)

            archive.close()
            print(f'Extraction and propation for {target_sub_ses_path} complete.')

            if clean_up:
                os.remove(fs_source_file)
            
            self.__logging['successes']['propagation'].append(log_string)
        
        self.__log_output()
        
            

            



