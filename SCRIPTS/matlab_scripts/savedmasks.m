function [mask,threshold]=savedmasks(masktype)
% This just allows me to use handles to references different masks saved in
% various places.
% Josh Siegel 8/8/2012
threshold=1;
switch masktype
    case 'graymatter'
        mask = read_4dfpimg('/data/nil-bluearc/corbetta/Hacker/ROIs/Cortex_Mask_20k/N21_aparc+aseg_GMctx_on_711-2V_333_avg.4dfp.img');
        threshold=0.3;
    case 'wholebrain'
        mask = read_4dfpimg('/data/petsun43/data1/atlas/glm_atlas_mask_333_b100.4dfp.img');
    case 'basalganglia'        
        mask = read_4dfpimg('/data/nil-bluearc/corbetta/Studies/Functional_Connectivity_Stroke_R01_HD061117-05A2/Analysis/callejasa/FC_Basal_Ganglia_Patients/ROIs_Barnes5n2ndry/DCsum_ROI333.4dfp.img');
    case '0.3symmetric'
        mask = read_4dfpimg('/data/nil-bluearc/corbetta/Studies/DysFC/ROIs/N21_aparc+aseg+GMctx_711-2V_333_avg_pos_mask_t0.3_symmetric.4dfp.img');        
    otherwise
        mask = masktype; 
        [~,masktype,~] = fileparts(masktype);
end
end