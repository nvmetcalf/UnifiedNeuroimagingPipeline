import os

def expand_data_path(path: str, execution_path: str) -> str:

    #If the path is not absolute then it was executed relatively. We need to add the execution path
    #to any incoming data paths.
    if not os.path.isabs(path):
        path = os.path.join(execution_path, path)

    #Finally expand out environment variables if somehow they werent parsed.
    return os.path.expandvars(path)
