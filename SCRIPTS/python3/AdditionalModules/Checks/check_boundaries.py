## ---------------------------------------------------------------------------------------------------------
#
# Checks if a given parameter is within boundaries defined in Boundries.json.
#
# Current functions:
# 1) Checks if the parameter at the current line is within boundaries.
#
# Written by Pete Canfield: Nov-2023
#
# Last updated: 1/25/2024
#
## ---------------------------------------------------------------------------------------------------------


import re
import os
import json
import math

def check_boundaries(match, this):
    
    boundaries = '$PP_SCRIPTS/python3/AdditionalModules/Checks/Boundries.json'
    boundaries = os.path.expandvars(boundaries)

    boundry_data = None
    try:
        f = open(boundaries, 'r')
        boundry_data = json.load(f)
        f.close()
    except:
        print('No paramter boundry file found at: %s' % boundaries)
        return 9
    
    #Now lets figure out which parameter we are dealing with.
    #Extract the parameter.
    parameter = match.string.split()[1]
    
    #Extract the values.
    values = []
    if match.group(7) == None: 
        values.append(float(match.group(5)))
    else:
        values = [float(i) for i in match.group(7).split()]

    #Now make sure its in the specified range.
    match_all = True 
    for value in values:
        minimum = boundry_data['numeric'][parameter]['min']
        maximum = boundry_data['numeric'][parameter]['max']
        if not ((value > minimum and value < maximum) or (math.isclose(value,minimum,abs_tol=1e-10) or math.isclose(value,maximum,abs_tol=1e-10))):
            print('Parameter not in range [%f,%f] specified in boundry file: %s' % (minimum, maximum, boundaries)) 
            match_all = False
            break

    return 0 if match_all else 10
