function write_matrix_as_csv(Input, CSV_Out, transpose)

    if(ischar(Input))
        a = importdata(Input);
    else
        a = Input;
    end
    
    if(transpose)
        a = a';
    end
    
    csvwrite(CSV_Out,a)
end