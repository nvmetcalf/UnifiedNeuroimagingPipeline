BEGIN {
	FramesRemoved = 0;
	FramesKept = 0;
}

{
	if($0 == "x") FramesRemoved +=1;
	if($0 == "+") FramesKept +=1;
}

END {
	printf("%i\t%i\t%3.0f\t%i",FramesRemoved,FramesKept,(FramesKept/(FramesKept+FramesRemoved)) * 100,FramesKept*TR);	
}
