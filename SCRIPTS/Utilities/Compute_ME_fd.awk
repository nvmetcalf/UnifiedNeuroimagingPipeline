{
	sum = 0;
	num_echos = NF;
	good_echo_fd = 1;
	good_frame_fd = 1;
	
	for( i = 1; i<=num_echos; i++)
	{
		sum+=$i; 
		
		if($i > echo_fd_thresh)
		{
			good_echo_fd = 0;
		}
	}
	mean = sum/num_echos;
	if(mean > frame_fd_thresh || skip > 0)
	{
		good_frame_fd = 0;
	}
	print(sum" "num_echos" "mean" "good_echo_fd" "good_frame_fd" "good_frame_fd*good_echo_fd);
	skip--;
}
