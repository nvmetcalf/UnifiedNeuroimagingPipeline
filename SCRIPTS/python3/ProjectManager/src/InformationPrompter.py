from bson.objectid import ObjectId
import copy

#from src.Subject import Subject
import src.DataModels.Definitions as Definitions

#Subject could not be type hinted due to circular imports. the subject_object is a Subject.
class SubjectInformationPrompter(object):
    def __init__(self, subject_object) -> None:
        self.__subject = copy.copy(subject_object)
        
        #This builds up what prompt functions to call given the data type of the information.
        self.__prompt_by_type = {
            str  : self.__prompt_string,
            list : self.__prompt_list
        }

        #Lets figure out which fields are available.
        #Fill in the MAP_ID
        map_id = self.__subject.data[Definitions.MAP_ID]
        if map_id == Definitions.MISSING_BY_TYPE[type(map_id)]:
            print(f'The map ID could not be resolved for subject, cannot prompt information')
            return
        
        self.has_data = {}
        self.no_data  = {}
        self.__session2uid = {}

        #Store the session_ids for the current subject in a list just because dicts are 
        #not always ordered based on python version. Additionally this is only used to associate
        #an index with each session for selection later.
        self.__session_ids = [] 
        
        
        #Build up a data structure for each session that keeps track of data that is filled out (has_data)
        #and data that is not filled out (no_data)
        for session_uid in self.__subject.sessions:
            session_object = self.__subject.sessions[session_uid]
            session_id = session_object.data[Definitions.SESSION_ID]
            
            if session_id in self.__session_ids:
                #Look for any other potential duplicate sessions and get the last one.
                session_number = 2

                #Generate all the possible duplicates in reverse order and try to find them in the
                #current list. The worst case is that every session in the list is a duplicate.
                for index in range(len(self.__session_ids) + 1, 1, -1):
                    if f'{session_id}_( copy {index} )' in self.__session_ids:
                        session_number = index + 1

                session_id = f'{session_id}_( copy {session_number} )'
                        

            
            self.__session_ids.append(session_id)
            self.__session2uid[session_id] = session_uid 
            self.has_data[session_id] = []
            self.no_data[session_id]  = []

            for session_key in session_object.data:
                #Skip over the session id because we already have that.
                if session_key == Definitions.SESSION_ID:
                    continue

                #Skip _id because that shouldnt be modifiable
                if session_key == '_id':
                    continue

                field = session_object.data[session_key]
                if Definitions.MISSING_BY_TYPE[type(field)] == field:
                    self.no_data[session_id].append(session_key)
                    continue
                
                self.has_data[session_id].append(session_key)


    def __prompt_string(self, prompt_text) -> str:  
        return input(prompt_text)
    
    #Prompts the user for a list of comma separated items. enforce_type attempts
    #to cast each item of the list to the given type. If this fails then the user is
    #prompted to enter a new valid list.
    def __prompt_list(self, prompt_text, enforce_type = str) -> list:
        
        final_list = []

        while True:
            user_input = input(prompt_text)

            final_list = user_input.split(',')

            if final_list[0] == '':
                print(f'The input {user_input} could not be parsed into a comma-seperated list, Try again.')
                continue


            #Now try to cast each member of the list to the correct type.
            try:
                final_list = [enforce_type(item) for item in final_list]
            except ValueError:
                print(f'Unable to cast all elements of the list: {user_input} to type {enforce_type}, Try again.')
                continue

            #Otherwise we are good to go.
            break
        
        return final_list

    
    #This will return T/F depending on if there is missing information in the given subject object.
    #Does not check duplicate or longitudinal data.
    def subject_incomplete(self) -> bool:
        for session in self.no_data:
            if len(self.no_data[session]):
                return True
        
        return False
    
    def print_subject(self) -> None:
        print('------------------------- Subject Information -------------------------')
        print(f'The first group ({Definitions.COLORS["GREEN"]}green{Definitions.COLORS["RESET"]}) is data that was automatically detected and set')
        print(f'The second group ({Definitions.COLORS["RED"]}red{Definitions.COLORS["RESET"]}) is data that could not be determined automatically')
        
        #Print out the subject and its map ID.
        print(f'{Definitions.COLORS["BOLD"]}Subject: {self.__subject.data[Definitions.MAP_ID]}{Definitions.COLORS["RESET"]}')
        
        for index, session in enumerate(self.__session_ids):
            print(f'\t{index + 1}. {Definitions.COLORS["CYAN"]}{session}{Definitions.COLORS["RESET"]}')
            
            #Get the session object.
            session_object = self.__subject.sessions[self.__session2uid[session]]
            for index,key in enumerate(self.has_data[session]):
                print(f'\t\t{index+1}. {Definitions.COLORS["GREEN"]}{key}: {session_object.data[key]}{Definitions.COLORS["RESET"]}')
            print() 
            for index,key in enumerate(self.no_data[session]):
                print(f'\t\t{index+1}. {Definitions.COLORS["RED"]}{key}: {session_object.data[key]}{Definitions.COLORS["RESET"]}')


        print()

    #This is the function that does most of the work for the information prompter. It prints the missing
    #information for a subject and prompts the user to enter said information in a useful way if required.
    def prompt_missing_information(self) -> dict:
        modified_data = {}

        allowed_session_inputs = [str(index + 1) for index in range(len(self.__session_ids))]
        while True:
            Definitions.CLEAR_SCREEN()
            self.print_subject()
            print('Type: (F)inished - to quit and save changes')
            print('Type: (Q)uit - to quit and discard changes')
            
            while True:
                session_choice = input(f'Enter the session you would like to modify ([(F)inished/(Q)uit to exit): ')
                if session_choice.lower() in (allowed_session_inputs + ['finished', 'quit', 'f', 'q']):
                    break
                
                #Otherwise it was not a valid input
                print(f'{session_choice} is not a valid option, try again.')

            #Now if we entered finished then that means we are done here.
            if session_choice.lower() in ['quit', 'q']:
                modified_data = {} # Clear it out.
                break

            if session_choice.lower() in ['finished', 'f']:
                break

            #Otherwise now we have to prompt for that session
            edit_session_id = ''
            for index, session in enumerate(self.__session_ids):
                if (int(session_choice) - 1) == index:
                    edit_session_id = session
                    break

            #Now lets prompt for the session.
            modification_choice = ''
            while True:
                modification_choice = input('Would you like to (A)dd or (M)odify data? ')
                if modification_choice.lower() in ['modify', 'add', 'm','a']:
                    break
                
                print(f'{modification_choice} is not a valid option, try again.')
                
            #Now we know if we want to modify data or not, lets ask what data to fill in.
            fields_to_modify = None 
            if modification_choice.lower() == 'm':
                fields_to_modify = self.has_data[edit_session_id]
            else:
                fields_to_modify = self.no_data[edit_session_id]
            
            #Now prompt for each index we want to modify.
            valid_options = [str(index + 1) for index in range(len(fields_to_modify))]
            #Add the exit option
            valid_options += ['done', 'd']

            while True:
                modification_choice = input('Enter the index of the field to modify or (D)one: ')
                if not modification_choice.lower() in valid_options:
                    print(f'{modification_choice} is not a valid option, try again.')
                    continue

                #Otherwise we hit a valid option.
                #Check if we are exiting, otherwise modify the respective field
                if modification_choice.lower() in ['done', 'd']:
                    break

                #Otherwise we are actually modifying a field.
                session_field = fields_to_modify[int(modification_choice) - 1]
                session_uid = self.__session2uid[edit_session_id]
                
                session_object = self.__subject.sessions[session_uid]

                modification_prompt = f'Enter the new value for {Definitions.COLORS["UNDERLINE"]}{session_field}{Definitions.COLORS["RESET"]} (lists should be comma-separated): '

                new_data = self.__prompt_by_type[type(session_object.data[session_field])](modification_prompt)
                
                #Set the data appropriately.
                if not session_uid in modified_data:
                    modified_data[session_uid] = {}

                modified_data[session_uid][session_field] = new_data
                session_object.data[session_field]        = new_data #Do this for display purposes.

                #Now check if we are modifying already existing data or if we are adding new data.
                if fields_to_modify == self.no_data:
                    self.has_data[edit_session_id].append(session_field)
                    fields_to_modify.remove(session_field)

                    #Clear the screen and re-print with new information:
                    Definitions.CLEAR_SCREEN()
                    self.print_subject()

        return modified_data

