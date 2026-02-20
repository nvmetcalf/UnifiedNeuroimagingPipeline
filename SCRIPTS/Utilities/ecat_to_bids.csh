#!/bin/csh
set echo

pushd $1
	foreach ses(*)
		pushd $ses
			set curr_dir = $cwd
			mkdir ECAT 4DFP BIDS
			mv *.v *.r ECAT/

			cd ECAT
				foreach ecat(*.v)
					ecatto4dfp $ecat $curr_dir/4DFP/$ecat:r
					if($status) exit 1

					ecat_header $ecat >! $curr_dir/4DFP/$ecat:r"_header.txt"
					if($status) exit 1
				end
			cd ..

			cd 4DFP
				#should have 4dfp images that also have the timing information for each scan
				foreach image(`ls *.4dfp.img`)
					niftigz_4dfp -n $image:r:r $curr_dir/BIDS/$image:r:r
					if($status) exit 1

					cp $PP_SCRIPTS/PET/misc/template_1.json $curr_dir/BIDS/$image:r:r".json"

					set value = `grep "Facility Name" $curr_dir/4DFP/$image:r:r"_header.txt" | cut -d: -f2`
					cat $curr_dir/BIDS/$image:r:r".json" | sed "s/InstitutionName_REPLACE/${value}/g" >! temp
					mv temp $curr_dir/BIDS/$image:r:r".json"

					set value = `grep "Software Version" $curr_dir/4DFP/$image:r:r"_header.txt" | cut -d: -f2`
					cat $curr_dir/BIDS/$image:r:r".json" | sed "s/SoftwareVersions_REPLACE/$value/g" >! temp
					mv temp $curr_dir/BIDS/$image:r:r".json"

					set value = `grep "Study Description" $curr_dir/4DFP/$image:r:r"_header.txt" | cut -d: -f2`
					cat $curr_dir/BIDS/$image:r:r".json" | sed "s/SeriesDescription_REPLACE/$value/g" >! temp
					mv temp $curr_dir/BIDS/$image:r:r".json"

					set value = `grep "Scan TOD" $curr_dir/4DFP/$image:r:r"_header.txt" | cut -d: -f2`
					cat $curr_dir/BIDS/$image:r:r".json" | sed "s/AcquisitionTime_REPLACE/$value/g" >! temp
					mv temp $curr_dir/BIDS/$image:r:r".json"

					set value = `grep "Radiopharmaceutical" $curr_dir/4DFP/$image:r:r"_header.txt" | cut -d: -f2 | tr -d " "`
					cat $curr_dir/BIDS/$image:r:r".json" | sed "s/Radiopharmaceutical_REPLACE/$value/g" >! temp
					mv temp $curr_dir/BIDS/$image:r:r".json"

					set value = `grep "Injected dose" $curr_dir/4DFP/$image:r:r"_header.txt" | cut -d: -f2`
					cat $curr_dir/BIDS/$image:r:r".json" | sed "s/RadionuclideTotalDose_REPLACE/$value/g" >! temp
					mv temp $curr_dir/BIDS/$image:r:r".json"

					set value = `grep "Isotope Half-life" $curr_dir/4DFP/$image:r:r"_header.txt" | cut -d: -f2`
					cat $curr_dir/BIDS/$image:r:r".json" | sed "s/RadionuclideHalfLife_REPLACE/$value/g" >! temp
					mv temp $curr_dir/BIDS/$image:r:r".json"

					set value = `grep "Calibration Factor" $curr_dir/4DFP/$image:r:r"_header.txt" | cut -d: -f2`
					cat $curr_dir/BIDS/$image:r:r".json" | sed "s/DoseCalibrationFactor_REPLACE/$value/g" >! temp
					mv temp $curr_dir/BIDS/$image:r:r".json"

					echo \"DecayFactor\": [ >> $curr_dir/BIDS/$image:r:r".json"
					cat $curr_dir/4DFP/$image:r:r".4dfp.img.rec" | awk 'BEGIN{output = 0; started = 0; skip = 0}{if($2 == "Missing" && started){printf("\n],\n");started=0;output=0;} if(started && skip) printf(",\n"); if(output) {printf("%s",$7); skip=1;} if($1 == "Frame") {output = 1; started=1;}}' >> $curr_dir/BIDS/$image:r:r".json"

					echo \"FrameTimesStart\": [ >> $curr_dir/BIDS/$image:r:r".json"
					cat $curr_dir/4DFP/$image:r:r".4dfp.img.rec" | awk 'BEGIN{output = 0; started = 0; skip = 0}{if($2 == "Missing" && started){printf("\n],\n");started=0;output=0;} if(started && skip) printf(",\n"); if(output) {printf("%s",$4/1000); skip=1;} if($1 == "Frame") {output = 1; started=1;}}' >> $curr_dir/BIDS/$image:r:r".json"

					echo \"FrameDuration\": [ >> $curr_dir/BIDS/$image:r:r".json"
					cat $curr_dir/4DFP/$image:r:r".4dfp.img.rec" | awk 'BEGIN{output = 0; started = 0; skip = 0}{if($2 == "Missing" && started){printf("\n],\n");started=0;output=0;} if(started && skip) printf(",\n"); if(output) {printf("%s",$2/1000); skip=1;} if($1 == "Frame") {output = 1; started=1;}}' >> $curr_dir/BIDS/$image:r:r".json"

					echo \"FrameReferenceTime\": [ >> $curr_dir/BIDS/$image:r:r".json"
					cat $curr_dir/4DFP/$image:r:r".4dfp.img.rec" | awk 'BEGIN{output = 0; started = 0; skip = 0}{if($2 == "Missing" && started){printf("\n],\n");started=0;output=0;} if(started && skip) printf(",\n"); if(output) {printf("%s",$3); skip=1;} if($1 == "Frame") {output = 1; started=1;}}' >> $curr_dir/BIDS/$image:r:r".json"

					cat $PP_SCRIPTS/PET/misc/template_2.json >> $curr_dir/BIDS/$image:r:r".json"

				end
			cd ..
		popd
	end
popd

