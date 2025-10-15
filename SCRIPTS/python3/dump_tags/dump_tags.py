import os
import glob
import argparse
import sys
import pydicom
import json

CAST_TABLE = {
    pydicom.Dataset : str
}

ACQUISITION_NUMBER = (0x0020, 0x0012)

#Convert the given value to a json serializable type. Filter out pydicom types.
def cast_header_value(value):
    if type(value) in CAST_TABLE:
        return CAST_TABLE[type(value)](value)
    return value 
    

def extract_dicom_tags(dcm_paths: list) -> dict:
    found_tags = {}
    for dcm_path in dcm_paths:
            
        try:
            dcm_header = pydicom.dcmread(dcm_path, stop_before_pixels=True)
            acquisition = int(dcm_header[ACQUISITION_NUMBER].value)
        except: 
            continue
        
        
        found_tags[acquisition] = {}
        acq = found_tags[acquisition]

        for data_element in dcm_header.iterall():
            name = str(data_element.name) 
            value = None

            if isinstance(data_element.value, pydicom.multival.MultiValue):
                value = data_element.to_json_dict(None, 1024)
            else:
                value = str(data_element.value)
            
            #Add the value to the acq dict.
            acq[name] = value

    
    #Now sort the found_tags dictionary by aqcuisision number.
    found_tags = dict(sorted(found_tags.items()))

    #Now condense down the lists by refererence numbers.
    condensed = {}

    #Figure out all the keys in all acquisitions.
    all_keys = set()
    for acquisition in found_tags:
        all_keys |= set(found_tags[acquisition].keys())

    #Now go through all the keys and see if they are in all the tag matches for each aqcuisision
    for key in all_keys:
        all_match = True
        
        acq = []
        last_value = None
        

        for number, tags in found_tags.items():
            if not key in tags:
                all_match = False
                continue

            value = tags[key]
            acq.append(value)

            if last_value != None and last_value != value:
                all_match = False

            last_value = value
        
        #Now we have determined if this key matches accross all sequences, add it to the final list if so.
        condensed_key = ''.join(key.split())
        if all_match:
            condensed[condensed_key] = acq[0]
        else:
            condensed[condensed_key] = acq

    return condensed 

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Process DICOM files and generate dcm2nii format JSON.")
    parser.add_argument(
        "dicom_dir",
        help = "Path to the DICOM folder for the associated nifti/json file.",
        type = str
    )

    parser.add_argument(
        "json_path",
        help = "Path to the generated dcm2nii JSON file.",
        type = str
    )

    parser.add_argument(
        "-o", 
        "--overwrite", 
        help = "Overwrite the original json files.",
        action = 'store_true',
        default = False
    )
    
    parser.add_argument(
        "--suffix", 
        help = "Suffix to add to the json file name (default: _dumped).",
        type = str,
        default = 'dumped'
    )
    
    parser.add_argument(
        "--skip_keys", 
        help = "A list of metadata keys to skip in json header inclusion.",
        type = str,
        nargs = '+',
        default = []
    )

    args = parser.parse_args()
    skip_keys = args.skip_keys
    
    with open(args.json_path, 'r') as read_file:
        json_data = json.load(read_file)
        
        output_path = args.json_path
        if not args.overwrite:
            output_path = f'{args.json_path[:-5]}_{args.suffix}.json'
    
    dcm_files = []
    for file_name in os.listdir(args.dicom_dir):
        path = os.path.join(args.dicom_dir, file_name)
        if os.path.islink(path) or os.path.isfile(path):
            dcm_files.append(path)

    if len(dcm_files) == 0:
        print('Could not find any dicom files at the provided directories.', file=sys.stderr)
        exit(1)
    
    extracted_tags = extract_dicom_tags(dcm_files) 

    for key in skip_keys:
        if key in extracted_tags:
            del extracted_tags[key]

    json_data.update(extracted_tags)

    with open(output_path, 'w') as write_file:
        json.dump(json_data, write_file, indent='\t')
