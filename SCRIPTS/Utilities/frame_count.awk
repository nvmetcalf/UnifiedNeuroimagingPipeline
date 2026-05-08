BEGIN {
	FramesRemoved = 0;
	FramesKept = 0;
}

{
	if($1 == "0") FramesRemoved +=1;
	if($1 == "1") FramesKept +=1;
}

END {
	printf("%s,%i,%i,%3.0f,%i\n",RunIndex,FramesRemoved,FramesKept,(FramesKept/(FramesKept+FramesRemoved)) * 100,FramesKept*TR);	
}
