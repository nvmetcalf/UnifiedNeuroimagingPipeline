%load PET
%load timing and decay information
%This matlab script replicates sum_pet_4dfp

% PET_Timeseries_Filename = '/data/nil-bluearc/vlassenko/Pipeline/Projects/Vision/InProcess/108032_PET2_20221003/dicom/108032_PET2_20221003_CCIR_0970_QuadPack_Adult_20221003125730_18.nii.gz'
% PET_Timings_Filename = '/data/nil-bluearc/vlassenko/Pipeline/scratch/Vision/108032_PET2_20221003/PET_temp/108032_PET2_20221003_CCIR_0970_QuadPack_Adult_20221003125730_18_PET_timings.txt' 
% PET_HalfLife = 123;
% PET_Output_Filename = '108032_PET2_20221003_CCIR_0970_QuadPack_Adult_20221003125730_18_sum.nii.gz'

function sum_pet(PET_Timeseries_Filename, PET_Timings_Filename, PET_HalfLife, PET_Output_Filename)
%=============================================

    PET = load_nifti(PET_Timeseries_Filename);
    PET_Timings = import_pet_timings(PET_Timings_Filename);

    %turn in to a vector where each timepoint is a row.
    PET_Timeseries = reshape(PET.vol, PET.dim(2) * PET.dim(3) * PET.dim(4), PET.dim(5))';

    % 
    % 		for (i = 0; i < dimension; i++) {				/* process and sum the pixels */
    % 			
    % 			if (decayCor > 0)  image3d[i] /= decayCor;		/* remove decay correction */
    % 			if (duration > 0)  image3d[i] *= duration;		/* scale by frame duration seconds */
    % 			
    % 			img[i] += image3d[i];
    % 			
    % 		}
    % 		frameCounter++;
    % 
    % 	   }  /* if k>= istart */
    % 	}  /* for k=0 */
    % 	

    %remove decay correction
    %scale by frame duration in seconds
    %sum all the frames
    TotalDuration = 0;
    for i = 1:length(PET_Timings(:,1))
        PET_Timeseries(i,:) = (PET_Timeseries(i,:)./PET_Timings(i,1)) .* PET_Timings(i,3);
        TotalDuration = TotalDuration + PET_Timings(i,3);
    end

    sum_PET_Timeseries = sum(PET_Timeseries);

    % /***********************************************/
    % /* Calculate decay correction for summed image */
    % /***********************************************/
    %         decayCor = 1;
    % 	if (halflife > 0){
    % 	
    % 		dc = 0.693147 / halflife;					/* decay constant = log(2)/halflife */	
    % 		numerator = durationTotal * dc;
    % 		right = 1 - exp((-1.0 * dc ) * durationTotal);
    % 		left = exp((-1.0 * dc) * startTime);
    % 		
    % 		decayCor = numerator / (left * right);
    % 		
    % 	}
    % 	if (USEFIRST==1)decayCor = decayCor_first;
    % 
    % 	printf("sum_pet_4dfp: frameCount=%d halflife=%.2f sec startTime=%.2f sec durationTotal=%.2f sec decayCor=%.5f\n",\
    % 		        frameCounter-1,halflife,startTime,durationTotal,decayCor);
    DecayConstant = log(2)/PET_HalfLife;

    DecayCorrection = (TotalDuration * DecayConstant)/( (exp((-1.0 * DecayConstant) * PET_Timings(1,4))) * (1 - exp((-1.0 * DecayConstant ) * TotalDuration)) );

    % /********************/
    % /* final processing */
    % /********************/
    % 	for (i = 0; i < dimension; i++) {
    % 		   if (durationTotal > 0) img[i] /= durationTotal;		/* reverse the duration scaleing */
    % 		   if (halflife > 0)      img[i] *= decayCor;			/* scale by the new decay correction */
    % 		   if (scaleFactor != 1.0)img[i] *= scaleFactor;		/* final scalefactor */
    % 	}
    % 	
    % 	fprintf (stdout, "Writing: %s\n", outfile);
    % 	if (ewrite (img, dimension, control, fp_out)) errw (program, outfile);

    sum_PET_Timeseries = (sum_PET_Timeseries ./ TotalDuration) .* DecayCorrection;

    PET.vol = reshape(sum_PET_Timeseries, PET.dim(2), PET.dim(3), PET.dim(4));
    PET.dim(5) = 1;

    save_nifti(PET,PET_Output_Filename);
