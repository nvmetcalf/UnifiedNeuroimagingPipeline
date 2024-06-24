#!/bin/bash

# Authenticates credentials against XNAT and returns the cookie jar file name. USERNAME and
# PASSWORD must be set before calling this function.

dos2unix $1

output_dir="./downloads"

USERNAME="canfieldp"
read -s -p "Enter your password for username ${USERNAME} accessing data on https://cnda.wustl.edu:" PASSWORD

function startSession {
    # Authentication to XNAT and store cookies in cookie jar file
    local COOKIE_JAR=.cookies-$(date +%Y%M%d%s).txt
    curl -k -s -u ${USERNAME}:${PASSWORD} --cookie-jar ${COOKIE_JAR} "https://cnda.wustl.edu/data/JSESSION" > /dev/null
    echo ${COOKIE_JAR}
}
	
while IFS="," read -r mr_sess sess_id cnda_id scanner fs_version fs_id; do
	#download
    echo "Beginning download for ${sess_id} MR data"

    #COOKIE_FILE=$( startSession )
    #URL='https://cnda.wustl.edu/data/experiments/'$cnda_id'/scans/ALL/files?format=zip' 
    #curl $URL --cookie $COOKIE_FILE -o "${output_dir}/${sess_id}.zip"
    
    COOKIE_FILE=$( startSession )
    URL="https://cnda.wustl.edu/data/experiments/{$cnda_id}/assessors/${fs_id}/files?format=zip" 
    curl $URL --cookie $COOKIE_FILE -o "${output_dir}/${sess_id}.zip"

    #Remove all the cookie files
    rm .cookies*.txt

done < "$1"
