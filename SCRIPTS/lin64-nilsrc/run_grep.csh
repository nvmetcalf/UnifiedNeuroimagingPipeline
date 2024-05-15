#!/bin/csh

foreach x (*/*.mak)

	set str = `grep lin_algebra $x`
	if (! $status) then
		echo $x"	"$str
	endif
end
