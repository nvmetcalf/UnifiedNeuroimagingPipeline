import pyxnat
import shutil
import pandas
import os
import glob
import json

import src.DataModels.Definitions as Definitions
import src.DataModels.QueryDefinitions as QueryDefinitions
import src.Subject as Subject
import src.Utils.DatabaseManager as DatabaseManager

class XNATQueryManager(DatabaseManager.DatabaseManager):
    def __init__(self, database_name: str, server: str, user_name: str, project: str, log_file: str) -> None:
        
        #Connect to the database.
        super().__init__(database_name, project, log_file)
        
        self.log(f'Please enter you password for {server}')
        self.__xnat = pyxnat.Interface(server = server, user = user_name)
        self.__project = project
        self.__project_id = ''
    
        #Store current query.
        self.__query_root_element = ''
        self.__query_elements = []

        try:
            self.__project_id = self._projects_data[Definitions.PROJECTS][project][Definitions.PROJECT_ID]
        except KeyError:
            self.log(f'Could not find either the project {project} or the associated {Definitions.PROJECT_ID}. Make sure that this is formed correctly.')
            raise ValueError

        #Load in the stored queries from the DB.
        #Stored queries are organized by name then include root element and additional elements.
        self.__stored_queries = {}
        self.__stored_queries_collection = self._database[QueryDefinitions.DB_QUERY_COLLECTION]

        #go through each file and add it to the stored queries collection in the database.
        default_query_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'Default_Queries')
        for fname in glob.glob(f'{default_query_path}/*.json'):
            json_data = {}
            try:
                file = open(os.path.join(default_query_path, fname), 'r')
                json_data = json.load(file)
                file.close()
            except:
                continue
            default_name = json_data[QueryDefinitions.NAME]
            query_data = {
                QueryDefinitions.ROOT     : json_data[QueryDefinitions.ROOT],
                QueryDefinitions.ELEMENTS : json_data[QueryDefinitions.ELEMENTS]
            }
            
            #Now upload the document to the database.
            self.__stored_queries_collection.update_one({QueryDefinitions.NAME : default_name},
                                                        {'$set'                : query_data},
                                                        upsert = True)

        #Now try to load in the default queries that are included by default.
        try:

            for query in self.__stored_queries_collection.find({}):
                data_name    = query[QueryDefinitions.NAME]
                root_element = query[QueryDefinitions.ROOT]
                data         = query[QueryDefinitions.ELEMENTS]
                
                self.__stored_queries[data_name] = {
                    QueryDefinitions.ROOT     : root_element,
                    QueryDefinitions.ELEMENTS : data
                }
        except:
            self.log('Could not load stored queries')
        

    #----------------- Data organization helper functions ------------------
    def __get_stored_root_elements(self) -> list:

        root_elements = []
        for query_data in self.__stored_queries.values():
            if not QueryDefinitions.ROOT in query_data:
                continue

            root_elements.append(query_data[QueryDefinitions.ROOT])

        return root_elements


    def __convert_response_to_dataframe(self, response: list) -> pandas.DataFrame:

        if len(response) == 0:
            return pandas.DataFrame()
        
        rows = iter(response)
        first_row = next(rows)

        flattened = {}
        for col,value in first_row.items():
            flattened[col] = [ value ] 

        for row in rows:
            for col,value in row.items():
                flattened[col].append(value)
        
        return pandas.DataFrame.from_dict(flattened)
    
    #Given a response list and two keys in the response, return a mapping from key A -> key B.
    def __convert_response_to_mapping(self, response: list, mappings: tuple) -> tuple:
        map_tuple = tuple({} for _ in range(len(mappings)))
        
        if len(response) == 0 or len(mappings) == 0:
            return map_tuple
        
        for row in response:
            
            #Go through each of the mapping pairs.
            for index, (a,b) in enumerate(mappings):
                if not (a in row or b in row):
                    continue
                
                map_tuple[index][row[a]] = row[b]
        
        return map_tuple


    #----------------- Prompting helper functions ------------------
    def __generate_query_printing_string(self) -> str:

        if self.__query_root_element == '' or len(self.__query_elements) == 0:
            return ''

        display = f'Current Query Root Element: {self.__query_root_element}\n'
        for element in self.__query_elements[:-1]:
            display += f'├──{element}\n' 

        display += f'└──{self.__query_elements[-1]}\n'

        return display

    #This function takes two lists and prints the data on the left and right side of the side of the screen
    def __print_two_columns(self, left_data: list, right_data: list) -> None:
        
        # Get the size of the terminal window
        columns, _ = shutil.get_terminal_size()
        
        # Divide the terminal width into two equal parts
        col_width = columns // 2

        # Ensure both columns are padded properly
        left_data = left_data + [""] * (max(len(left_data), len(right_data)) - len(left_data))
        right_data = right_data + [""] * (max(len(left_data), len(right_data)) - len(right_data))
        
        # Print each pair of rows from the left and right columns
        for left, right in zip(left_data, right_data):
            print(f"{left:<{col_width}}{right:<{col_width}}")

    #This is a general helper function which is meant to make prompting for list of options easier.
    #Takes three arguments.
    # 1. The options to display
    # 2. A hidden set which can be additionally selected if needed.
    # 3. The header to text to display for additional information.
    # 4. The maximum number of items that are allowed in the selection. 0 -> no limit.
    #Returns:
    # A list of selected keys.
    def __prompt_item(self, options: list, hidden_options = [], header_text = '', selection_limit = 0) -> list:

        #Keys for indexing.
        show_hidden = False 
        while True:
            selected_indices = []
            selection_index = 1

            Definitions.CLEAR_SCREEN()
            if header_text != '':
                print(header_text)

            left_screen_data = []
            right_screen_data = self.__generate_query_printing_string().splitlines()

            for field in options:
                left_screen_data.append(f'\t{Definitions.COLORS["CYAN"]}{selection_index}.{Definitions.COLORS["RESET"]} {Definitions.COLORS["GREEN"]}{str(field)}{Definitions.COLORS["RESET"]}')
                selection_index += 1
            
            if show_hidden:
                for field in hidden_options:
                    left_screen_data.append(f'\t{Definitions.COLORS["CYAN"]}{selection_index}.{Definitions.COLORS["RESET"]} {Definitions.COLORS["GREEN"]}{str(field)}{Definitions.COLORS["RESET"]}')
                    selection_index += 1

            self.__print_two_columns(left_screen_data, right_screen_data)

            prompt_text = 'Please enter the data index of the selection you are are interested in.'
            input_text = 'Enter a comma separated list of indices: '
            
            allowed_selection = [str(i) for i in range(1, selection_index)]

            if len(hidden_options) > 0 and not show_hidden:
                prompt_text += ' A/a to show all queriable data.' 
                input_text = input_text[:-1] +  '([A]ll): '
                allowed_selection.append('a')

            print(prompt_text)
            selection = input(input_text).replace(' ','').split(',')

            if selection_limit != 0 and len(selection) > selection_limit:
                continue

            if len(hidden_options) != 0 and not show_hidden and len(selection) == 1 and selection[0].lower() == 'a':
                show_hidden = True
                continue
        
            check_indices = []
            #Otherwise we need to try to convert each string to ints.
            retry = False
            for choice in selection:
                try:
                    index = int(choice) 

                    #Cant be out of bounds.
                    if index > selection_index:
                        break

                    check_indices.append(index - 1)
                except ValueError:
                    print(f'The selection {choice} is not a valid selection.')
                    retry = True
                    break
            
            if retry:
                continue

            if len(check_indices) != len(selection):
                continue

            selected_indices = check_indices
            break
        
        #Now figure out what to return.
        selected = [] 
        options_len = len(options)
        for index in selected_indices:
            
            if index >= options_len:
                selected.append(hidden_options[index - options_len])
                continue

            selected.append(options[index])
        
        return selected

    #This function uploads the current query to the database.
    def __save_query(self) -> None:

        while True:
            selection = input('Would you like to save the current query (Y/N)? ').lower()
            if selection == 'y':
                #Save the query
                query_data = {
                    QueryDefinitions.ROOT : self.__query_root_element,
                    QueryDefinitions.ELEMENTS : self.__query_elements
                }

                #Ask what name they want
                query_name = ''
                while True:
                    query_name = input('Enter a name for the current query: ')
                    selection = input(f'Would you like to save the query {query_name} (Y/N)? ').lower()
                    if selection == 'y':
                        break
                
                self.__stored_queries_collection.update_one({QueryDefinitions.NAME : query_name},
                                                            {'$set'                : query_data},
                                                            upsert = True)
                break

            elif selection == 'n':
                break

    def __select_stored_query(self) -> None:
        saved_query_list = self.__prompt_item(list(self.__stored_queries.keys()), header_text='Select a saved query to load.', selection_limit=1)
        query = saved_query_list[0]

        self.__query_root_element = self.__stored_queries[query][QueryDefinitions.ROOT]
        self.__query_elements = self.__stored_queries[query][QueryDefinitions.ELEMENTS]
    
    #----------------- Main query function ------------------
    def __query(self, filter_local_data: bool) -> list:
        
        #First we need to ask if they want to just submit a default query or not. If so just select one and move on.
        Definitions.CLEAR_SCREEN()
        use_default = False
        prompt_to_save = True

        #Prompt if we want to load stored queries if there are any queries to choose from
        while len(self.__stored_queries) > 0:
            option = input('Would you like to load a stored query (Y/N)? ').lower()

            if option == 'y':
                prompt_to_save = False
                use_default = True
                break

            if option == 'n':
                break
        
        #Now if we are using a default query then lets prompt which one they want.
        if use_default:
            self.__select_stored_query()
        
        #get all the search groups
        xnat_search_groups = self.__xnat.inspect.datatypes()
        
        #Ask if we want to add selection to the search groups.
        all_main_keys = self.__get_stored_root_elements()
        all_additional_keys = list(filter(lambda x: x not in all_main_keys, xnat_search_groups))
        
        if len(all_main_keys) == 0:
            all_main_keys = all_additional_keys
            all_additional_keys = []

        #If we didnt use a default query then we have to select a root element.
        if not use_default:
            selected_root_list = self.__prompt_item(all_main_keys, 
                                                    all_additional_keys, 
                                                    header_text = 'Select a root element.', 
                                                    selection_limit = 1)

            self.__query_root_element = selected_root_list[0]

            #Now ask what data to include in the query.
            xsi_elements = self.__xnat.inspect.datatypes(self.__query_root_element)
            self.__query_elements = self.__prompt_item(xsi_elements,
                                                       header_text = f'Select data elements for {self.__query_root_element}.')

        while True:
            option = input('Would you like to load any additional search groups (Y/N)? ').lower()
            if option == 'y':

                prompt_to_save = True

                #Now add the additional selections to the query data.
                selected_keys = self.__prompt_item(all_main_keys, all_additional_keys,
                                                   header_text='Select search group(s).')
                for key in selected_keys:
                    #Get the search dict.
                    xsi_keys = self.__xnat.inspect.datatypes(key)
                    selected_keys = self.__prompt_item(xsi_keys,
                                                       header_text = f'Select the additional elements to add to the {key} query')
                    
                    self.__query_elements += selected_keys

                break

            if option == 'n':
                break
        
        #Do the query.
        self.log('Sending query ...')
        response = self.query_xnat()

        self.log('Query complete.')
        if prompt_to_save:
            self.__save_query()

        #Now ask if we need to filter out local data.
        query_name = ''
        if self.__query_root_element in QueryDefinitions.ROOT2QUERY:
            query_name = QueryDefinitions.ROOT2QUERY[self.__query_root_element]

        if filter_local_data and query_name != '':

            subject_object = Subject.Subject(self._projects_data, self._database, self.__project, self)
            
            #Get the associated mappings for subject accession and potentially session accession (depending on root element).
            subject_accession_col = QueryDefinitions.DEFAULT_QUERIES[query_name]['subject_accession']
            
            #Get the session_accession if it exists. 
            session_accession_col = ''
            if 'session_accession' in QueryDefinitions.DEFAULT_QUERIES[query_name]:
                session_accession_col = QueryDefinitions.DEFAULT_QUERIES[query_name]['session_accession']

            
            #If both the subject_accession_col and session_accession_col are specified then skip rows 
            #have mathing entries for both. Otherwise just skip for matching subject_accession_col entries.
            filtered_response = []
            for row in response:
                #Load the subject associated with this row.
                if not subject_object.load_by_cnda_id(row[subject_accession_col], False):
                    filtered_response.append(row)
                    continue
                
                #If the session_accession was not specified then we need to filter this one out.
                if session_accession_col == '':
                    subject_object.clear()
                    continue
                
                #If the session accession was specified then we need to go through all the local sessions
                #and see if there is a match.
                found_match = False
                for session_uid in subject_object.sessions:
                    session_object = subject_object.sessions[session_uid]

                    if session_object.data[Definitions.SESSION_ACCESSION] == row[session_accession_col]:
                        found_match = True
                        break
                
                #If the session accession was found then filter it out otherwise do nothing.
                if not found_match:
                    filtered_response.append(row)
                
                subject_object.clear()

            response = filtered_response

        return response

    #----------------- update functions ------------------
    def update_accession_from_xnat(self) -> None:
        #First do the subject the subject query.
        self.__query_root_element = self.__stored_queries[QueryDefinitions.SUBJECT_ACCESSION_QUERY][QueryDefinitions.ROOT]
        self.__query_elements = self.__stored_queries[QueryDefinitions.SUBJECT_ACCESSION_QUERY][QueryDefinitions.ELEMENTS]
        self.log('Sending subject accession query...')
        subject_response = self.query_xnat()

        #Now generate a mapping from the subject id to subject accession
        subject_pairing = (
            (
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.SUBJECT_ACCESSION_QUERY]['subject_id'],
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.SUBJECT_ACCESSION_QUERY]['subject_accession']
            ),
        )
        subject_mapping = self.__convert_response_to_mapping(subject_response, subject_pairing)[0]

        #Now do the mr session query.
        self.__query_root_element = self.__stored_queries[QueryDefinitions.MR_ACCESSION_QUERY][QueryDefinitions.ROOT]
        self.__query_elements = self.__stored_queries[QueryDefinitions.MR_ACCESSION_QUERY][QueryDefinitions.ELEMENTS]
        self.log('Sending mr accession query...')
        session_response = self.query_xnat()

        mr_pairing = (
            (
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.MR_ACCESSION_QUERY]['subject_id'],
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.MR_ACCESSION_QUERY]['subject_accession']
            ),
            (
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.MR_ACCESSION_QUERY]['session_id'],
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.MR_ACCESSION_QUERY]['session_accession']
            ),
            (
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.MR_ACCESSION_QUERY]['session_id'],
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.MR_ACCESSION_QUERY]['fs_accession']
            )
        )

        #Now generate the mappings for the mr and pet sessions
        mr_subject_mapping, mr_session_mapping, mr_fs_mapping = self.__convert_response_to_mapping(session_response, mr_pairing)
        
        #Now do the pet session query.
        self.__query_root_element = self.__stored_queries[QueryDefinitions.PET_ACCESSION_QUERY][QueryDefinitions.ROOT]
        self.__query_elements = self.__stored_queries[QueryDefinitions.PET_ACCESSION_QUERY][QueryDefinitions.ELEMENTS]
        self.log('Sending pet accession query...')
        session_response = self.query_xnat()

        pet_pairing = (
            (
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.PET_ACCESSION_QUERY]['subject_id'],
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.PET_ACCESSION_QUERY]['subject_accession']
            ),
            (
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.PET_ACCESSION_QUERY]['session_id'],
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.PET_ACCESSION_QUERY]['session_accession']
            ),
            (
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.PET_ACCESSION_QUERY]['session_id'],
                QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.PET_ACCESSION_QUERY]['fs_accession']
            )
        )
        
        #Now generate the mappings for the mr and pet sessions
        pet_subject_mapping, pet_session_mapping, pet_fs_mapping = self.__convert_response_to_mapping(session_response, pet_pairing)

        #Update all accession values for exact matches.
        self.log('Updating accession values for all exact matches')
        for subject_object in self._generate_subject_by_project(False):

            subject_id = subject_object.data[Definitions.MAP_ID]
            if subject_id in subject_mapping:
                subject_object.update_metadata({ Definitions.SUBJECT_ACCESSION : subject_mapping[subject_id] }, True)

            #Now we have loaded the subject try to get the session.
            for session_uid in subject_object.sessions:
                session_object = subject_object.sessions[session_uid]

                session_id = session_object.data[Definitions.SESSION_ID]
                if session_id in mr_session_mapping:
                    session_object.update({Definitions.SESSION_ACCESSION : mr_session_mapping[session_id]}, True)
                
                if session_id in mr_fs_mapping:
                    session_object.update({Definitions.FS_ACCESSION : mr_fs_mapping[session_id]}, True)
                
                if session_id in pet_session_mapping:
                    session_object.update({Definitions.SESSION_ACCESSION : pet_session_mapping[session_id]}, True)
                
                if session_id in pet_fs_mapping:
                    session_object.update({Definitions.FS_ACCESSION : pet_fs_mapping[session_id]}, True)

    #----------------- report functions ------------------
    def generate_report(self, exclude_local: bool, report_path: str) -> None:
        
        query_data = self.__query(exclude_local)
        result = self.__convert_response_to_dataframe(query_data)
        result.to_csv(report_path, index = False)
    
    #----------------- external query functions ------------------
    def set_query(self, root_element: str, queries: list) -> None:
        self.__query_root_element = root_element
        self.__query_elements = queries

    def query_xnat(self) -> list:
        
        if self.__query_root_element == '' or len(self.__query_elements) == 0:
            return {}

        query_filters = [
            (f"{self.__query_root_element}/sharing/share/project", '=', self.__project_id),
            'OR',
            (f"{self.__query_root_element}/PROJECT", '=', self.__project_id)
        ]
        
        try:
            response = self.__xnat.select(self.__query_root_element, self.__query_elements).where(query_filters)
        except Exception as e:
            self.log('There was an error processing this query. Could not get data.')
            self.log(e)
            return []

        return response.data
    #----------------- filter results ------------------
    #This function takes a dictionary of existing accession values and returns query results
    #matching the accession structure in the input dictionary.
    def get_remote_extended_query(self, show_remote_columns: bool) -> dict: 

        final = {} 
        #First load the mr accession query. Ask what data to include with it addtionally.
        self.__query_root_element = self.__stored_queries[QueryDefinitions.SUBJECT_ACCESSION_QUERY][QueryDefinitions.ROOT]
        self.__query_elements = self.__stored_queries[QueryDefinitions.SUBJECT_ACCESSION_QUERY][QueryDefinitions.ELEMENTS]
        

        while True:
            selection = input('Would you like to add any additional xnat subject data (Y/N)? ').lower()
            if selection == 'y':
                xsi_keys = self.__xnat.inspect.datatypes(self.__query_root_element)
                selected_keys = self.__prompt_item(xsi_keys, header_text = f'Select the additional elements to add to the {self.__query_root_element} query')
                             
                self.__query_elements += selected_keys
                break

            if selection == 'n':
                break

        #Now do the mr query.
        print(f'Sending {QueryDefinitions.SUBJECT_ACCESSION_QUERY} query ...')
        subject_response = self.query_xnat()
        
        subject_accession_col = QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.SUBJECT_ACCESSION_QUERY]['subject_accession']
        #Now go through each row and if there is a hit in the organized_data add it there.
        #this could be optimized by pulling out the columns from each row once at the beginning.
        for row in subject_response:
            if not row[subject_accession_col] in final:
                final[row[subject_accession_col]] = {}
            
            #Copy everything over except for the subject_accession column
            for col in row:
                if not show_remote_columns and col in QueryDefinitions.DEFAULT_QUERIES[QueryDefinitions.SUBJECT_ACCESSION_QUERY].values():
                    continue

                final[row[subject_accession_col]][f'remote.{QueryDefinitions.SUBJECT_ACCESSION_QUERY}.{col}'] = row[col]
            
        #Do the MR and PET queries.
        #Do this by building up an accession tree and adding the elements from those to the organized_data tree.
        base_queries = [
            (QueryDefinitions.MR_ACCESSION_QUERY, Definitions.SESSION_DATA),
            (QueryDefinitions.PET_ACCESSION_QUERY, Definitions.SESSION_DATA)
        ]
        
        for query, group in base_queries:
            #First load the mr accession query. Ask what data to include with it addtionally.
            self.__query_root_element = self.__stored_queries[query][QueryDefinitions.ROOT]
            self.__query_elements = self.__stored_queries[query][QueryDefinitions.ELEMENTS]

            while True:
                selection = input(f'Would you like to add any additional {query} data (Y/N)? ').lower()

                if selection == 'y':
                    xsi_keys = self.__xnat.inspect.datatypes(self.__query_root_element)
                    selected_keys = self.__prompt_item(xsi_keys, header_text = f'Select the additional elements to add to the {self.__query_root_element} query')
                                 
                    self.__query_elements += selected_keys
                    break

                if selection == 'n':
                    break

            #Now do the mr query.
            self.log(f'Sending {query} query ...')
            response = self.query_xnat()

            subject_accession_col = QueryDefinitions.DEFAULT_QUERIES[query]['subject_accession']
            session_accession_col = QueryDefinitions.DEFAULT_QUERIES[query]['session_accession']

            for row in response:
                try:
                    subject_accession = row[subject_accession_col]
                    session_accession = row[session_accession_col]
                except KeyError:
                    break
                
                #Now add the session entry to the tree.
                data = {}
                for col in row:
                    if not show_remote_columns and col in QueryDefinitions.DEFAULT_QUERIES[query].values():
                        continue

                    #Skip the columns that are included in the default query.
                    data[f'remote_{query}.{col}'] = row[col]

                #Now add the data from this row to the final response tree.
                if not subject_accession in final:
                    final[subject_accession] = {
                        group : { 
                             session_accession : data 
                        }
                    }
                    continue
                
                if not group in final[subject_accession]:
                    final[subject_accession][group] = {
                        session_accession : data
                    }
                    continue

                if not session_accession in final[subject_accession][group]:
                    final[subject_accession][group][session_accession] = data
                    continue

                final[subject_accession][group][session_accession].update(data)
        
        return final
