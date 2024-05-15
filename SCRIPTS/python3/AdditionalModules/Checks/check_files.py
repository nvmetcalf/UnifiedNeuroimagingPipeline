## ---------------------------------------------------------------------------------------------------------
#
# Checks any files found at the current line of the files exist.
#
# Current functions:
# 1) Checks for file and symlink existance.
#
# Written by Pete Canfield: Nov-2023
#
# Last updated: 1/25/2024
#
## ---------------------------------------------------------------------------------------------------------

import os
import re
import pdb 

#Takes the python match object as input. This can be further analized by looking at the groups.
#Additionally takes the current subject being processed in case this needs to be used
#for additional context.
def check_files(regex_match, this):
    
    #The match groups for the file names are 7 if surrounded by parentheses (will also pull out the qoutes so these 
    #need to be removed) and group 5 if there is only one value.
    
    file_names = regex_match.group(5).replace('"','') if regex_match.group(7) == None else regex_match.group(7).replace('"','')
    file_name_list = file_names.split()
    
    #There are no files to check.
    if file_names == '()':
        return 0

    #Now attempt to actually check for file existance at these paths.
    #Also check if they are sym links and if so check that the link is also valid.
    #Can check 
    rcode = 0
    try:
        #Expand the whole file path. 
        for f in file_name_list:
            path = os.path.join('dicom',f)
            os.stat(path)
    
    except FileNotFoundError:
        print(f"Could not find file {path}, file or symlink does not exist.")
        rcode = 8

    #Return the error code.
    return rcode
