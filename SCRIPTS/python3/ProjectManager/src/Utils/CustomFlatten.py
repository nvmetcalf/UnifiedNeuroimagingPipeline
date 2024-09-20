import pandas
import src.DataModels.Definitions as Definitions

#Takes a subject and returns a well formatted dataframe representing the
#Subject and Session data. Additionally assumes that the data has been 
#expanded into the (SESSION_ID : {DATA}) format.
def expanded_subject_to_dataframe(subject_data: dict) -> pandas.DataFrame:

    if subject_data == {}:
        return pandas.DataFrame()


    #First get all the unique fields.
    subject_metadata = {}
    fields = list()
    for key in subject_data:
        if key == '_id':
            continue

        if key == Definitions.SESSION_DATA:
            continue

        if key == Definitions.DUPLICATES:
            continue

        if key == Definitions.LONGITUDINAL:
            continue

        fields.append(key)
        subject_metadata[key] = subject_data[key]

    #Now go through each session and add their fields.
    for session_id in subject_data[Definitions.SESSION_DATA]:
        session_data = subject_data[Definitions.SESSION_DATA][session_id]

        for key in session_data:
            if key == '_id':
                continue

            if key in fields:
                continue
            
            fields.append(key)
    
    #Now build up a dictionary which has all the data we just obtained.
    
    flattened = {}
    for key in fields:
        flattened[key] = []

    #Now add each row iteratively.
    for session_id in subject_data[Definitions.SESSION_DATA]:
        
        #Copy the subject data to the current row.
        for key in subject_metadata:
            flattened[key].append(subject_metadata[key])

        session_data = subject_data[Definitions.SESSION_DATA][session_id]
        for key in session_data:
            if key == '_id':
                continue

            flattened[key].append(session_data[key])

        unreached = set(fields) - set(subject_metadata.keys()) - set(session_data.keys())

        for key in unreached:
            flattened[key].append('')
        
    
    return pandas.DataFrame.from_dict(flattened)

#Takes a subject and returns a well formatted dataframe representing the
#Subject and Session data. Assumes that the data is in a condensed form
#subject_data[Definitions.SESSION_DATA] = [list of session_ids]
def condensed_subject_to_dataframe(subject_data: dict) -> pandas.DataFrame:
    
    flattened = {}
    for key in subject_data:
        if key == '_id':
            continue

        if key == Definitions.SESSION_DATA:
            continue
        
        if key == Definitions.DUPLICATES:
            continue

        if key == Definitions.LONGITUDINAL:
            continue

        flattened[key] = []
        
    #Add the session_data field
    flattened[Definitions.SESSION_DATA] = []


    #Now add each row iteratively.
    for session_id in subject_data[Definitions.SESSION_DATA]:
        
        #Copy the subject data to the current row.
        for key in subject_data:
            if key == Definitions.SESSION_DATA:
                continue

            flattened[key].append(subject_data[key])

            flattened[Definitions.SESSION_DATA].append(session_id)

    return pandas.DataFrame.from_dict(flattened)


