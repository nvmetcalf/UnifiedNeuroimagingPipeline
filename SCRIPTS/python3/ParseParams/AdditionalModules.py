## ---------------------------------------------------------------------------------------------------------
#
# Checks if a given parameter is within boundaries defined in Boundries.json.
#
# Current functions:
# 1) Checks if the parameter at the current line is within boundaries.
# 2) Checks if specified dicom files exist and if symlinks exist. Additionally checks if dicom
#    file extensions are allowed (Defined in Boundaries.json).
# 3) Suggests field map types based on if possible field maps are detected in the dicom files.
# 4) Checks if day1 path exists (This needs improvement because currently it skips this check if
#    shell expansion is required because I havent figured out how to do that yet in this case.
# 5) Checks if an ASL time inversion is 0 and sequnce is PASL, this should only be the case in 
#    pcASL.
# 6) Warns if field mapping is set to none, worst case it should be synth.
# 7) Checks if all BOLD scans have a consistent multiband acceleration factor, warns if not.
# 8) Checks if all BOLD and PET scans have consistent dimensions, fails if not.
#
# Written by Pete Canfield: Nov-2023
#
# Last updated: 1/24/2025
#
## ---------------------------------------------------------------------------------------------------------

import os
import re
import json
import math
import subprocess

#Checks to see if a given parameter is within reasonable boundaries defined
#in Boundaries.json
def check_boundaries(regex_match, this):
    #Now lets figure out which parameter we are dealing with.
    #Extract the parameter.
    parameter = regex_match.string.split()[1]
    
    #Extract the values.
    values = [float(value) for value in re.findall(r"-?\d*\.\d+", regex_match.string)]

    #Now make sure its in the specified range.
    regex_match_all = True 
    for value in values:
        minimum = this.boundary_data['numeric'][parameter]['min']
        maximum = this.boundary_data['numeric'][parameter]['max']
        if not ((value > minimum and value < maximum) or (math.isclose(value,minimum,abs_tol=1e-10) or math.isclose(value,maximum,abs_tol=1e-10))):
            print('Parameter not in range [%f,%f] specified in boundry file' % (minimum, maximum)) 
            regex_match_all = False
            
            break
    
    return 0 if regex_match_all else 10


#Checks particularly the field mapping paramter. If field map files have been specified then check that they exist,
#otherwise look at all the files in the dicom folder. If there are any files that have ap, AP, pa, PA in the file
#name then output a warning that the files were found and could potentially be field maps.
def check_field_maps(regex_match, this, fm_type):
    #First check for the usual file existance.
    r_code = check_dicom_files(regex_match, this)
    if r_code:
        return r_code
    

    #Now if we get to this point then the field maps should be stored in the match_map.
    field_maps = this.match_map[fm_type]
    
    #If there are field maps already set then they are probably correct. This is just meant to
    #detect possible field maps if they havent been set.
    if len(field_maps):
        return 0

    #Get all the files in the dicom directory.
    #convert the strings to lowercase.
    dicom_files = [f for f in os.listdir('./dicom') if os.path.isfile(os.path.join('./dicom', f))]

    possible_field_maps = []

    #Exlude all the file names that contain this text.
    exclusion_patterns = ['.json']

    patterns = ['ap', 'pa', 'field', 'map', 'gre']
    for fname in dicom_files:
        lowercase = fname.lower()
        
        for pattern in patterns:
            if pattern in lowercase:
                if not fname in possible_field_maps:
                    
                    #Now check all the exlusion patterns and exclude file names that contain those.
                    good_fname = True
                    for ep in exclusion_patterns:
                        if ep in lowercase:
                            good_fname = False
                            break
                    
                    if good_fname:    
                        possible_field_maps.append(fname)
        
        

    #If there are no suspicious looking files then just exit normally.
    if not len(possible_field_maps):
        return 0

    #Otherwise lets create the error string.
    error_message = 'no field maps set in %s but the following potiental field maps were detected in the dicom folder:\n' % fm_type
    for fname in possible_field_maps:
        error_message += fname + '\n' 

    #Remove the trailing newline
    error_message = error_message[:-1]

    return this.process_warning(error_message, e_level = 2)

#The issue with executing these functions now is that
#they depend on other paramters being set in the params file to do all their checks. So what needs to
#be done is the function and the right function parameters need to be stored for later execution after all the other
#Lines have been read in and extracted to ensure that the required info is always there if it exists.

