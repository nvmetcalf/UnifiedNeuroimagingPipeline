import sys
from CheckParamsSyntax import *


if __name__ == '__main__':
    exit_code = 0
    
    #Check file arguments, should only be one which is the file to check.
    if (len(sys.argv) != 4):
        print("Incorrect arguments passed to CheckParamsSyntax, exiting...")
        exit_code = 5
    else:
        parser = ParseParams(rules_path='/data/nil-bluearc/ances/PeteCanfield/ParseParams/TemplateParams.json', 
                             boundary_path='/data/nil-bluearc/ances/PeteCanfield/ParseParams/Boundaries.json', verbosity=int(sys.argv[2]), strictness=int(sys.argv[3]))

        parser.loadFile(sys.argv[1])
        parser.checkSyntax()
        exit_code = parser.status()

    sys.exit(exit_code)
