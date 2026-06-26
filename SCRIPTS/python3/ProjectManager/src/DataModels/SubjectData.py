import src.DataModels.ColumnNames as ColumnNames
import src.DataModels.Definitions as Definitions

#Defines the structure of the subject document. These are the fields that will exist in the databse.
def generate_subject_data(map_id: str, cnda_id: str) -> dict:
    
    #Longituninal and duplicate data is stored in the following manor.
    #An uid is stored which is associated with a list of uids that it owns.
    #These uids correspond to session_ids that the subject owns.
    #If a session uid is removed then these sources must also searched and removed
    #both in the local and database copies.
    subject_data = {
        ColumnNames.PARTICIPANT_ID    : map_id,
        ColumnNames.SUBJECT_ACCESSION : cnda_id,
        Definitions.LONGITUDINAL      : {},
        Definitions.DUPLICATES        : []
    }
    return subject_data
