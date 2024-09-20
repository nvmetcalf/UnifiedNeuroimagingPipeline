# Syntax Checker Rules

The following is a brief overview of how to write rules for syntax checking in the pipeline. 
Whenever a new parameter is added to GenerateParams a new rule must be added to `$PP_SCRIPTS/Utilities/TemplateParams.json`
in order for syntax checking to accept this new parameter.

## Overview of file structure.
There are three main groups in `TemplateParams.json`

1. `patterns`: contains regular expressions to match common patterns in the parameter file.
2. `required_rules`: contains expressions which must be pressent in a file.
3. `valid_rules`: contains all the valid expressions that may or may not be found in a parameter file.

### patterns
Patterns are regular expressions contained in an isolated group which are associated with a tag for easy substitution into other regular expressions. 
Using this method, more complicated regular expressions can be built from previously defined patterns.

The following table contains all the patterns, their associated meanings, its definition, and an example string which the pattern will match. 
Additionally, some patterns contain patterns which have previously been defined. This is done by replacing any tag a pattern surrounded by `${}` with the previously defined pattern.

| Pattern | Meaning | Definition | Example Match(s) |
|---------|---------|------------|------------------|
| `ws` | Whitespace | Spaces and tabs, additionally whitespace may not exist and will still match | _'         \t   ', ''_ |
| `fnnq` | File name no quotes | Matches valid file names containing alpha-numeric characters and special characters: ":.(){}[]-$*" | _'1234_MR1_pcasl_3D_tgse_4p8mm_PLD1_1234_9.nii.gz'_ |
| `dec` | Decimal number | Any decimal number | _'-123.003', '.231'_ |
| `n` | A natural number | Any natural number | _'123'_ |
| `n0` | A natural number including 0 | Any natural number including 0 | _'123', '0'_ |
| `dir` | Direction | Matches any valid phase encoding direction | _'-x', 'y', '-z'_ |
| `optsnq` | Options no quotes | Field mapping methods | _'gre', 'appa_6dof'_ | 
| `tarnq` | Targets no quotes | Valid registration targets | _'T1', 'T2', 'FLAIR'_ |
| `rcfunnq` | Registration cost function no quotes | Valid options for registration cost functions | _'mutualinfo', 'corratio', 'leastsq'_ |
| `rng` | Range | A range of `dec` | _'200-400'_ |
| `opts` | Options | `optsnq` with or without qoutes | _'appa', '"synth"', '"none"'_ |
| `tar` | Targets | `tar` with or without quotes | _'T1', '"T1"'_ |
| `rcfun` | Registration cost funtion | `rcfunnq` with or without quotes | _'normcorr', '"normmi"'_ |
| `fn` | File name | `fn` with or without quotes | _'"1234_MR1_pcasl_3D_tgse_4p8mm_PLD1_1234_9.nii.gz"'_ |
| `cm` | Comment | A comment starting with _#_ and any text following | _'#Anything goes now'_ |
| `fnlnp` | File name list no parentheses | A `ws` separated list of `fn` without any parentheses | _'fileone.a  \t  filetwo.b file/path/two'_ |
| `declnp` | Decimal list no parentheses | A `ws` separated list of `dec` without any parentheses | _'123 -4  \t  2'_ |
| `n0lnp` | Natural number list including 0 no parentheses | A `ws` separated list of `n0` without any parentheses | _'0 1 2 3 4'_ |
| `dirlnp` | Direction list no parentheses | A  `ws` separated list of `dir` without any parentheses | _'x y -z z x y'_ |
| `rnglnp` | Range list no parentheses | A `ws` separated list of ranges without any parentheses | _'60-40   \t   -20-40.2'_ |
| `fnl` | File name list | A `ws` separated list of `fn` with or without parentheses | _'fileone.a  \t  filetwo.b file/path/two', '(foo.txt "test.csh")'_ |
| `decl` | Decimal number list | A `ws` separated list of `dec` with or without parentheses |  _'-4.1 0 2', '(0 -1.1 2)'_ |
| `n0l` | Natural number list including 0 | A `ws` separated list of `n0` with or without any parentheses | _'4 2 1 0', '(1 2 3 4)'_ |
| `dirl` | Direction list | A  `ws` separated list of `dir` with or without any parentheses | _'x y z', '(-x -y -z)'_ |
| `rngl` | Range list | A `ws` separated list of `rng` with or without any parentheses | _'40-50','(0-4 100-200)'_ |
| `n0lcs` | Comma separated list of natural numbers including 0 | A comma separated list of `n0` with or without any parentheses | _'4,2,1,0', '(1,2,3,4)'_ |
| `declcs` | Comma separated list of decimal numbers | A comma separated list of `dec` with or without any parentheses | _'4.4,-2,1,0', '(-1,2.2,3,4.0)'_ |
| `sscsdeclnp` | Space separated comma separated decimal number list no parenthesis | A space seperated list of comma seperated `dec` lists | _'1,2,3 -4,5.5,6'_ |
| `sscsdecl` | Space separated comma separated decimal number list with or without parenthesis | A space seperated list of comma seperated `dec` lists that may or may not be surrounded by parenthesis| _'1,2,3 -4,5.5,6', '('1,2,3 -4,5.5,6')'_ |