#Wraps check_field_maps but sets the key to be BOLD_fm
def check_BOLD_field_maps(regex_match, this):
    this.queue_funct(check_field_maps, (regex_match, this, 'BOLD_fm'))
    return 0

#Wraps check_field_maps but sets the key to be ASL_fm
def check_ASL_field_maps(regex_match, this):
    this.queue_funct(check_field_maps, (regex_match, this, 'ASL_fm'))
    return 0

#Wraps check_field_maps but sets the key to be DTI_fm
def check_DTI_field_maps(regex_match, this):
    this.queue_funct(check_field_maps, (regex_match, this, 'DTI_fm'))
    return 0

def check_dicom_files(regex_match, this):
    
    #First get the paramter name so we can store these matches for other later checks.
    parameter = regex_match.string.split()[1]

    #The match groups for the file names are 7 if surrounded by parentheses (will also pull out the qoutes so these 
    #need to be removed) and group 5 if there is only one value.
    file_names = regex_match.group(7).replace('"','') # <- remove the first and last parenthesis 
    
    #There are no files to check.
    if file_names == '' or file_names == None:
        this.match_map[parameter] = []
        return 0
    
    #If there are no file names to match then exit early.
    file_name_list = file_names.split()
    
    #Otherwise add the paramter to the match map with the file list.
    this.match_map[parameter] = file_name_list

    all_allowed, fname = check_file_list_extensions(file_name_list, this)
    if not all_allowed:
        print(f'The file: {fname} has an extension not found in "Allowed_Dicom_Scan_Extensions" definied in Boundaries.json. Please ensure file extensions are correct or add this extension to the allowed extensions list.')
        return 8
        

    #Now attempt to actually check for file existance at these paths.
    #Also check if they are sym links and if so check that the link is also valid.
    #Can check 
    rcode = 0
    path = ''
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

#returns true if all extensions match the allowed extensions in the boundary file.
def check_file_list_extensions(file_name_list, this):
    valid_extensions = this.boundary_data['Allowed_Dicom_Scan_Extensions']
    for fname in file_name_list:
        found_extension = False 
        for extension in valid_extensions:
            ext_len = len(extension)

            if ext_len >= len(fname):
                continue

            #Otherwise cut the end off the file name and compare it to the extension.
            if fname[(ext_len * -1):] == extension:
                found_extension = True
                break

        if not found_extension:
            return (False, fname)

    return (True,'')

def check_target(regex_match, this):
    #First check if the target has an extension.
    fname = regex_match.group(5)
    if '.' in os.path.basename(fname):
        #If it does then we just need to check existance and file extension types.

        r_code = check_existance(regex_match, this) 
        if r_code:
            return r_code

        all_allowed, fname = check_file_list_extensions([fname], this)
        if not all_allowed:
            print(f'The file: {fname} has an extension not found in "Allowed_Dicom_Scan_Extensions" definied in Boundaries.json. Please ensure file extensions are correct or add this extension to the allowed extensions list.')
            return 8
        
        return 0


    #Otherwise we should try to add on possible extensions and see if these files exist. If they 
    #do then we are good otherwise there is an issue.

    found_extension = False
    valid_extensions = this.boundary_data['Allowed_Dicom_Scan_Extensions']

    for extension in valid_extensions:
        try:
            os.stat(f'{fname}.{extension}')
            found_extension = True
            break

        except FileNotFoundError:
            pass
    
    if not found_extension:
        print(f'Could not find any file {fname} using defined allowed dicom extensions. Please ensure a valid target exists.')
        return 8

    return 0

#Checks if a given subject exists in the current project.
def check_existance(regex_match, this):
    #The match groups for the file names are 7 if surrounded by parentheses (will also pull out the qoutes so these 
    #need to be removed) and group 5 if there is only one value.
    sub_ses = regex_match.group(5)

    #Now attempt to actually check for file existance at these paths.
    #Also check if they are sym links and if so check that the link is also valid.
    #Can check 
    rcode = 0

    #If the path is absolute then check it directly otherwise assume that the path belongs to
    #this project folder
    path = sub_ses if os.path.isabs(sub_ses) else os.path.join('..', sub_ses)
    try:
        os.stat(path)

    except FileNotFoundError:
        print(f"Could not find file {path}, file or symlink does not exist.")
        rcode = 8

    #Return the error code.
    return rcode
     
