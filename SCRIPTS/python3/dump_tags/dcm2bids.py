import pydicom
import argparse
import os
import glob
import sys
import json
import subprocess
import shutil

UID_TAG         = (0x0020, 0x000E)

UNSORTED     = "unsorted"
BIDS_DEFUALT = "remaining_dicom"
TEMP_LINK    = "links"
BIDS_GUESS   = 'BidsGuess'

def find_dcm_locations(root_dicom_locations: list, depth: int = None) -> list:
    """
    Recursively finds all .dcm files under each path in root_dicom_locations.

    Parameters:
    - root_dicom_locations: List of root directories to search.
    - depth: the maximum depth to descend to when searching. None -> no max depth.

    Returns:
    - List of absolute paths to dcm files.
    """
    tagged_dcm_files = []
    untagged_dcm_files = []
    for root in root_dicom_locations:
        root = os.path.abspath(root)
        root_depth = root.count(os.sep)

        for dirpath, dirnames, filenames in os.walk(root):
            current_depth = dirpath.count(os.sep) - root_depth

            if depth is not None and current_depth >= depth:
                # Prevent os.walk from descending further
                dirnames[:] = []

            for filename in filenames:
                abs_path = os.path.abspath(os.path.join(dirpath, filename))
                
                #Check if this is actually a dicom file.
                try:
                    dcm_header = pydicom.dcmread(abs_path, stop_before_pixels=True)
                except pydicom.errors.InvalidDicomError:
                    continue

                try:
                    tagged_dcm_files.append(
                        (
                            abs_path, 
                            dcm_header[UID_TAG].value,
                        )
                    )
                except KeyError:
                    untagged_dcm_files.append(abs_path)
    
    #Print results of the dicoms found.
    tagged_dicom_file_len   = len(tagged_dcm_files)
    untagged_dicom_file_len = len(untagged_dcm_files)
    print(f'Found {tagged_dicom_file_len + untagged_dicom_file_len} dicom files.')
    print(f'Found {tagged_dicom_file_len} dicoms with required tag: {UID_TAG}.')
    print(f'Found {untagged_dicom_file_len} dicoms without required tags.')
    return (tagged_dcm_files, untagged_dcm_files)

def invert_bids_settings(bids_settings: dict) -> dict:
    inverted = {}
    for key, list_val in bids_settings.items():
        for val in list_val:
            inverted[val] = key

    return inverted

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description = "Process DICOM files and sort into a BIDS format based on the bids_spec.json file. Requires dcm2niix to be in the system PATH."
    )

    parser.add_argument(
        "dicom_dirs",
        help = "Path(s) to the DICOM folders to recusively search.",
        type = str,
        nargs = '+'
    )
    
    parser.add_argument(
        "output",
        help = "The path to create the bids structure in.",
        type = str
    )
    
    parser.add_argument(
        "-d", 
        "--depth", 
        help = "The maximum depth to search to in each source folder.",
        type = int,
        default = None
    )
    args = parser.parse_args()

    tagged_dcm_files, untagged_dcm_files = find_dcm_locations(args.dicom_dirs, args.depth)
    if len(tagged_dcm_files) == 0 and len(untagged_dcm_files) == 0:
        print('Could not find any dicom files at the provided directories.', file=sys.stderr)
        exit(1)
    
    #Initalize a BIDs dict to sort everything into.
    bids = {}
    for path, series_uid in tagged_dcm_files:
        if not series_uid in bids:
            bids[series_uid] = [path]
        else:
            bids[series_uid].append(path)

    #Now go through and create the conversion folder.
    os.makedirs(args.output, exist_ok = True)
    
    #Dump all the series folders into a temp folder. 
    bids_default_folder = os.path.join(args.output, BIDS_DEFUALT)
    os.makedirs(bids_default_folder, exist_ok = True)

    #Create the temp folder to link files into 
    series_index = 1
    for series, paths in bids.items():
        print(f'\rLinking and converting DICOM series {series_index}/{len(bids)} ...', end = '', flush = True)
        output_path = os.path.join(args.output, BIDS_DEFUALT, series)
        temp_links  = os.path.join(output_path, TEMP_LINK)
        os.makedirs(temp_links, exist_ok = True)
        for dcm_path in paths:

            dest_path = os.path.join(temp_links, os.path.basename(dcm_path))
            if os.path.islink(dest_path):
                continue

            os.symlink(dcm_path, dest_path, target_is_directory = True)
        
        #Convert linked files to nifti/json
        out = None
        try:
            out = subprocess.run(
                ['dcm2niix', '-z', 'y', '-o', output_path, '-f', '%p_%t_%s', temp_links], 
                check = True,
                text = True,
                capture_output = True
            )
        except subprocess.CalledProcessError:
            print() #print a newline.
            print(f'Could not convert DICOM series {series}')

            if(out):
                print(out.stdout)
                print(out.stderr)

        series_index += 1

    print() #print a newline.
    
    #Now that we have sorted everything, lets look at the files that couldnt be sorted directly into BIDs categories
    #by the 'best guess' category generated by dcm2niix.
    print('Moving undetermined DICOM series to BIDs based on best guess.')
    for path_folder in bids:
        series_path = os.path.join(args.output, BIDS_DEFUALT, path_folder)

        if not os.path.isdir(series_path):
            continue

        #Try to open each json file and extract the best guess value.
        bids_guess = None
        for fname in os.listdir(series_path):
            if not fname.endswith('.json'):
                continue
            
            #Now we have found json file, open it and get the best guess array.
            try:
                with open(os.path.join(series_path, fname), 'r') as json_file:
                    bids_guess = json.load(json_file)[BIDS_GUESS][0]
                break
            except:
                pass #Something went wrong, we cant find the best guess.
        
        #If we were able to find a best guess then move this series.
        if bids_guess:
            destination = os.path.join(args.output, bids_guess, path_folder)

            try:
                shutil.move(series_path, destination)
            except:
                print(f'Could not move {series_path} to {destination}')
                        
    #Now finally if there are any dicom files that were unable to sorted then bin them all together.
    if len(untagged_dcm_files) != 0:
        print('Converting remaining unsorted DICOMs ...')
        default_dir = os.path.join(args.output, UNSORTED)
        link_path   = os.path.join(default_dir, TEMP_LINK)
        os.makedirs(link_path, exist_ok = True)

        #Link in the dicom files.
        for dcm_path in untagged_dcm_files:
            os.symlink(dcm_path, os.path.join(link_path, os.path.basename(dcm_path)), target_is_directory = True)

        #Run the conversion.
        subprocess.run(
            ['dcm2niix', '-z', 'y', '-o', default_dir, '-f', '%p_%t_%s', link_path], 
            check = True,
            stdout=subprocess.DEVNULL
        )
