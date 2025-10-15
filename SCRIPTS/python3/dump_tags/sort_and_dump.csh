#! /bin/csh

if($#argv != 2) then
    decho "Expects 2 arguments"
    decho "1. Path to the source DICOM folder."
    decho "2. Path generate BIDs structure in."
    exit 1
endif

#Default name for the link folder which tells us where all the 
set dicom_path = `readlink -f ${1}`
set bids_path = `readlink -f ${2}`

decho "Sorting DICOMs and creating BIDs directory." 
$FSL_BIN/python3 $PP_SCRIPTS/python3/dump_tags/dcm2bids.py $dicom_path $bids_path
if($status) then
    decho "There was an error creating BIDs structure."
    exit 1
endif
    
#Try to remove all the ()[] chars from any generated file names. This will become a problem later. 
set noglob
    set file_list = `find "${bids_path}" -type f`
    foreach file ($file_list)
        set stripped  = `echo "$file" | sed 's/\[//g' | sed 's/\]//g' | sed 's/(//g' | sed 's/)//g'`
        if("$stripped" != "$file") then
            mv "${file}" "${stripped}"
        endif
    end
unset noglob

#Removing specific junk.
find $bids_path -name "*_i?????.*" -exec rm -f {} \;

#Now we have generated all the nifti json pairs. Find all the nifti/json pairs and search the associated 'links' directory.
#All the sed stuff is to get around how cshell handles paranthesis in filenames. 
#Super hacky but works...
decho "Dumping extra DICOM header info to json files."
set json_list = `find "${bids_path}" -type f -name '*.json'`
foreach json_file ($json_list:q)
    set link_folder = "`dirname -- "$json_file"`/links"
    if ( -d "$link_folder" ) then
        $FSL_BIN/python3 $PP_SCRIPTS/python3/dump_tags/dump_tags.py "$link_folder" "$json_file" \
            --skip_keys "ReferencedImageSequence" "SourceImageSequence" "[CSAImageHeaderInfo]"  \
                        "[CSASeriesHeaderInfo]" "DecayFactor" "FrameReferenceTime"\
            -o
        if ( $status ) then
            decho "Could not dump tags for ${json_file}."
        endif
    endif
end
decho "Cleaning up."

#Okay now its time for cleanup. 
#   1. remove all the link folders (CAREFUL not to delete dcms by following links)
#   2. move all nifti/jsons one level up out of their series folders
#   3. delete all series folders

#Now move all nifti/json up a one level and then remove the parent folders.
cd $bids_path
foreach type (*)
    cd $type
        set series = `find . -maxdepth 1 -mindepth 1 -type d` 

        #move all nifti/jsons out
        foreach series ($series:q)
            find $series -maxdepth 1 -type f -name '*.json' -exec mv {} . \;
            find $series -maxdepth 1 -type f -name '*.nii.gz' -exec mv {} . \;
            rm -r -f $series
        end
    cd ..
end
