#!/bin/csh

@ k = 0
while ($k < 50)
	date
	ssa_test 12 6 -i$k
	@ k++
end
exit

