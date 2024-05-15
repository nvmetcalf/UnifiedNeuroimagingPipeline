## ---------------------------------------------------------------------------------------------------------
#
# Extracts a parameter and its associated data from a line. Not sure if this is being used at all anymore.
#
# Current functions:
# 1) Extracts a parameter and its associated data from a line.
#
# Written by Pete Canfield: Nov-2023
#
# Last updated: 1/25/2024
#
## ---------------------------------------------------------------------------------------------------------

import os
import re

def extract_param(regex_match, this):
    
    rvalue = (None, None)

    try:
        #Extract the parameter name from the string itself.
        param = regex_match.string.split()[1]

        #The match groups for the file names are 7 if surrounded by parentheses (will also pull out the qoutes so these 
        #need to be removed) and group 5 if there is only one value.
        data = regex_match.group(5)
        rvalue = (param, data)

    except:
        print("Could not extract parameter from regex: %s" % regex)

    return rvalue 