## Rules
Rules are what the syntax checker will attempt to match lines of the provided parameter file to. The structure or a rule in the `TemplateParams.json` file is:
`<regex patten to match>:<additional execution tag>` (see __Additional Modules__ for more info on these tags).

There are two sections which contain the rules for everything you could find in a parameter file.

1. `required_rules`: contains rules which must exist in a parameter file. If the rules here are not matched then the parameter file is invalid and an error will be thrown.
2. `valid_rules`: contains all possible valid rules for a parameter file. If the a given line in a parameter file does not match any expression here then a syntax error will be thrown. 

### required_rules

Rules which must be matched for a parameter file to be valid. 

### valid_rules

All subcategories within `valid_rules` are arbitrary and just there for human readability, they will be combined into one list in to be searched
internally.

The syntax of a valid rule follows normal regular expression syntax with the caveat that first any regex tags surrounded by `${}` found in
`patterns` will first be replaced with the associated regex.

#### Example rules
| Rule | Meaning | Example Match |
|------|---------|---------------|
| `${ws}set${ws}mprs${ws}=${ws}${fnl}?${ws}${cm}?:"check_files"` | set mprs = "file name list (may or maynot exist)" "comment", separated by any amount of whitespace (may or may not exist). Run file and symlink existance checks on the files provided in this parameter | 'set mprs = (1A_MR1_t1_mpr_1mm_p2_pos50_8.nii.gz  2A_MR1_T1_MPRAGE_sag_p2_iso_1_176_20210625095352_7.nii.gz)' |
| `${ws}set${ws}H2O_Target${ws}=${ws}\\(${ws}(${tar}${ws}FDG)${ws}\\)${ws}${cm}?:"none"` | set H2O_Target = ( "target" FDG ) "comment", seperated by any amount of whitespace (may or may not exist) | 'set H2O_Target = (T1 FDG)   #H2O registration path.' |

## Additional Modules
The associated execution tag is a function which is exectued found in `$PP_SCRIPTS/python3/AdditionalModules.py`. 

The functions must adhere to the following properties:

1. The tag name and function name must be the same.
2. The function definition must be of the form `def function_name(match, this):` where the first parameter is always the regex match object generated when the match was found. The second parameter is the `ParseParams` instance. See `CheckParamsSyntax.py` for more info.
3. The function will return a exit status, 0 on status and any other number on failure.

The following are the existing additional modules and their functions.
| Module Tag | Function | Return Code |
|------------|----------|------------------|
| "none" | Nothing will be executed | N/A (Automatic success) |
| "check_files" | Extracts either a single file or a list of files from a file list parameter then checks to see if they exist in the session dicom folder. | 0 on success, 8 on failure |
| "check_boundaries" | Checks to see if the given parameter is within the range inclusive range specified in `$PP_SCRIPTS/python3/Boundaries.json`. | 0 on success, 10 on failure |