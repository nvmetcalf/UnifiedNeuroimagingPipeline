#!/bin/csh

#see if two images register similarly to each other

set SourceImage = $1
set TargetImage = $2
set SourceToTargetMat = $3
set TargetToSourceMat = $4
set StartingCoord = ($5 $6 $7)
set MaxThresholdDistance = $8

if($SourceToTargetMat:e == "mat") then
	set TransformType = "-xfm"
else
	set TransformType = "-warp"
endif

if($TargetToSourceMat:e == "mat") then
	set TargetTransformType = "-xfm"
else
	set TargetTransformType = "-warp"
endif

#find out where the StartingCoord in the Source to Target matrix ends up
#echo $StartingCoord | img2imgcoord -src $SourceImage -dest $TargetImage -xfm $SourceToTargetMat -mm
set SourceToTarget_Result = (`echo $StartingCoord | img2imgcoord -src $SourceImage -dest $TargetImage $TransformType $SourceToTargetMat -mm | tail -1`)

#Using the result of the source to target, see if the independent target to source ends up in the same place
#echo $SourceToTarget_Result | img2imgcoord -dest $SourceImage -src $TargetImage -xfm $TargetToSourceMat -mm
set TargetToRestult_Result = (`echo $SourceToTarget_Result | img2imgcoord -dest $SourceImage -src $TargetImage $TargetTransformType $TargetToSourceMat -mm | tail -1`)

#It won't be exact, but lets see how close we are.
set Distance = `echo $StartingCoord $TargetToRestult_Result | awk '{print(sqrt(($1-$4)^2 + ($2 - $5)^2 + ($3 - $6)^2))}'`

#see if the forward and backwards transforms end up in roughly the same point
if($MaxThresholdDistance == "") then
	echo $Distance
else
	echo $Distance $MaxThresholdDistance | awk '{if($1<=$2) print(1); else print(0);}'
endif

exit 0