#Checks the value of ASL_TI1. If 0 check to see if the file names in the list look like theyre PASL. If so throw a warning.
def check_asl_time_inversion(regex_match, this):
    this.queue_funct(check_pasl, (regex_match, this))
    return 0

#This is grouped into its own function so it can be wrapped and queued.
def check_pasl(regex_match, this):
    #This is specifically for ASL_TI1 
    #Extract the values.
    values = [ float(f) for f in regex_match.group(5)[1:-1].split() ]
    
    #Now we need to check to see if all the files in the 
    files_to_check = this.match_map['ASL']
    
    pasl_files = []
    for fname, value in zip(files_to_check, values):
        if 'pasl' in fname.lower() and int(value) == 0:
                pasl_files.append(fname)
    
    if pasl_files != []:
        #Now Generate the warning message and process it.
        error_message = 'ASL_TI1 set to 0 (-> pcASL) but the following seemingly PASL scans were set in ASL:\n' 
        for fname in pasl_files:
            error_message += fname + '\n' 

        #Remove the trailing newline
        error_message += '\n%s' % regex_match.string 

        rcode = this.process_warning(error_message, e_level = 2)
        if rcode:
            return rcode
    
    #Otherwise just check the boundaries like normal. 
    #Now make sure its in the specified range.
    regex_match_all = True 
    for value in values:
        minimum = this.boundary_data['numeric']['ASL_TI1']['min']
        maximum = this.boundary_data['numeric']['ASL_TI1']['max']
        if not ((value > minimum and value < maximum) or (math.isclose(value,minimum,abs_tol=1e-10) or math.isclose(value,maximum,abs_tol=1e-10))):
            print('Parameter not in range [%f,%f] specified in boundry file' % (minimum, maximum)) 
            regex_match_all = False
            break

    return 0 if regex_match_all else 10

def check_field_map_type(regex_match, this, fm):
    
    fm_type = regex_match.group(7)
    
    r_code = 0 
    
    if fm_type == 'none':
        r_code = this.process_warning('%s_FieldMapping set to "none", check that this is correct and consider switching to "synth" if no field maps exist.' % fm, e_level = 2)

    return r_code

def check_BOLD_field_map_type(regex_match, this):
    return check_field_map_type(regex_match, this, 'BOLD')

def check_ASL_field_map_type(regex_match, this):
    return check_field_map_type(regex_match, this, 'ASL')

def check_ASE_field_map_type(regex_match, this):
    return check_field_map_type(regex_match, this, 'ASE')

def check_DTI_field_map_type(regex_match, this):
    return check_field_map_type(regex_match, this, 'DTI')

def check_consistent_multiband(regex_match, this):
    r_code = check_dicom_files(regex_match, this)
    if r_code:
        return r_code
    
    #Now check that the dimensionality is consistent.
    r_code = check_nifti_dims('BOLD', this)
    if r_code:
        return r_code

    bold_files = this.match_map['BOLD']
    mb_factors = [] 
    json_fname = ''
    for fname in bold_files:
        #Try to get the multiband acceleration factors.
        
        try:
            #First find the nifti extension and replace it with the json extension.
            json_fname = ''
            for extension in this.boundary_data['Allowed_Dicom_Scan_Extensions']:
                if fname.endswith(extension):
                    #Chop off the extension and the last '.' and add the '.json' extension.
                    json_basename = fname[:-(len(extension) + 1)] + '.json'
                    json_fname = os.path.join('dicom', json_basename)
                    break
            
            if len(json_fname) == 0:
                continue

            try: 
                header_data = json.load(open(json_fname))
            except json.decoder.JSONDecodeError:
                print(f'Could not decode the header data at "{json_fname}"')
                return 8

            #Now extract the multiband acceleration factor
            mba = 1
            try:
                mba = header_data['MultibandAccelerationFactor']
            except:
                pass

            mb_factors.append(mba)

        except FileNotFoundError:
            print('Could not find nifti header file: %s' % json_fname)
            return 8
            
    #Now make sure that all files have the same multiband value.
    all_equal = True
    for i in range(1, len(mb_factors)):
        if mb_factors[i-1] != mb_factors[i]:
            all_equal = False
            break

    if not all_equal:
        
        warning_message = 'Detected Multiband Acceleration Factors do not all match.\n'
        for mbf,fname in zip(mb_factors, bold_files):
            warning_message += '%s: MB Factor %d\n' % (fname, mbf)
        warning_message += '\nCheck that BOLD files are consistent and check slice interleave order.'
        
        r_code = this.process_warning(warning_message, e_level = 1) 
    
    return r_code

