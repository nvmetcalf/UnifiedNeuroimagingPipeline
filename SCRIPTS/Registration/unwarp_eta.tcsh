#!/bin/tcsh -f

#Get location of input images
source $argv[1]

#Extract echo spacing
set dwell = `cat $argv[2] | awk '/Echo Spacing/{printf("%.20f", $NF/1000);}'`

#Override default FSL output type to appease nifti_4dfp
setenv FSLOUTPUTTYPE NIFTI

# convert estimated field map 4dfp->nifti
$RELEASE/nifti_4dfp -n $phase $phase		>> /dev/null
if ($status) exit $status

#Undistort EPI with new field map
$FSLDIR/bin/fugue --loadfmap=$phase --dwell=$dwell --in=$epi -u ${epi:h}/${epi:t}_uwrp --unwarpdir=$dir

#Convert NIFTI to 4dfp
$RELEASE/nifti_4dfp -4 ${epi:h}/${epi:t}_uwrp ${epi:h}/${epi:t}_uwrp -N		>> /dev/null

#Copy over initial t4 file
/bin/cp $t4 ${epi:h}/${epi:t}_uwrp_to_${t2:t}_t4

#Register the unwarped epi to the t2
@ mode = 8192 + 2048 + 3
$RELEASE/imgreg_4dfp $t2 $t2_mskt ${epi:h}/${epi:t}_uwrp none ${epi:h}/${epi:t}_uwrp_to_${t2:t}_t4 $mode >! ${epi:h}/${epi:t}_uwrp_to_${t2:t}.log

#Extract eta from the imgreg_4dfp log
set eta = `awk '/eta,q/{print $2}' ${epi:h}/${epi:t}_uwrp_to_${t2:t}.log | tail -1`

#If weight file has an eta, remove it; append current value to the end
sed '/Eta:/d'		$argv[2] >! temp$$
/bin/mv temp$$		$argv[2]
echo "Eta: $eta"     >> $argv[2]

