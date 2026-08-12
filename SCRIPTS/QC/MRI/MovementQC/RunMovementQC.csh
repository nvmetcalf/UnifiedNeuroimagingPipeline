#!/bin/csh

#extract and output movement graphs

#####################################
		##
		## Creates line graphs based on the
		## subjects movements during
		## acquisition of the BOLD data
		##
		#####################################
		if($RunMovement == 1) then
			decho "	Creating Movement Graphs" ${DEBUG_FILE}

			if(-e movement) then
				cd movement

				if(-e ${Patient}_total_movement.txt) then
					rm -f ${Patient}_total_movement.txt
				endif

				touch ${Patient}_total_movement.txt
				foreach x(*.dat)
					echo $x >> ${Patient}_total_movement.txt
					tail -1 $x >> ${Patient}_total_movement.txt
				end

				if(`uname -s` == "SunOS") then
					##Generates post script files for movement
					$RELEASE/xmgr_rdat $cwd

					#Extra print of xmgr_rdat was here

					############################
                         ## Print the Movement Graphs
					############################
					if($?PrintMovement) then
						lp -d${BW_Printer} ${Patient}_total_movement.txt
              		          $RELEASE/xmgr_rdat $cwd -p${Printer}

						decho "	Printing Movement Graphs to ${Printer}" ${DEBUG_FILE}
					endif

					decho "	Printing total Movement RMS to ${BW_Printer}..." ${DEBUG_FILE}
				else
					echo "${RED_B}	Error: Movement graphs currently may only be generated on Sun Systems.${LF}${NORMAL}"
					decho "	Error: Movement graphs currently may only be generated on Sun Systems." ${DEBUG_FILE}
				endif


				rm -f ${Patient}.lst
				touch ${Patient}.lst
				@ i = 1;

				while( -e ${Patient}_b${i}_faln_dbnd_xr3d.ddat)
					echo ${Patient}_b${i}_faln_dbnd_xr3d.ddat >> ${Patient}.lst
					@ i++
				end

				run_ddat ${Patient}.lst $DDAT_Threshold
				cd ..
			else
				echo ${RED_B}-=FAIL: Movement Graphs not able to be created! Movement directory does not exist.${LF}${NORMAL}
				decho "		Error: Movement Graphs not able to be created! Movement directory does not exist." ${DEBUG_FILE}
			endif

			decho "		Finished." ${DEBUG_FILE}
		endif