#Checks if all the nifti files in dicoms saved at a given location have the same dimensions.
#Takes only a scan_key (key for the match map entry) and returns 0 on success and 8 on failure. 
#The match_map entry for this scan key must exist before calling this function.
def check_nifti_dims(scan_key, this):
    
    files = this.match_map[scan_key]
    
    rcode = 0 
    fdims = []
    for f in files:
        path = os.path.join('dicom',f)

        # Run the command, capture stdout and stderr
        result = subprocess.run('fslsize \"%s\" -s' % path, 
                                            shell=True, 
                                stdout=subprocess.PIPE, 
                                stderr=subprocess.PIPE, 
                                universal_newlines=True)

        # Check the return code
        rcode = result.returncode

        # Capture the stdout and stderr
        stdout_result = result.stdout
        stderr_result = result.stderr
        
        #Check if fslsize is installed properly.
        if rcode and ('command not found' in stderr_result):
            error_msg = 'Cannot execute command: fslsize. Check that this is installed and in the system path. Skipping file dimensionality checks.'
            return this.process_warning(error_msg, e_level = 1) 

        if 'Image Exception' in stderr_result:
            print('fslsize was unable to open the file: %s. Ensure that the file exists.' % path)
            return 8

        if stderr_result != '':
            print('An error occured executing fslsize.\n%s' % stderr_result)
            return 8

        #Otherwise we presume the command executed properly and got the file dims.
        
        #Remove all whitespace from the string
        parsed_string = ''.join(stdout_result.split())

        #Just get the dimensions part.
        parsed_string = parsed_string.split(':')[0].replace('Size=','')

        #now seperate out.
        parsed_string = parsed_string.split('x')

        fdims.append((int(parsed_string[0]),
                      int(parsed_string[1]),
                      int(parsed_string[2])))

    fdiml = len(fdims)
    if fdiml <= 1:
        return 0

    #Test that all the fdims are the same.
    for i in range(1,fdiml):
        if fdims[i] != fdims[i-1]:
            print(f'\nError, not all file dimensions match.\nFile: {files[i]} {fdims[i]}\nFile: {files[i-1]} {fdims[i-1]}\n')
            return 8

    return 0

#This simply wraps the usual check dicom files but also includes the dimensionality check for all pet modalities.
def check_fdg_dicom_files(regex_match, this):
    rcode = check_dicom_files(regex_match, this)

    if rcode:
        return rcode

    #Now do the check for dimensionality.
    return check_nifti_dims('FDG',this)

def check_o2_dicom_files(regex_match, this):
    rcode = check_dicom_files(regex_match, this)

    if rcode:
        return rcode

    #Now do the check for dimensionality.
    return check_nifti_dims('O2',this)

def check_co_dicom_files(regex_match, this):
    rcode = check_dicom_files(regex_match, this)

    if rcode:
        return rcode

    #Now do the check for dimensionality.
    return check_nifti_dims('CO',this)

def check_h2o_dicom_files(regex_match, this):
    rcode = check_dicom_files(regex_match, this)

    if rcode:
        return rcode

    #Now do the check for dimensionality.
    return check_nifti_dims('H2O',this)

def check_pib_dicom_files(regex_match, this):
    rcode = check_dicom_files(regex_match, this)

    if rcode:
        return rcode

    #Now do the check for dimensionality.
    return check_nifti_dims('PIB',this)

def check_tau_dicom_files(regex_match, this):
    rcode = check_dicom_files(regex_match, this)

    if rcode:
        return rcode

    #Now do the check for dimensionality.
    return check_nifti_dims('TAU',this)

def check_fbx_dicom_files(regex_match, this):
    rcode = check_dicom_files(regex_match, this)

    if rcode:
        return rcode

    #Now do the check for dimensionality.
    return check_nifti_dims('FBX',this)
