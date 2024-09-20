#!/bin/csh
set echo
set SubjectList = ($1)

set Fail = ()
set blur	= .735452	# = .4413/6, i.e., 6 mm blur that is conservative relative to fidl's Monte Carlo
set SmoothingSigma = `echo $2 | awk '{print($1/2.3548);}'`

foreach Subject($SubjectList)
	pushd ${Subject}/Functional/Volume
# 		niftigz_4dfp -4 ${Subject}_rsfMRI_uout_resid_bpss ${Subject}_rsfMRI_uout_resid_bpss
# 		if($status) then
# 			set Fail = ($Fail $Subject)
# 			goto SKIP
# 		endif
		if(-e ${Subject}_rsfMRI_uout_bpss_resid.nii.gz) then
			fslmaths ${Subject}_rsfMRI_uout_bpss_resid.nii.gz -kernel gauss $SmoothingSigma -fmean ${Subject}_rsfMRI_uout_bpss_resid_sm${2}
		else
			fslmaths ${Subject}_rsfMRI_uout_resid_bpss.nii.gz -kernel gauss $SmoothingSigma -fmean ${Subject}_rsfMRI_uout_resid_bpss_sm${2}
		endif
		#gauss_4dfp ${Subject}_rsfMRI_uout_resid_bpss $blur
		if($status) then
			set Fail = ($Fail $Subject)
			goto SKIP
		endif
		
		#niftigz_4dfp -n ${Subject}_rsfMRI_uout_resid_bpss_g7 ${Subject}_rsfMRI_uout_resid_bpss_g7
# 		if($status) then
# 			set Fail = ($Fail $Subject)
# 			goto SKIP
# 		endif
		
		rm *4dfp*
		
		SKIP:
	popd
end

echo $Fail
