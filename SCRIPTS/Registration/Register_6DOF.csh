#!/bin/csh

source $1
source $2

set FM_Suffix = $3

set AtlasName = `basename $target`

set ped = ($4)

set Reg_Target = $5

set SubjectHome = $cwd

rm -rf ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
mkdir ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}
pushd ${SubjectHome}/Anatomical/Volume/FieldMapping_${FM_Suffix}

	set peds = (`echo $ped | tr " " "\n" | sort | uniq`)
		
	if(! $?day1_path || ! $?day1_patid) then
		set Target_Path = ${SubjectHome}/Anatomical/Volume
		set Target_Patid = ${patid}
	else
		set Target_Path = ${day1_path}/Anatomical/Volume
		set Target_Patid = ${day1_patid}
	endif
	
	foreach direction($peds)
		bet ../${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} ${patid}_${FM_Suffix}_ref_distorted_${direction}_brain -R -f 0.3
		if($status) exit 1
		
		flirt -in ../${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} -ref ${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} -out ${patid}_${FM_Suffix}_ref_distorted_brain_on_${Reg_Target} -omat ${patid}_${FM_Suffix}_ref_unwarped_${direction}.mat -interp spline -dof 6 -cost mutualinfo -searchcost mutualinfo
		
		if($status) exit 1
	end
popd
exit 0
