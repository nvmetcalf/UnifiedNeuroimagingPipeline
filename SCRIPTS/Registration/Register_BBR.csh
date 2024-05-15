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
		
		set peds = (`echo $ped | tr " " "\n" | sort | uniq`)
		
		foreach direction($peds)
			epi_reg --epi=../${FM_Suffix}_ref/${patid}_${FM_Suffix}_ref_distorted_${direction} --t1=${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target} --t1brain=${Target_Path}/${Reg_Target}/${Target_Patid}_${Reg_Target}_brain.nii.gz --out=${patid}_${FM_Suffix}_ref_unwarped_${direction} --noclean
			if($status) exit 1
		end
	endif
	
popd

exit 0