#Session could not be type hinted due to circular imports. the sessionn_object is a Session.
class SessionInformationPrompter(object):
    def __init__(self, session_object) -> None:
        self.__session = session_object
        self.session_fields = []

        for field in self.__session.data:

            #Done let the _id or session_id fields be modifiable.
            if field == '_id':
                continue
            if field == Definitions.SESSION_ID:
                continue

            self.session_fields.append(field)

    def print_session(self, highlight_fields='') -> None:
        print(f'Session: {Definitions.COLORS["CYAN"]}{self.__session.data[Definitions.SESSION_ID]}{Definitions.COLORS["RESET"]}')

        for field in self.session_fields:
            print(f'\t{highlight_fields}{field}{Definitions.COLORS["RESET"]}: {self.__session.data[field]}')


    def print_merge_conflict_prompt(self, conflicting_keys: list, conflicting_data:dict) -> None:
        print(f'------------------------- Session {self.__session.data[Definitions.SESSION_ID]} Merge Issue -------------------------')
        print(f'It appears that the current session could not automatically merge because the existing')
        print(f'data and the incoming data both seem plausable. Please choose the desired data you want to keep to continue.')
        print(f'The current data is shown in {Definitions.COLORS["GREEN"]}green{Definitions.COLORS["RESET"]} and the incoming data is showin in {Definitions.COLORS["RED"]}red{Definitions.COLORS["RESET"]}.')
       
        self.print_session(highlight_fields=Definitions.COLORS["GREEN"])

        print('\nIncoming Data:')
        for index, field in enumerate(conflicting_keys):
            print(f'\t{index + 1}. {Definitions.COLORS["RED"]}{field}{Definitions.COLORS["RESET"]}: {conflicting_data[field]}')

    #This function takes a dictionary of fields that conflict in a given session with plausable
    #data and asks the user to merge the data based on what they want to keep. It returns a dictionary
    #of the final decided values the user wants to keep.
    def prompt_conflicting_information(self, conflicting_data:dict ) -> dict:
        resolved_values = {} 
        #Set the resolved to the current data.
        for key in conflicting_data:
            resolved_values[key] = self.__session.data[key]

        conflicting_keys = list(conflicting_data)
        #Set the resolved data to be all the incoming data at the moment.
        while True:
            self.print_merge_conflict_prompt(conflicting_keys, conflicting_data)

            valid_fields = [str(index + 1) for index in range(len(conflicting_keys))] + ['done', 'd', 'accept', 'a']

            while True:
                user_field = input('Enter the index of the field you want to select [(D)one to accept current state or (A)ccept all incoming changes]: ')
                if not user_field.lower() in valid_fields:
                    print(f'The choice {user_field} is not a valid option. Try again.')
                    continue

                break
            
            if user_field.lower() in ['done', 'd']:
                break
            
            #Then we need to add all the current conflicting values to resolved and exit.
            if user_field.lower() in ['accept', 'a']:
                for key in conflicting_data:
                    resolved_values[key] = conflicting_data[key]

                break

            selected_field = conflicting_keys[int(user_field) - 1]

            #Otherwise we have selected a field to judge.
            while True:
                judgment = input('Would you like to (A)ccept the incoming change or (R)eject it? ')
                if not judgment.lower() in ['accept', 'a', 'reject', 'r']:
                    print(f'The choice {user_field} is not a valid option. Try again.')
                    continue

                break
            
            #If we accepted the change then we should set the resolved data at the given key to be the new data.
            #Swap them so that we still have the old data as an option.
            if judgment.lower() in ['accept', 'a']:
                old_data = self.__session.data[selected_field] 
                new_data = conflicting_data[selected_field]

                self.__session.data[selected_field] = new_data
                resolved_values[selected_field] = new_data 
                
                conflicting_data[selected_field] = old_data
            
            Definitions.CLEAR_SCREEN()

        return resolved_values


