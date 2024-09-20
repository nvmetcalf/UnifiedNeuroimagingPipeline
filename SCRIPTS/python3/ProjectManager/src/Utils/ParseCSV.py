class ParseCSV(object):
    def __init__(self, csv_file: str, delimiter = ',') -> None:
        #try to open the csv file in read mode.
        file = None
        try:
            file = open(csv_file, 'r')
        except Exception as e:
            print(f'There was an error opening the file {csv_file}.')
            raise e

        #Now lets try to read in the header.
        header = file.readline().strip()
        if header == '':
            print(f'The file {csv_file} appears to be empty, cannot parse file.')
            raise RuntimeError

        self.header_columns = header.split(delimiter)
        
       
        #This stores all the data found in the csv file in each row.
        self.row_data = []

        #Now lets read in the csv row wise.
        for row in file:
            cols = row.strip().split(delimiter) # Read in the columns on this line
            #Check if this row is empty.
            all_empty = True
            for col in cols:
                if col != '':
                    all_empty = False
                    break

            if all_empty:
                #Skip this row.
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

        #Finally lets transpose this data so we have a column-wise reprensentation as well.
        self.column_data = []
        for col in range(len(self.header_columns)):
            self.column_data.append([ self.row_data[row][col] for row in range(len(self.row_data)) ])

        file.close()
    
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
