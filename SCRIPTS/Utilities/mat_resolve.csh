#!/usr/bin/csh

#original provided by Tyler Blazey, modified by Nicholas Metcalf

# Quick usage
if ( $#argv < 3) then
    echo "${0:t}: Wrapper script for running mat_resolve based motion correction"
    echo ""
    echo "Usage: <pet_image> <pet_json> <out_dir> <options>"
    echo ""
    echo "Required Arguments:"
    echo "  <pet_image>         Path to nifti PET 4D timeseries"
    echo "  <pet_json>          Path to JSON sidecar describing <pet_image>"
    echo "  <out_dir>           Directory for storing results"
    echo ""
    echo "Optional Arguments:"
    echo "  -cores            Number of processors to use for mat_resovle pairwise. Default is 1/4 detected cores"
    echo "  -no-clear         Do not clear out already existing results."
    echo "  -no-skip          Don't skip any frames."
    echo "  -mask             designate a mask image instead of creating one."
    echo "  -ignore-json      Only consider the images, nothing in the jsons like bolus onset. USeful for anatomical/MRI"
    echo ""
    echo "Note: Arugments must be specified in order"
    exit
endif
set echo
set n_procs = `nproc --all | awk '{printf("%i",$1/4)}'`
set force = 1
set no_skip = 0
set pet_mask = ""
set ignore_json = 0


set pet_img = `realpath $1`
if($2 == "none") then
	set ignore_json = 1
else
	set pet_json = `realpath $2`
endif

set out_dir = `realpath $3`


@ i = 4
while($i <= $#argv)
	@ k = $i + 1
	switch($argv[$i])
		case "-cores":
			set n_procs = $argv[$k]
			@ i++
			breaksw
		case "-no-skip":
			set no_skip = 1
			breaksw
		case "-no-clear":
			set force = 0
			breaksw
		case "-mask":
			set pet_mask = $argv[$k]
			@ i++
		case "-ignore-json":
			set ignore_json = 1
			breaksw
		default:
			echo "unknown option $argv[$i]"
			exit 1
			breaksw
	endsw
	@ i++
end
set echo
echo "Using $n_procs cores."

#install and update the modules for this script
pip install -e $PP_SCRIPTS/python3/crop_img
if($status) exit 1

pip install -e $PP_SCRIPTS/python3/mat_resolve
if($status) exit 1

# Make output directory if necessary
if ( ! -d $out_dir ) mkdir -p $out_dir

if($pet_mask == "") then
	# First compute mean image
	set pet_mean = $out_dir/${pet_img:t:r:r}_mean.nii.gz
	if ( ! -e $pet_mean || $force == 1) then
		fslmaths $pet_img -Tmean $pet_mean
	endif

	# Now get brain mask from cropped image
	set pet_mask = $out_dir/${pet_img:t:r:r}_mean_brain_mask.nii.gz
	if ( ! -e $pet_mask || $force == 1 ) then
		mri_synthstrip -i $pet_mean -m $pet_mask
		if ( $status != 0 ) exit 1
	endif
endif

# Use mask to crop image
set crop_root = $out_dir/${pet_img:t:r:r}_crop/${pet_img:t:r:r}
if ( ! -d $crop_root:h ) mkdir $crop_root:h
set pet_cropped = ${crop_root}_cropped.nii.gz
if ( ! -e $pet_cropped || $force == 1 ) then
    crop_img $pet_img $pet_mask --pad 10 --out $crop_root
    if ( $status != 0 ) exit 1
endif

# Register each frame to every other frame
set pair_dir = $out_dir/${pet_img:t:r:r}_pairwise

set json_flag = ""
if(! $ignore_json) then
	set json_flag = " --skip-before auto --fwhm 3 --bids-json $pet_json --bolus-threshold 100"
endif

mat_resolve_pairwise $pet_cropped \
                         $pair_dir \
						 $json_flag \
                         --workers $n_procs
if ( $status != 0 ) exit 1


# Run resolve to get transforms that minimize least squares error
set resolve_dir = $out_dir/${pet_img:t:r:r}_resolve

set skip_before = ""
if(! $ignore_json) then
    set skip_before = " --skip-before "`$PP_SCRIPTS/etc/jq .skip_before  $pair_dir/bolus_onset.json`
endif

mat_resolve $pair_dir \
                ${pet_img:t:r:r}_resolved \
                --output-dir $resolve_dir \
                --qc-report \
                --input-4d $pet_cropped \
                --reference -1 \
                $skip_before 
if ( $status != 0 ) exit 1


# Resample to orignal, uncropped space
set pet_resolved = ${resolve_dir}d.nii.gz

    echo "Splitting frames prior to resampling"
    set temp_dir = $cwd/temp
    rm -r $temp_dir
    mkdir $temp_dir
    
    fslsplit $pet_img $temp_dir/raw_
    
    # Now loop through all the frames and transform them
    @ i = 0
    set n_frames = `fslval $pet_img dim4`
    set n_pad = `echo "$n_frames - 1" | bc | tr -d '\n' | wc -m | tr -d ' '`
    set xfmd_frames = ()
    set xfm_root = $resolve_dir/$pet_img:t:r:r
    while ( $i <  $n_frames )
        set mat_num = `printf "%0${n_pad}d" $i`
        set split_num = `printf "%04d" $i`
        
        set full_resolved = ${xfm_root}_full_${mat_num}_to_${pet_img:t:r:r}_resolved_full.mat 
        if ( ! -e $full_resolved || $force == 1 ) then
            cp $FSLDIR/etc/flirtsch/ident.mat $full_resolved
            foreach xfm ( ${crop_root}_full2crop.mat \
                          ${xfm_root}_cropped_${mat_num}_to_${pet_img:t:r:r}_resolved.mat \
                          ${crop_root}_crop2full.mat )
                convert_xfm -omat $full_resolved -concat $xfm $full_resolved
                if ( $status != 0 ) exit 1           
            end
            set force = 1
        endif
        
        echo "Resampling frame $i of $n_frames"
        flirt -init $full_resolved -applyxfm \
			  -interp nearestneighbour \
			  -ref $pet_mask \
			  -out $temp_dir/xfmd_$split_num \
			  -in $temp_dir/raw_$split_num
			  
        if ( $status != 0 ) exit 1
        set xfmd_frames = ( $xfmd_frames $temp_dir/xfmd_$split_num )
        @ i++
        
    end
    
    echo "Merging motion corrected frames"
    fslmerge -t $pet_resolved $xfmd_frames
    if ( $status != 0 ) exit 1
    
    # Clean up
    rm -R $temp_dir
    

