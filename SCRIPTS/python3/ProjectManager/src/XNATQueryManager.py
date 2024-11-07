import requests
import os
import copy

import src.Subject as Subject
import src.DataModels.Definitions as Definitions
import src.Utils.XNATAuthenticator as XNAT
import src.Utils.CustomFlatten as CustomFlatten

class XNATQueryManager(XNAT.XNATAuthenticator):
    def __init__(self, database_name: str, server: str) -> None:

        super().__init__(database_name, server)

        self.data = {}
 
    
    def __query_xnat(self, xml_data: str) -> dict:
        url = f'{self._server}data/search?format=json'
        response = {}
        try:
            #Send the post request.
            self._mutex.acquire()
            server_response = requests.post(url, data = xml_data, cookies = self._cookie.get_dict(), headers={'Content-Type': 'application/xml'})
            self._mutex.release()
            
            # Check if the response was successful
            if server_response.status_code == 200:
                response = server_response.json()
            else:
                print(f"Request failed with status code {server_response.status_code}")

        except requests.exceptions.RequestException as e:
            print(f'Error, could not post the xml data {xml_data} to {url}', e)

            #If we failed before releasing the lock we must release it.
            if self._mutex.locked():
                self._mutex.release()
            
        return response

    #This is a helper function which synthesizes together MR data.
    #It expects query data in this order.
    #   1. A dict containing subjects query data. This is necissarily non-empty.
    #   2. A dict containing mr query data.
    #   3. A dict containing pet query data.
    #   4. A dict containing fs query data.
    #It combines this together by pivoting on subject ID and accession. Additionally columns will
    #be combined into a single column based on the mappings in Definitions.py.
    #The result is stored internally into the self.data field.
    #
    #The self.data member object has the following structure:
    #
    # -Subject_Accession
    #   -Session_id
    #   -other metadata
    def __synthesize_queries(self, 
                             subjects_data: dict,
                             mr_data: dict,
                             pet_data: dict,
                             fs_data: dict) -> None:

        self.data = {}

        def check_response(data: dict) -> dict:
            if data == {}:
                return {}

            try:
                return data['ResultSet']['Result']
            except KeyError:
                print('The response data is not formated in the expected way, something must have went wrong in the http request.')
                return {}

        def add_and_alias(mappings: str, key: str, value: str, to_add: dict) -> None:
            #Now check if it is in any of the other keys.
            mapped_keys = list(Definitions.XNAT_UNIFICATION_MAPPINGS[mappings].keys())
            for possible_key in mapped_keys:
                if key in Definitions.XNAT_UNIFICATION_MAPPINGS[mappings][possible_key]:
                    to_add[possible_key] = value
                    return

            #Otherwise we just add the key to the dictionary.
            to_add[key] = value

        #SUBJECTS 
        entry_list = check_response(subjects_data)
        if len(entry_list) != 0: 
            for subject in entry_list:
                #Now we need to add values to the data dictionary.
                #First lets add the subject id and subject accession to the data dictionary.
                all_accession_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['SUBJECT_MAPPINGS'][Definitions.SUBJECT_ACCESSION]

                #Now lets add these values to the data dictionary.
                cnda_accession = subject[all_accession_entries[0]]
                
                #If it doesnt exist, add it.
                if not cnda_accession in self.data:
                    self.data[cnda_accession] = {}

                #Now add all the rest of the keys. First do the mapped keys in the definitions file.
                to_add = {}
                for key in subject:
                    add_and_alias('SUBJECT_MAPPINGS', key, subject[key], to_add)

                self.data[cnda_accession].update(to_add)
        
        #MR_Sessions.
        entry_list = check_response(mr_data)
        if len(entry_list) != 0: 
            for mr_session in entry_list:
                #Now we need to add values to the data dictionary.
                #First lets add the subject id and subject accession to the data dictionary.
                all_subject_accession_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['MR_MAPPINGS'][Definitions.SUBJECT_ACCESSION]

                #Now lets add these values to the data dictionary.
                subject_accession = mr_session[all_subject_accession_entries[0]]
                
                #If it doesnt exist, add it.
                if not subject_accession in self.data:
                    all_subject_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['MR_MAPPINGS'][Definitions.MAP_ID]
                    self.data[subject_accession] = {
                        Definitions.MAP_ID: mr_session[all_subject_entries[0]]
                    }

                #Now add all the rest of the keys. First do the mapped keys in the definitions file.
                all_session_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['MR_MAPPINGS'][Definitions.SESSION_ACCESSION]
                session_accession = mr_session[all_session_entries[0]]

                to_add = {}
                for key in mr_session: 
                    add_and_alias('MR_MAPPINGS', key, mr_session[key], to_add)

                #Now lets finally add the session data to the data dictionary.
                if not Definitions.SESSIONS in self.data[subject_accession]:
                    self.data[subject_accession][Definitions.SESSIONS] = {
                        session_accession : to_add
                    }
                elif not session_accession in self.data[subject_accession][Definitions.SESSIONS]:
                    self.data[subject_accession][Definitions.SESSIONS][session_accession] = to_add
                else:
                    self.data[subject_accession][Definitions.SESSIONS][session_accession].update(to_add)
        
        #PET_Sessions.
        entry_list = check_response(pet_data)
        if len(entry_list) != 0: 
            for pet_session in entry_list:
                #Now we need to add values to the data dictionary.
                #First lets add the subject id and subject accession to the data dictionary.
                all_subject_accession_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['PET_MAPPINGS'][Definitions.SUBJECT_ACCESSION]

                #Now lets add these values to the data dictionary.
                subject_accession = pet_session[all_subject_accession_entries[0]]
                
                #If it doesnt exist, add it.
                if not subject_accession in self.data:
                    all_subject_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['PET_MAPPINGS'][Definitions.MAP_ID]
                    self.data[subject_accession] = {
                        Definitions.MAP_ID: pet_session[all_subject_entries[0]]
                    }

                #Now add all the rest of the keys. First do the mapped keys in the definitions file.
                all_pet_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['PET_MAPPINGS'][Definitions.PET_ACCESSION]
                pet_accession = pet_session[all_pet_entries[0]]

                to_add = {}
                for key in pet_session: 
                    add_and_alias('PET_MAPPINGS', key, pet_session[key], to_add)

                #Now lets finally add the session data to the data dictionary.
                if not Definitions.PET_SESSIONS in self.data[subject_accession]:
                    self.data[subject_accession][Definitions.PET_SESSIONS] = {
                        pet_accession : to_add
                    }
                elif not pet_accession in self.data[subject_accession][Definitions.PET_SESSIONS]:
                    self.data[subject_accession][Definitions.PET_SESSIONS][pet_accession] = to_add
                else:
                    self.data[subject_accession][Definitions.PET_SESSIONS][pet_accession].update(to_add)
        
        #FS_data
        entry_list = check_response(fs_data)
        if len(entry_list) != 0: 
            for fs in entry_list:
                #Now we need to add values to the data dictionary.
                #First lets add the subject id and subject accession to the data dictionary.
                all_accession_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['FS_MAPPINGS'][Definitions.SUBJECT_ACCESSION]

                #Now lets add these values to the data dictionary.
                subject_accession = fs[all_accession_entries[0]]
                
                #If it doesnt exist, add it.
                if not subject_accession in self.data:
                    self.data[subject_accession] = {}
                
                #Now add all the rest of the keys. First do the mapped keys in the definitions file.
                all_fs_entries = Definitions.XNAT_UNIFICATION_MAPPINGS['FS_MAPPINGS'][Definitions.SESSION_ACCESSION]
                session_accession = fs[all_fs_entries[0]]

                #Now add all the rest of the keys. First do the mapped keys in the definitions file.
                to_add = {}
                for key in fs:
                    add_and_alias('FS_MAPPINGS', key, fs[key], to_add)

                #Now try to add the data to either a pet or mr session entry. If niether exist then add it to the subject.
                if Definitions.SESSIONS in self.data[subject_accession]:
                    session_root_data = self.data[subject_accession][Definitions.SESSIONS]
                    if session_accession in session_root_data:
                        if not Definitions.FS_SESSION in session_root_data[session_accession]:
                            session_root_data[session_accession][Definitions.FS_SESSION] = to_add
                        else:
                            session_root_data[session_accession][Definitions.FS_SESSION].update(to_add)
                elif Definitions.PET_SESSIONS in self.data[subject_accession]:
                    session_root_data = self.data[subject_accession][Definitions.PET_SESSIONS]
                    if session_accession in session_root_data:
                        if not Definitions.FS_SESSION in session_root_data[session_accession]:
                            session_root_data[session_accession][Definitions.FS_SESSION] = to_add
                        else:
                            session_root_data[session_accession][Definitions.FS_SESSION].update(to_add)

    

    #Queries xnat using the xnat search API, by default a subject query is always run. If any other 
    #additional queries are specified then they are synthesized with the subject data.
    def __store_cnda_data(self, 
                          project: str,
                          include_mr: bool,
                          include_pet: bool,
                          include_fs: bool) -> None:
        
        #First lets try to get the CNDA ccir project ID from the database mappping.
        project_id = ''
        try:
            project_id = self._projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ID]
        except KeyError:
            print(f'Could not find either the project {project} or the associated {Definitions.PROJECT_ID}. Make sure that this is formed correctly.')
            raise ValueError
        
        root_dir = os.path.dirname(__file__)
        files_to_post = ( 
            os.path.join(root_dir, 'Query_XML/get_subjects_by_project.xml'),
            os.path.join(root_dir, 'Query_XML/get_mr_by_project.xml') if include_mr else '',
            os.path.join(root_dir, 'Query_XML/get_pet_by_project.xml') if include_pet else '',
            os.path.join(root_dir, 'Query_XML/get_fs_by_project.xml') if include_fs else ''
        )

        response_data = []
        #Now insert that project into the xml raw text.
        for file_path in files_to_post:

            if file_path == '':
                response_data.append({})
                continue

            raw_xml = ''
            with open(file_path, 'r') as xml_file:
                raw_xml = xml_file.read()

            raw_xml = raw_xml.replace('${PROJECT}', project_id)
            print(f'Sending template xml request "{os.path.basename(file_path)}" with inserted project ID {project_id} to server "{self._server}".')

            response_data.append(self.__query_xnat(raw_xml))
        
        subject, mr, pet, fs = tuple(response_data)
        self.__synthesize_queries(subject, mr, pet, fs)

    #----------------- report functions ------------------
    def generate_xnat_report(self,
                             project: str,
                             include_mr: bool,
                             include_pet: bool,
                             include_fs: bool,
                             report_path: str) -> None:
        
        #First we need to ensure that we are logged in.
        if not self._logged_in:
            print('You must log in to perform this opperation.')
            return

        #Now update internal data structure with CNDA data.
        self.__store_cnda_data(project,
                               include_mr,
                               include_pet,
                               include_fs)


        result = CustomFlatten.dict_to_dataframe(self.data)
        result.to_csv(report_path, index = False)
    
    def generate_missing_data_report(self,
                             project: str,
                             include_mr: bool,
                             include_pet: bool,
                             include_fs: bool,
                             report_path: str) -> None:
        
        #First we need to ensure that we are logged in.
        if not self._logged_in:
            print('You must log in to perform this opperation.')
            return

        #Now update internal data structure with CNDA data.
        self.__store_cnda_data(project,
                               include_mr,
                               include_pet,
                               include_fs)
        
        report_data = copy.deepcopy(self.data)
        #Now we should iterate through the sessions in a project and remove the data from self.data
        
        subjects_to_remove = []

        #Get all the uids in the given project.
        uids = self._database[project].distinct('_id')
        
        subject_object = Subject.Subject(self._projects_data, self._database, project)
        for uid in uids:
            subject_object.load_by_uid(uid, False)
            subject_accession  = subject_object.data[Definitions.SUBJECT_ACCESSION]
            
            if subject_accession in report_data:

                sessions_removed = 0
                total_sessions = 0

                if Definitions.SESSIONS in report_data[subject_accession]: 
                    total_sessions += len(report_data[subject_accession][Definitions.SESSIONS]) 
                if Definitions.PET_SESSIONS in report_data[subject_accession]: 
                    total_sessions += len(report_data[subject_accession][Definitions.PET_SESSIONS])
                #Now for each session check if it is either in the MR or PET Sessions field.
                for session_uid in subject_object.sessions:
                    session_accession = subject_object.sessions[session_uid].data[Definitions.SESSION_ACCESSION]

                    if Definitions.SESSIONS in report_data[subject_accession] and session_accession in report_data[subject_accession][Definitions.SESSIONS]:
                        del report_data[subject_accession][Definitions.SESSIONS][session_accession]
                        sessions_removed += 1
                    elif Definitions.PET_SESSIONS in report_data[subject_accession] and session_accession in report_data[subject_accession][Definitions.PET_SESSIONS]:
                        del report_data[subject_accession][Definitions.PET_SESSIONS][session_accession]
                        sessions_removed += 1

                if sessions_removed == total_sessions:
                    subjects_to_remove.append(subject_accession)
                
            subject_object.clear()
        
        #Now remove all the subjects we have fully cleared out.
        for subject_accession in subjects_to_remove:
            del report_data[subject_accession]

        result = CustomFlatten.dict_to_dataframe(report_data)
        result.to_csv(report_path, index = False)
