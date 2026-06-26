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

#This function takes a tree and consolidates it into a more flattened format. The way that it does this is by combining levels which just
#store hierachy infomration. For instance.
#The following tree would be flattened as follows:
#a { b { key1 : value1} c { key1: value1 } } } -> a { b.key1 : value 1, c.key1 : value1 }

def consolidate_tree(tree : dict, prepend = '') -> dict:
    
    consolidated = {}
    all_dicts = True
    for key in tree:
        if not isinstance(tree[key], dict):
            all_dicts = False
            break

    if all_dicts:
        for key in tree:
            key_name = f'{prepend}.{key}' if prepend != '' else key
            consolidated[key_name] = consolidate_tree(tree[key], prepend)
        
        return consolidated

    #Otherwise just return the tree.
    return tree

def concat_subtrees(metadata: dict, sub_trees: dict) -> dict:
    if len(sub_trees) == 0:
        flattened = {}
        for key in metadata:
            flattened[key] = [ metadata[key] ]

        return flattened

    merged_subtrees = {}
    
    sub_trees_iter = iter(sub_trees)

    #Add the first sub tree to start with
    first_tree_name = next(sub_trees_iter)
    for col in sub_trees[first_tree_name]:
        merged_subtrees[col] = sub_trees[first_tree_name][col]

    #Now we need to go through each remaining sub_tree and add the data.
    for sub_tree in sub_trees_iter:
        whitespace_amount = len(merged_subtrees[next(iter(merged_subtrees))])
        current_subtree_size = len(sub_trees[sub_tree][next(iter(sub_trees[sub_tree]))])

        touched_cols = set()
        for col in sub_trees[sub_tree]:

            #If the column doesnt exist in merged_subtrees then we need to add it and pad the previous values with whitespace.
            if not col in merged_subtrees:
                whitespace = Definitions.MISSING_BY_TYPE[type(sub_trees[sub_tree][col][-1])]
                merged_subtrees[col] = ([whitespace] * whitespace_amount) + sub_trees[sub_tree][col]
                touched_cols.add(col)
                continue

            #Otherwise we need to just add the column to the one that already exists.
            merged_subtrees[col] += sub_trees[sub_tree][col]
            touched_cols.add(col)
        
        #Every sub_tree we need to flatten out the columns that we didnt touch with whitespace.
        for col in merged_subtrees:
            if col in touched_cols:
                continue 
            
            #Otherwise we have hit the case where we havent touched this one before.
            whitespace = Definitions.MISSING_BY_TYPE[type(merged_subtrees[col][-1])]
            merged_subtrees[col] += [whitespace] * current_subtree_size
    
    #If there is no metadata then we can just return now.
    if metadata == {}:
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

def tree_to_table(root_element: dict, exclude_columns: list) -> dict:

    #I dont expect that this case should be evaluated but it seems like an obvious escape method. 
    if root_element == {}:
        return {}

    #Go through each key, if a key is a key,value pair (not another dictionary),
    #Then we should add it as a column. otherwise we need to convert it to a sub
    #table and add it appropriately.
    
    #Determine which values are metadata and which ones are children.
    sub_trees = {}
    metadata = {}
    
    for key in root_element:
        if key in exclude_columns or root_element[key] == {}:
            continue

        if type(root_element[key]) == dict:
            sub_trees[key] = tree_to_table(root_element[key], exclude_columns)
            continue
            
        metadata[key] = root_element[key]
    
    #Otherwise the data needs to be synthesized with the other flattened data.
    #We do this in general by copying the current metadata so that the amount of rows in that metadata matches
    #The number of rows in the flattened data.
    #Finally the data is then just concatenated together to make a flattened structure.
    #The trick comes in the case that the current metadata contains a key which matches ones of the sub_trees keys.
    #This is the case when merging accross similar subtrees that arent differentiated via the pivot columns.
    return concat_subtrees(metadata, sub_trees)


#This has a critical constraint that the keys for every subgroup must be unique.
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
