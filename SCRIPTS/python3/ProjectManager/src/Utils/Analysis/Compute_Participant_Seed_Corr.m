function Compute_Participant_Seed_corr(subject_dir, output_path)

    pp_scripts = getenv('PP_SCRIPTS');
    
    %Add the matlab scripts folder to the file path.
    addpath(fullfile(pp_scripts, 'matlab_scripts'));
       
    Network_Groupings = {1:25;26:55;56:60;61:74;75:87;88:144;145:149;150:180;181:205;206:223;224:251;252:260;261:271;272:298};
    Network_Names = {'Unassigned';'SM';'SM_lat';'CO';'AUD';'DMN';'MEM';'VIS';'FP';'SAL';'SUBCort';'VAN';'DAN';'CEREB'};
    
    Parcellation_Filename = fullfile(pp_scripts, 'Parcellation/BigBrain298/BigBrain298__MNI_allROIs_MNI_333_target.nii.gz');

    [path, sub_ses] = fileparts(subject_dir);

    try
        if(exist([ subject_dir '/Functional/Volume/' sub_ses '_rsfMRI_uout_resid_bpss_sm7.nii.gz'], 'file'))
            BOLD_TimeSeries_NiftiFilename = [ subject_dir '/Functional/Volume/' sub_ses '_rsfMRI_uout_resid_bpss_sm7.nii.gz'];
        else
            BOLD_TimeSeries_NiftiFilename = [ subject_dir '/Functional/Volume/' sub_ses '_rsfMRI_uout_bpss_resid_sm7.nii.gz'];
        end
        
        tmask_filename = [ subject_dir '/Functional/TemporalMask/rsfMRI_tmask.txt'];
        
        [SeedCorrMatrix, Seed_Timeseries] = volume_seed_corr(BOLD_TimeSeries_NiftiFilename, Parcellation_Filename, tmask_filename);
        
        if(sum(isnan(reshape(SeedCorrMatrix,1,[]))) > 0)
            disp('has nans');
        end
        
        Network_Composite = zeros(length(Network_Groupings),length(Network_Groupings));
        for j = 1:length(Network_Groupings)
            for k = 1:length(Network_Groupings)
                values = SeedCorrMatrix(Network_Groupings{j},Network_Groupings{k});
                values = reshape(values,1,[]);
                
                Network_Composite(j,k) = nanmean(values(values ~= 1));
            end
        end

        save(output_path,'SeedCorrMatrix','Seed_Timeseries','tmask_filename','Network_Composite');
    catch ME
        disp(strcat('Could not compute volume seed correlations for ', sub_ses));
    end
end
