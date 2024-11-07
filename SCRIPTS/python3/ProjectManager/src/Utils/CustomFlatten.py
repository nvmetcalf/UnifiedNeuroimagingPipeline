import pandas
import src.DataModels.Definitions as Definitions

def clean_dataframe_empty_columns(input_dataframe: pandas.DataFrame) -> pandas.DataFrame:

    columns_to_remove = []
    for col in input_dataframe:
        series = input_dataframe[col]
        if pandas.api.types.is_integer_dtype(series) and series.eq(0).all():
            columns_to_remove.append(col)
        if pandas.api.types.is_string_dtype(series) and series.eq('').all():
            columns_to_remove.append(col)
        if pandas.api.types.is_object_dtype(series) and series.apply(lambda x: isinstance(x, list) and len(x) == 0).all():
            columns_to_remove.append(col)

    return input_dataframe.drop(columns=columns_to_remove)

def concat_subtrees(metadata: dict, sub_trees: dict) -> dict:
    merged_subtrees = {}
    
    sub_trees_iter = iter(sub_trees)

    specify_parent = metadata != {}

    #Add the first sub tree to start with
    first_tree_name = next(sub_trees_iter)
    for col in sub_trees[first_tree_name]:
        name = f'{first_tree_name}.{col}' if specify_parent else col
        merged_subtrees[name] = sub_trees[first_tree_name][col]

    #Now we need to go through each remaining sub_tree and add the data.
    for sub_tree in sub_trees_iter:
        whitespace_amount = len(merged_subtrees[next(iter(merged_subtrees))])
        current_subtree_size = len(sub_trees[sub_tree][next(iter(sub_trees[sub_tree]))])

        touched_cols = set()
        for col in sub_trees[sub_tree]:
            
            #Figure out the final name.
            final_col_name = f'{sub_tree}.{col}' if specify_parent else col

            #If the column doesnt exist in merged_subtrees then we need to add it and pad the previous values with whitespace.
            if not final_col_name in merged_subtrees:
                whitespace = Definitions.MISSING_BY_TYPE[type(sub_trees[sub_tree][col][-1])]
                merged_subtrees[final_col_name] = ([whitespace] * whitespace_amount) + sub_trees[sub_tree][col]
                touched_cols.add(final_col_name)
                continue

            #Otherwise we need to just add the column to the one that already exists.
            merged_subtrees[final_col_name] += sub_trees[sub_tree][col]
            touched_cols.add(final_col_name)
        
        #Every sub_tree we need to flatten out the columns that we didnt touch with whitespace.
        for col in merged_subtrees:
            if col in touched_cols:
                continue 
            
            #Otherwise we have hit the case where we havent touched this one before.
            whitespace = Definitions.MISSING_BY_TYPE[type(merged_subtrees[col][-1])]
            merged_subtrees[col] += [whitespace] * current_subtree_size
    
    #If there is no metadata then we can just return now.
    if not specify_parent:
        return merged_subtrees
    
    #Now lets create the final flattened dictionary. We do this in two stages to take advantage of the fact that the dictionaries
    #Are ordered as of python3.7 by insertion order. We want the metadata to be first.
    flattened = {}

    #Now lets firge out how many times we need to copy the metadata keys.
    merged_size = len(merged_subtrees[next(iter(merged_subtrees))])


    #Add the metadata_keys
    for col in metadata:
        flattened[col] = [ metadata[col] ] * merged_size
    #Now add in the merged_subtrees.
    for col in merged_subtrees:
        flattened[col] = merged_subtrees[col]

    return flattened

def tree_to_table(root_element: dict, exclude_columns: list, depth = 0) -> dict:
    #I dont expect that this case should be evaluated but it seems like an obvious escape method. 
    if root_element == {}:
        return {}

    #Go through each key, if a key is a key,value pair (not another dictionary),
    #Then we should add it as a column. otherwise we need to convert it to a sub
    #table and add it appropriately.
    
    #Determine which values are metadata and which ones are children.
    sub_trees = {}
    metadata_keys  = []
    for key in root_element:
        if key in exclude_columns or root_element[key] == {}:
            continue

        if type(root_element[key]) == dict:
            sub_trees[key] = tree_to_table(root_element[key], exclude_columns, depth = depth + 1)
            continue
        
        metadata_keys.append(key)


    #If there are no child trees then the flattened data is simply the metadata.
    if len(sub_trees) == 0:
        flattened = {}
        for key in metadata_keys:
            flattened[key] = [ root_element[key] ]
         
        return flattened
    
    #Otherwise the data needs to be synthesized with the other flattened data.
    #We do this in general by copying the current metadata so that the amount of rows in that metadata matches
    #The number of rows in the flattened data.
    #Finally the data is then just concatenated together to make a flattened structure.
    #The trick comes in the case that the current metadata contains a key which matches ones of the sub_trees keys.
    #This is the case when merging accross similar subtrees that arent differentiated via the pivot columns.
    #In this case, 
    
    metadata = {}
    for key in metadata_keys:
        metadata[key] = root_element[key]

    return concat_subtrees(metadata, sub_trees)

def dict_to_dataframe(dict_data: dict, 
                      column_order = [], 
                      exclude_columns = []) -> pandas.DataFrame: 

    if dict_data == {}:
        return pandas.DataFrame()
    #Now lets construct the flattened dictionary which will be converted into the dataframe.
    flattened = tree_to_table(dict_data, exclude_columns)

    re_ordered = {}
    for col in column_order:
        if col in flattened:
            re_ordered[col] = flattened[col]

    #Now add all the stuff which wasnt hit earlier
    for col in flattened:
        if not col in column_order:
            re_ordered[col] = flattened[col]
            
    return pandas.DataFrame.from_dict(re_ordered)
