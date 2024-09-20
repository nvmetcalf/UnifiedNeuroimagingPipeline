BEGIN{
print_vals = 0; 
}
{
	if($1 == "]," || substr($1,1,1) == "\"") 
		print_vals = 0; 

	if($1 == 0)
		first_slice_found = 0;

	if(print_vals) 
		printf("%s\n",$1); 

	if($1 == "\"SliceTiming\":")
	{
		print_vals = 1; 
	}
}