class ExtractionInformationPrompter(object):
    def __init__(self, projects_data: dict, project: str) -> None:
        self.__scan_location_data = copy.deepcopy(projects_data[Definitions.PROJECTS][project][Definitions.SCAN_LOCATIONS])
        self.__scan_locations = list(self.__scan_location_data.keys())
        self.__project = project

    def print_scan_locations(self):
        print(f'------------------------- Project {self.__project} Scan Locations -------------------------')
        print(f'The following is all scan locations listed with associated scanner aliases.')
        print(f'The scan location is shown in {Definitions.COLORS["CYAN"]}cyan{Definitions.COLORS["RESET"]} and the associated scan locations are is shown in {Definitions.COLORS["GREEN"]}green{Definitions.COLORS["RESET"]}.')
        
        for index, field in enumerate(self.__scan_locations):
            print(f'\t{index + 1}. {Definitions.COLORS["CYAN"]}{field}{Definitions.COLORS["RESET"]}: {Definitions.COLORS["GREEN"]}{self.__scan_location_data[field]}{Definitions.COLORS["RESET"]}')
    
    #Prompts the user to add a new scan source to the current project. Returns a string associated with the scan location to add the scan source to.
    #Returns '' if no scan source is specified.
    def prompt_scan_source(self, scanner_name: str) -> str:
        
        add_scanner = True 
        while True:
            option = input(f'Would you like to add the current scanner {scanner_name} to a scan source [(Y)es/(N)o]? ')
            
            if not option.lower() in ['y', 'yes', 'n', 'no']:
                continue

            if option.lower() in ['n', 'no']:
                add_scanner = False

            break
        
        if not add_scanner:
            return ''
        
        accepted_scan_location = ''
        self.print_scan_locations()
        while True:
            valid_options = [str(index + 1) for index in range(len(self.__scan_locations))] + ['n', 'new']

            option = input(f'Enter the index of the scan source you want to add the scanner {scanner_name} ([N]ew to add a new scan source) ')

            if not option.lower() in valid_options:
                print(f'The scan source {option} is invalid.')
                continue 

            if option.lower() in ['n', 'new']:

                accept_changes = False
                abbort         = False
                scan_location = ''
                while not (accept_changes or abbort):
                    scan_location = input('Enter the new scan location: ')
                    
                    while True:
                        option = input(f'Would you like to accept the new scan location {scan_location} ([Y]es/[N]o/[A]bbort)? ')

                        if not option.lower() in ['y', 'yes', 'n', 'no', 'a', 'abbort']:
                            print(f'The option {option} is invalid.')
                            continue
                        
                        if option.lower() in ['a', 'abbort']:
                            abbort = True  

                        if option.lower() in ['y', 'yes']:
                            accept_changes = True

                        break
                    
                if abbort:
                    continue

                return scan_location

            #Otherwise we want to add to an index.
            scan_location = self.__scan_locations[int(option) -  1]
            accept_changes = False
            while True:
                option = input(f'Would you like to accept the new scan location {scan_location} ([Y]es/[N]o)? ')

                if not option.lower() in ['y', 'yes', 'n', 'no']:
                    print(f'The option {option} is invalid.')
                    continue

                if option.lower() in ['y', 'yes']:
                    accept_changes = True

                break
            
            if accept_changes:
                accepted_scan_location = scan_location
                break

        return accepted_scan_location
            
