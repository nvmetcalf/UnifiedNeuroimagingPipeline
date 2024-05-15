#!/bin/csh

#exclude runs based upon how many frames are remaining from each run as determined by temporal mask


decho "	Thresholding Runs based on frames remaining. Threshold is ${PercentLeft}%." ${DEBUG_FILE}
			#need to collect how many frames remain in each run

			##############
			# count frames by run
			##############

			set home = $cwd

			set UsableBOLDS = 0
			rm -f temp_frame_removed_conc.conc
			touch temp_frame_removed_conc.conc

			@ BoldNum = 0
			foreach Run(${irun})
				pushd ${BoldDirName}${Run}

				touch ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid_${BoldDirName}${Run}.conc
				echo "number_of_files: 1" >! ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid_${BoldDirName}${Run}.conc
				echo "file:${Patient}_b${Run}_faln_dbnd_xr3d_atl_g7_bpss_resid.4dfp.img" >> ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid_${BoldDirName}${Run}.conc

				if($DVAR_Threshold == 0) then
					run_dvar_4dfp_corbetta ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid_${BoldDirName}${Run}.conc -m${home}/${FCmapsFolder}/${patid}_faln_dbnd_xr3d_atl_dfndm.4dfp.img -n4
				else
					run_dvar_4dfp_corbetta ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid_${BoldDirName}${Run}.conc -m${home}/${FCmapsFolder}/${patid}_faln_dbnd_xr3d_atl_dfndm.4dfp.img -x${DVAR_Threshold} -n4
				endif

				set format = (`cat ${patid}_faln_dbnd_xr3d_atl_g7_bpss_resid_${BoldDirName}${Run}.format`)
				set FrameCount = `format2lst $format | gawk '/+/{n++;};END{printf("%10d",n)}'`

				set TotalFrames = ""
				set TotalFrames = `format2lst -e ${format} | wc | awk '{print $3}'`

				set PercentLeft = `echo "$FrameCount	$TotalFrames" | awk '{i = $1/$2 * 100; print i}'`

				echo ${PercentLeft}

				#see if we have enough frames left over on this run
				if(`echo "$PercentLeft $ThreshRuns" | awk '{if($1 > $2) print 1}'` == 1) then
					#we do, so add it to the conc
					@ UsableBOLDS++

					echo "file:${cwd}/${patid}_b${Run}_faln_dbnd_xr3d_atl_g7_bpss_resid.4dfp.img" >> ../temp_frame_removed_conc.conc

				endif
				popd
			end

			#time to make the real conc
			echo "number_of_files: ${UsableBOLDS}" >! num_files.tmp
			cat num_files.tmp temp_frame_removed_conc.conc >! ${home}/${FCmapsFolder}/DVAR_${DVAR_Threshold}/${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid.conc

			#should have the conc we need, time to make the new format and back up the old one
			if($DVAR_Threshold == 0) then
					pushd $FCmapsFolder
					mv ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid.format ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid_no_runs_omitted.format
					run_dvar_4dfp_corbetta ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid.conc -m${home}/${FCmapsFolder}/${Patient}_faln_dbnd_xr3d_atl_dfndm.4dfp.img -n4
			else
					pushd ${FCmapsFolder}/DVAR_${DVAR_Threshold}
					mv ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid.format ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid_no_runs_omitted.format
					run_dvar_4dfp_corbetta ${Patient}_faln_dbnd_xr3d_atl_g7_bpss_resid.conc -m${home}/${FCmapsFolder}/${Patient}_faln_dbnd_xr3d_atl_dfndm.4dfp.img -x${DVAR_Threshold} -n4
			endif

			popd
			#tada, should have a conc and format with only those runs that have better than a x% frames remaining at a dvar of y
