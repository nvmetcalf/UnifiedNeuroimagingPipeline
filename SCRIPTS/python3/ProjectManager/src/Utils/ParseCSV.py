class ParseCSV(object):
    def __init__(self, csv_file: str, match_col: str, match_str = None, delimiter = ',') -> None:
        self.delimeter = delimiter

        #try to open the csv file in read mode
        file = None
        try:
            file = open(csv_file, 'r')
        except Exception as e:
            print(f'There was an error opening the file {csv_file}.')
            raise e

        #Now lets try to read in the header.
        self.header = file.readline().strip()
        if self.header == '':
            print(f'The file {csv_file} appears to be empty, cannot parse file.')
            raise RuntimeError

        self.header_columns = self.__parse_line(self.header)
        
        match_col_index = 0
        if match_str:
            if not match_col in self.header_columns:
                print(f'A match column {match_col} was specified but this was not found in the header row of the target csv file. Cannot parse file.')
                raise RuntimeError
            else:
                match_col_index = self.header_columns.index(match_col)
       
        #This stores all the data found in the csv file in each row.
        self.row_data = []

        #Now lets read in the csv row wise.
        for row in file:
            cols = self.__parse_line(row.strip()) # Read in the columns on this line
            #Check if this row is empty.
            all_empty = True
            for col in cols:
                if col != '':
                    all_empty = False
                    break

            if all_empty:
                continue
            
            #Check if the match str is set and the string at this cell doesnt match what we want to process.
            if match_str and cols[match_col_index] != match_str:
                continue

            #Now associate each cell with the header columns, however if there arent enough cells in this
            #row, fill the associated column with ''. If there are more cells in this row then there are
            #Cells in the header, then truncate the data.
            n_cols = len(cols)
            n_header = len(self.header_columns)
            if n_cols < n_header:
                self.row_data.append(cols + [''] * (n_header - n_cols))
                continue

            #Otherwise we should truncate the data.
            self.row_data.append(cols[:n_header])
        
        file.close()

        #Finally lets transpose this data so we have a column-wise reprensentation as well.
        self.compute_transpose()
    
    #Given a line from a csv file, split the csv file based on the delimiter. Basically splits a line based on the set
    #delimiter. The only difference is that if a chunk is surrounded by "" that will be treated as its own chunk.
    #For instance the string 'aa,bb,"cc,dd"' will be parsed as ['aa','bb','"cc,dd"'] if ',' is the delimiter.
    def __parse_line(self, line: str) -> list:
        line = line.strip()

        #We need to accumulate the split list.
        start_chunk = True
        ignore_delim = False
        chunk_start = 0

        split_list = []
        for index,char in enumerate(line):
            if start_chunk and char == '"':
                ignore_delim = True
                continue
            
            if ignore_delim and char == '"':
                ignore_delim = False
                continue
           
            
            if not ignore_delim and char == self.delimeter:
                split_list.append(line[chunk_start:index])
                chunk_start = index + 1
                start_chunk = True
            else:
                start_chunk = False

        #Finally we need to add the last chunk.
        split_list.append(line[chunk_start:])
        return split_list

    def check_header_existance(self, coi: str) -> bool:
        return coi in self.header_columns
    
    #Computes the transpose so column wise operations work.
    def compute_transpose(self) -> None:
        self.column_data = []
        for col in range(len(self.header_columns)):
            self.column_data.append([ self.row_data[row][col] for row in range(len(self.row_data)) ])
    
    #This function will go through the internal row representation of the data and return a tuple where
    #each cell matches one of the header cells in target_columns.
    #If a target is specified which is not in the header then None is returned for that value.
    def generate_csv_data(self, target_columns: tuple):

        target_indicies = []
        for target in target_columns:
            try:
                target_indicies.append(self.header_columns.index(target))
            except ValueError:
                target_indicies.append(None)


        #Now go through each row in the csv.
        for row in self.row_data:
            yield ( row[index] if index != None else None for index in target_indicies )


    def get_column_as_list(self, column: str) -> list:

        column_index = 0
        try:
            column_index = self.header_columns.index(column)
        except ValueError:
            return []

        #Return a copy of the associated row.
        return self.column_data[column_index][:]


    def get_row_as_list(self, row_index: int) -> list:

        if row_index < 0 or row_index >= len(self.row_data):
            return []

        return self.row_data[row_index][:]
    

    #Save specific rows of a csv. Takes a list of indexes to save, should be pre-sorted.
    def save_csv_rows(self, rows: list, output_path: str) -> None:
        with open(output_path, 'w') as file:
            file.write(f'{self.header}\n')
            for index in rows:
                file.write(f'{self.delimeter.join(self.row_data[index])}\n')

    def print_rows(self, rows: list) -> None:
        print(self.header)
        for i in rows:
            print(self.delimeter.join(self.row_data[i]))

