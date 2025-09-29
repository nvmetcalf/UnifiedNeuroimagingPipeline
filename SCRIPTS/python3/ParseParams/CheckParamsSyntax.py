## ---------------------------------------------------------------------------------------------------------
#
# Checks a parameter file for syntax and other errors.
# Additionally, parameter files must be sourced before calling this script
# to ensure proper variable expansion.
#
# Current functions:
# 1) Checks csh syntax
# 2) Checks parameter file has required lines
# 3) Checks parameter file has valid rules
# 4) Checks that parameters are within allowed bounds (Defined in ./Boundries.json)
# 5) Performs file existance checks for all file parameters.
# 6) Checks specific parameters that are commonly not set correctly.
# 
# Additional documentation found: ./SyntaxCheckerRulesREADME.md
#
# Written by Pete Canfield: Aug-2024
#
# Last updated: 2/28/2024
#
## ---------------------------------------------------------------------------------------------------------

import subprocess
import os
import sys
import re
import json
import AdditionalModules 

#Currently 2 verbosity levels, 0 and 1. If verbosity is set to 0 then do not show any warnings
#and if verbosity is 1 then show level 1 warnings.
#The strictness is the the level at which the syntax checker will fail. For instance if the 
#strictness is level 0 then any error that is level 1 or higher will not cause the syntax
#Checker to exit with a non-zero exit code. If the level is 1 then any level 1 or 0 error
#will cause the syntax checker to exit with an error code.
class ParseParams():
    def __init__(self, rules_path    = os.path.join(os.path.expandvars('$PP_SCRIPTS'), 'python3', 'ParseParams', 'TemplateParams.json'),
                       boundary_path = os.path.join(os.path.expandvars('$PP_SCRIPTS'), 'python3', 'ParseParams', 'Boundaries.json'),
                       verbosity     = 2,
                       strictness    = 0):
        
        #set the return code, match_map, strictness, and the verbosity level.
        self._ecode = 0
        self._verbosity = verbosity
        self._strictness = strictness
        
        #Paramters that need to be stored for additional checks and their associated values 
        #are stored here.
        #Additionally the function pointers and parameters for functions that need to be executed later are
        #stored. These are functions which depend on data being in match_map
        self.match_map = {}
        self._to_check = [] #Will be a list of tuples of the form (<funct pointer>, <(params)>)
                            #where (params) is a tuple of parameters

        #Load in the boundary data.
        self.boundary_data = None
        try:
            f = open(boundary_path, 'r')
            self.boundary_data = json.load(f)
            f.close()
        except:
            print('No parameter boundary file found at: %s' % boundary_path)
            self._ecode = 9
            return


        #Load in parser expressions.
        params_data = None
        try:
            f = open(rules_path, 'r')
            params_data = json.load(f) 
            f.close()
        except FileNotFoundError:
            print('No parameter syntax file found at: %s' % rules_path)
            self._ecode = 1 
            return

        #Attempt to expand all the regular expressions
        #First start with the patterns themselves
        tokens = []
        for tok in params_data['patterns']:
            #Check to see if the current expression needs to be expanded with previous
            #expressions
            for previous in tokens:
                to_match = '${%s}' % previous
                params_data['patterns'][tok] = params_data['patterns'][tok].replace(to_match, params_data['patterns'][previous])

            tokens.append(tok)

        #Now do the match pattern. The point of this is so that we can populate the match map with all variables in the file.
        self._match_pattern = params_data['match_pattern']
        for pattern in params_data['patterns']:
            self._match_pattern = self._match_pattern.replace('${%s}' % pattern, params_data['patterns'][pattern])

        self._match_pattern = re.compile('^%s$' % self._match_pattern)


        #Collect all the rules into one rule dictionary.
        #The keys represent the regex to match and the values represent
        #a dynamically loaded function to run if this rule is matched.Test
        self._required_regex = {}
        for rule in params_data['required_rules']:
            
            #Expand out the rule
            expanded = rule 
            for pattern in params_data['patterns']:
                expanded = expanded.replace('${%s}' % pattern, params_data['patterns'][pattern])
            
        
            #Now that the rule has been expanded, Lets find the associated function call for that rule.
            #The default function call is None in the "none" case.
            #Now load in the appropriate function call and store it with the regex.
            mpath = params_data['required_rules'][rule]
            self._required_regex[re.compile('^%s$' % expanded)] = getattr(AdditionalModules, mpath) if mpath != 'none' else None
        
        
        #Collect all the rules into one rule dictionary.
        #The keys represent the regex to match and the values represent
        #a dynamically loaded function to run if this rule is matched.
        self._regex = {}
        for category in params_data['valid_rules']:
            #Duplicate the ket to the value position for later modification. 
            for rule in params_data['valid_rules'][category]:
                
                #Expand out the rule
                expanded = rule 
                for pattern in params_data['patterns']:
                    expanded = expanded.replace('${%s}' % pattern, params_data['patterns'][pattern])
                
            
                #Now that the rule has been expanded, Lets find the associated function call for that rule.
                #The default function call is None in the "none" case.
                #Now load in the appropriate function call and store it with the regex.
                mpath = params_data['valid_rules'][category][rule]
                self._regex[re.compile('^%s$' % expanded)] = getattr(AdditionalModules, mpath) if mpath != 'none' else None

    def __check_csh_syntax(self,file_path):
        #Check to see if the file exists first. 
        if not os.path.isfile(file_path):
            return 3

        correct_syntax = 0 
        try:
            # Use subprocess to run csh with the '-n' flag to check syntax
            subprocess.run(['csh', '-n', file_path], check=True)

        except subprocess.CalledProcessError as e:
            print(f"Syntax error in {file_path}: {e}")
            correct_syntax = 2

        return correct_syntax

    def __build_match_map(self):
        #Go through each line and parse out the lines which set variables. These variables might not be parsed 
        #but they will at least have the variable name and its contents. This can be replaced later if more specific
        #parsing is needed.
        for line in self._file_data:
            match = self._match_pattern.match(line) 
            if match:
                self.match_map[match.group(3)] = match.group(6)
    
    def process_warning(self, message, e_level):
        
        r_code = 0
        if self._verbosity >= e_level:
            print('\nWarning (level %d): %s\n' % (e_level, message))

        if self._strictness >= e_level:
            self._ecode = 11
            r_code = 11
        
        return r_code

    
    def status(self):
        return self._ecode

    #Check the folder structure for required folders. Use definitions in Boundaries.json for folder structure.
    def check_folder_structure(self, session_path):
        if self._ecode:
            return
        
        required    = self.boundary_data['Folder_Structure']['Required']
        recommended = self.boundary_data['Folder_Structure']['Recommended']
        warning = 0

        for dir in required:
            if not os.path.isdir(os.path.join(session_path, dir)):
                print(f'Error could not find the required folder "{dir}" in the current session.')
                warning = 3
                break

        if warning != 0:
            self._ecode = warning
            return 
        
        for dir in recommended:
            if not os.path.isdir(os.path.join(session_path, dir)):
                warning = self.process_warning(f'The folder "{dir}" does not exist in the current session.', 2)
                if warning != 0:
                    break

        self._ecode = warning

    #Loads in a params_path file. 
    def loadFile(self, params_path):
        #Check the the error code to see if anything has gone wrong.
        if self._ecode:
            return
        
        #Check to see if the parameter file at least follows csh syntax.
        self._ecode = self.__check_csh_syntax(params_path) 
        if self._ecode:
            return
        
        #Now load in in the file to check.
        try:
            f = open(params_path,'r')
            self._file_data = f.read().splitlines()
            self._params_path = params_path
            f.close()
        except FileNotFoundError:
            self.ecode = 3 
            return

        #Lets add the cwd and cwd:h variables into the match map.
        self.match_map['cwd:h'] = os.path.dirname(os.getcwd())
        self.match_map['cwd'] = os.getcwd()
        #Now try to build the match_map.
        self.__build_match_map()

        #Now lets go back through and expand out each line.
        #Replace found shell variables (cwd and cwd:h). Can be denoted by $var or ${var}.
        for index, line in enumerate(self._file_data):
            for to_expand in self.match_map:
                line = line.replace(f'${{to_expand}}', self.match_map[to_expand])
                line = line.replace(f'${to_expand}', self.match_map[to_expand])

            self._file_data[index] = line

    def checkSyntax(self):
        #Check if anything has gone wrong again.
        if self._ecode:
            return
        
        #Check if the required rules are in the parameter file. For each one
        #that exists add it to a list of data to not check. If a paramter
        #isnt found then exit with an error.

        #Switch the execution path to the path where the parameter file is located. This is to ensure
        #proper variable expansion.
                 

        to_skip= []
        for pattern in self._required_regex:
            is_match = False
            index = 0
            line = ''
            for index,line in enumerate(self._file_data):
                match = pattern.match(line)
                if match:
                    rcode = 0
                    
                    if self._required_regex[pattern] != None:
                        rcode = self._required_regex[pattern](match,self)
                    
                    is_match = not rcode 
                    to_skip.append(index)
                    break
            if not is_match:
                if len(to_skip) != 0 and to_skip[-1] == index:
                    print("Syntax error in parameter file: %s at line %d" % (self._params_path,index + 1))
                    print('\n%s\n' % line)
                else:
                    print("Required parameter matching regex: \"%s\" not found." % pattern.pattern)
                
                self._ecode = 7
                return 

        #Now check all the remaining data. 
        for index,line in enumerate(self._file_data):
            #Check if we have already checked this line.
            if index in to_skip:
                continue
            
            is_match = False
            #Check all the regex to see if there is a match.
            for pattern in self._regex:
                match = pattern.match(line) 
                if match:
                    rcode = 0
                    #Execute the associated function call.
                    if self._regex[pattern] != None:
                        rcode = self._regex[pattern](match,self)
                    
                    #rcode should return 0 on succes and any other number is a failure.
                    is_match = not rcode 
                    break 

            if not is_match:
                print("Syntax error in parameter file: %s at line %d" % (self._params_path,index + 1))
                print('\n%s\n' % line)
                self._ecode = 4
                return
        
        #Now execute all the stored function calls which deepend on match_map information.
        for funct, params in self._to_check:
            if funct(*params):
                self._ecode = 4
                return

        
    
    def queue_funct(self, function, params):
        self._to_check.append((function, params))

#Here is a list of sys.exit codes and their assigned meanings.
#   0 -> Exit successfully, no errors.
#   1 -> regex syntax file not detected.
#   2 -> csh syntax error detected.
#   3 -> params file not found.
#   4 -> params file error detected.
#   5 -> file arguments not supplied correctly.
#   6 -> unable to load rule module.
#   7 -> Required parameter not found.
#   8 -> File path or symlink does not exist.
#   9 -> Boundry specification json does not exist.
#  10 -> Parameter not in bounds.
#  11 -> Warning generated.

if __name__ == '__main__':
    exit_code = 0
    
    #Check file arguments, should only be one which is the file to check.
    if (len(sys.argv) != 4):
        print("Incorrect arguments passed to CheckParamsSyntax, exiting...")
        exit_code = 5
    else:
        params_file = sys.argv[1]
        session_dir = os.path.dirname(os.path.realpath(params_file))
        
        parser = ParseParams(verbosity=int(sys.argv[2]), strictness=int(sys.argv[3]))
        parser.check_folder_structure(session_dir)
        parser.loadFile(params_file)
        parser.checkSyntax()
        exit_code = parser.status()

    sys.exit(exit_code)
