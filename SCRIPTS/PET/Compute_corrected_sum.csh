#!/bin/csh
set echo
source $PP_SCRIPTS/Config/PET_Isotopes.cfg

if ($#argv < 7) then
	echo "Usage: Compute_uncorrected_mean.csh <pet input name> <start frame> <end frame> <isotope> <output name> <DoFrameAlign> <SumMethod> <FD Threshold in mm> <Brain radius in mm>"
	echo "	Supported Isotopes:"
	@ i = 1
	while($i <= $#Isotopes)
		@ j = $i + 1

		echo "$Isotopes[$i] : $Isotopes[$j] s"
		@ i = $i + 2
	end

	echo "Sum Methods: "
	echo "	1) 1/2 duration before and after Peak Uptake"
	echo "	2) Start sum of frames after Duration amount of time till the end of scan"
	echo "	3) Sum the duration time range"
	exit 1
endif

set Image  = $1
set DurationAfterPeak = $2
set Isotope = $3
set Output = $4
set DoFrameAlign = $5
set SumMethod = $6
set FD_Threshold = $7
set BrainRadius = $8

if($#BrainRadius == 0) then
	set BrainRadius = 50
endif

if($#FD_Threshold == 0) then
	set FD_Threshold = 0.5
endif
#find the isotopes half life
@ i = 1
set HalfLife = -1

mkdir $Output
cd $Output

while($i <= $#Isotopes)
	@ j = $i + 1

	if($Isotope == $Isotopes[$i]) then
		set HalfLife = $Isotopes[$j]
		echo "Found $Isotope halflife of $HalfLife s!"
		break
	endif

	@ i = $i + 2
end

if($HalfLife == "-1") then
	echo "Error: Could not find $Isotope in the configuration. Enter one in $PP_SCRIPTS/Config/PET_Isotopes.cfg"
	exit 1
endif


if (! -e $Image) then
	echo "Error: $Image not found"
	exit 1
endif

set EndFrame = `fslinfo $Image | grep dim4 | head -1 | awk '{print($2)}'`

cat $Image:r:r".json" | awk 'BEGIN{Output = 0; }{if($1 == "\"DecayFactor\":") Output = 1;  if($1 == "\"FrameTimesStart\":" || $1 == "],") Output = 0; if(Output) print($1);}' | cut -d, -f1 >! DecayFactor
cat $Image:r:r".json" | awk 'BEGIN{Output = 0; }{if($1 == "\"FrameTimesStart\":") Output = 1;  if($1 == "\"FrameDuration\":" || $1 == "],") Output = 0; if(Output) print($1);}' | cut -d, -f1 >! FrameTimesStart
cat $Image:r:r".json" | awk 'BEGIN{Output = 0; }{if($1 == "\"FrameDuration\":") Output = 1;  if($1 == "\"FrameReferenceTime\":" || $1 == "],") Output = 0; if(Output) print($1);}' | cut -d, -f1 >! FrameDuration
cat $Image:r:r".json" | awk 'BEGIN{Output = 0; }{if($1 == "\"FrameReferenceTime\":") Output = 1;  if($1 == "\"SliceThickness\":" || $1 == "],") Output = 0; if(Output) print($1);}' | cut -d, -f1 >! FrameReferenceTime

set PET_Timings = `basename $Image:r:r`"_PET_timings.txt"

paste DecayFactor FrameTimesStart FrameDuration FrameReferenceTime | tail -$EndFrame >! $PET_Timings
if($status) exit 1

paste DecayFactor FrameTimesStart FrameDuration FrameReferenceTime >! ${Output}_Timings.txt
if($status) exit 1

set global_prm = $Output".glob.prm"
set global_dat = $Output".glob.dat"
# Make the global parameter file with header:
ftouch $global_prm
ftouch $global_dat

echo "#start	mean	length	frame" >> $global_prm
echo "#start	mean	length	frame" >> $global_dat
echo $cwd

@ TotalDuration = 0

#register to the end frame volume as it's most brain like (starts counting from 0)
if($DoFrameAlign) then
	mcflirt -in $Image -out ${Output}_mcflirt -nn_final -mats -report -plots -stats -refvol `echo $EndFrame | awk '{print($1-1)}'`
	if($status) exit 1

	$PP_SCRIPTS/Utilities/compute_fd.csh ${Output}_mcflirt.par $BrainRadius 0 1 $FD_Threshold
	if($status) exit 1
else
	fslmaths $Image -Tmean ${Output}_mcflirt_meanvol
	if($status) exit 1

	cp $Image ${Output}_mcflirt.nii.gz
endif

#make a brain mask
fslmaths ${Output}_mcflirt_meanvol -thr 0 -kernel gauss 1.274 -fmean ${Output}_mcflirt_meanvol_sm3
if($status) exit 1

niftigz_4dfp -4 ${Output}_mcflirt ${Output}_mcflirt
if($status) exit 1

#extract the frames we will be working with and their timings
#correct for decay
#fslroi starts from 0 not 1, so the code looks a bit weird
@ i = 0
while($i < $EndFrame && $EndFrame > 1)
	#set frame to the nominal frame name (makes sense to humans)
	@ frame = $i + 1

	sum_pet_4dfp_v2 ${Output}_mcflirt $PET_Timings $frame $frame -h$HalfLife ${Output}"_frame_"$frame"_deco"
	if($status) exit 1

	niftigz_4dfp -n ${Output}"_frame_"$frame"_deco" ${Output}"_frame_"$frame"_deco"
	if($status) exit 1

	#we want to skip the header line of the frame timings, so gotta go +2 from i
	head -$frame $PET_Timings | tail -1 >> ${Output}_Timings.txt

	set Duration = `head -$frame $PET_Timings | tail -1 | awk '{print($3)}'`
	set FrameStart = `head -$frame $PET_Timings | tail -1 | awk '{print($2)}'`

	set FrameMean = `fslstats ${Output}"_frame_"$frame"_deco" -m`

	echo "----------------------------------"
	echo "$FrameStart	$FrameMean	$Duration	$frame" >> $global_prm
	echo "$FrameStart	$FrameMean">>$global_dat
	echo "$frame	$Duration	$FrameStart	$FrameMean "
	echo "----------------------------------"
	@ i++

end

if($SumMethod == 1) then
	if($EndFrame == 1) then
		#only one frame, not many choices on what to use...
		set SumStartFrame = 1
		set SumEndFrame = 1
	else
		# Find the frames that should be summed to make the auto image:
		peakchk $global_prm $DurationAfterPeak 8 >&! $global_dat

		set SumStartFrame = `grep "Start Frame" $global_dat | cut -d= -f2`
		set SumEndFrame = `grep "Last Frame" $global_dat | cut -d= -f2`
	endif
else if($SumMethod == 2) then
	# instead of using the peak uptake, start at the end of the timeseries
	# and grab the indicated durations worth of frames
	@ DurationRemaining = $DurationAfterPeak

	@ SumStartFrame = $EndFrame
	@ SumEndFrame = $EndFrame
	@ Duration = `head -$SumStartFrame $PET_Timings | tail -1 | awk '{printf("%5.0f",$3)}'`
	while($DurationRemaining > $Duration && $SumStartFrame > 0)
		@ Duration = `head -$SumStartFrame $PET_Timings | tail -1 | awk '{printf("%5.0f",$3)}'`
		@ DurationRemaining = `echo $DurationRemaining $Duration | awk '{printf("%5.0f",$1 - $2)}'`
		@ SumStartFrame--
	end
else if($SumMethod == 3) then
	# extract the start time and end time
	set TimeStart = `echo $Duration | cut -d"-" -f1`
	set TimeEnd = `echo $Duration | cut -d"-" -f2`

	@ Time = 0

	set SumStartFrame = 0
	set SumEndFrame = 0

	@ i = 1
	set TotalFrames = `wc $PET_Timings | awk '{print($1)}'`
	set CurrDuration = 0

	while ($i <= $TotalFrames)

		set CurrFrameDuration = `head -$i $PET_Timings | tail -1 | awk '{printf("%5.0f",$3)}'`
		set CurrDuration = `echo $CurrDuration $CurrFrameDuration | awk '{printf("%5.0f",$1+$2);}'`

		if($SumStartFrame == 0 && `echo $CurrDuration $TimeStart | awk '{if($1 > $2) print(1); else print(0);}'`) then
			set SumStartFrame = $i
		endif

		if($SumEndFrame == 0 && `echo $CurrDuration $TimeEnd | awk '{if($1 > $2) print(1); else print(0);}'`) then
			set SumEndFrame = $i
			@ i = $TotalFrames
		endif

		@ i++
	end
else if($SumMethod == 4) then
	#use the offset from the duration variable, create the midpoint, compute the decay factor?

else if($SumMethod == 5) then
	#just average it all together, which was done earlier.
	cp ${Output}_mcflirt_meanvol.nii.gz ${Output}"_sum_deco.nii.gz"
	goto END
else
	echo "Unknown sum method."
	exit 1
endif

if($EndFrame == 1) then
	set UseFirstFrameDecay = "-d"
else
	set UseFirstFrameDecay = ""
endif

if($SumStartFrame <= 0) then
	set SumStartFrame = 1
endif

echo "Start Frame: $SumStartFrame"
echo "End Frame: $SumEndFrame"

sum_pet_4dfp_v2 ${Output}_mcflirt $PET_Timings $SumStartFrame $SumEndFrame -h$HalfLife ${UseFirstFrameDecay} ${Output}"_sum_deco"
if($status) exit 1

niftigz_4dfp -n ${Output}"_sum_deco" ${Output}"_sum_deco"
if($status) exit 1

END:
rm -f *4dfp* *_frame_*

cd ..

exit 0
