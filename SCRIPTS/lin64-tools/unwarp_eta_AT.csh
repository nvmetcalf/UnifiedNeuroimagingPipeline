#!/bin/csh -fx

#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/unwarp_eta_AT.csh,v 1.1 2020/08/24 22:08:05 avi Exp $
#$Log: unwarp_eta_AT.csh,v $
# Revision 1.1  2020/08/24  22:08:05  avi
# Initial revision
#
set idstr = '$Id: unwarp_eta_AT.csh,v 1.1 2020/08/24 22:08:05 avi Exp $'
echo $idstr
set program = $0; set program = $program:t

if ($#argv < 2) then
	echo $program": this script is intended to be called only by basis_opt_AT"
	exit -1
endif
#Get location of input images
source $argv[1]
if ( ! $?scratch ) set scratch = `pwd`
#Extract echo spacing
set dwell = `cat $argv[2]  | awk '/Echo Spacing/{printf("%.7f", $NF);}'`

#Override default FSL output type to appease nifti_4dfp
setenv FSLOUTPUTTYPE NIFTI

# convert estimated field map 4dfp->nifti
$RELEASE/nifti_4dfp -n $phase $phase		>> /dev/null
if ($status) exit $status

$FSLDIR/bin/fugue --loadfmap=$phase --dwell=$dwell --in=$scratch/${epi} -u $scratch/${epi}_uwrp_tmp  --unwarpdir=$dir
if ($status) exit $status


$RELEASE/nifti_4dfp -4 $scratch/${epi:t}_uwrp_tmp $scratch/${epi:t}_uwrp_tmp -N	>> /dev/null
if ($status) exit $status

/bin/rm $scratch/${epi:t}_uwrp_tmp.nii
exit 0
