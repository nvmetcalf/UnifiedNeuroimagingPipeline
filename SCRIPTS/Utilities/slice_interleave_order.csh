#!/bin/csh

set json = $1


#test to see if it is a row or column
set a = (`grep SliceTiming $1 | sed 's/\[/ /g' | sed 's/, / /g' | sed 's/],//g'` )
if($#a > 1) then
	#make it a column
	rm -f slice_timing.txt
	touch slice_timing.txt
	
	@ i = 2
	while ($i <= $#a)
		echo $a[$i]"," >> slice_timing.txt
		@ i++
	end
else
	cat $json | awk -f $PP_SCRIPTS/Utilities/slice_interleave.awk | uniq >! slice_timing.txt
endif

set num_slices = `cat slice_timing.txt | wc | awk '{print $1}'`

cat slice_timing.txt | sort -n | sed 's/,//g' | uniq | awk '{printf("%s ",$1)}' >! sorted_slice_timing.txt

set slice_timings = (`cat slice_timing.txt | sed 's/,/ /g'`)

set sorted_slice_timings = (`cat sorted_slice_timing.txt | uniq`)

set slice_order = ();
@ i = 1
while($i <= $#sorted_slice_timings)

	@ slice = 1
	foreach slc_tim($slice_timings)
		if($sorted_slice_timings[$i] == $slc_tim) then
			set slice_order = ($slice_order $slice)
			break
		endif
		@ slice++
	end
	
	@ i++
end

echo `echo $slice_order | sed 's/ /,/g'`

