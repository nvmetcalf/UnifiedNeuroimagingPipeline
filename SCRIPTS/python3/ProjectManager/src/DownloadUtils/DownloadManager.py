#This is the program which manages and organizes file downloads from CNDA.

class DownloadManager(object):
    
    #Initializes the download manager. The point of this class is to provide a wrapper
    #around scripts which download and organize data from CNDA. contains an error state
    #which can be checked to see the success or failure of the current execution.
    def __init__(self, xnat_source: str, cnda_project: str) -> None:
        self.error_state = 0
        self.__xnat_site = xnat_source
        self.__project = cnda_project

    def verify_sub_ses_dicoms(self, data_path: str, map_id: int, ses_id: str, report_path = '') -> bool:
        has_all_data = False
        
        #Execute the verification shell scripts.
        # 1) Perform a search with the xnat api to get the 

        
        return has_all_data
          
