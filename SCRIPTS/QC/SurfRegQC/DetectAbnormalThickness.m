function [ AbnormalVerticies ] = DetectAbnormalThickness( ThicknessSurface, Age, AgeSearchRange )
%DetectAbnormalThickness classifies verticies in a metric as too thick or
%thin based on the age of the brain
%   Given a hemisphere thickness metric surface this function will load
%   other thickenss surfaces of the same hemisphere (based on the .L. or 
%   .R. in the filename), compute a "normal" range of thickness for each
%   vertex, and classify each verted in the input as either "normal" or
%   "abnormal". Normal verticies equal 0 and abnormal vertices equal 1. If
%   AgeSearchRange is set, then the surfaces cooresponding to age given +/-
%   AgeSearchRange will be used for determining the normal thichkness.
%   Default is +/- 5 years.

    %read in the environment so we know where to look for the comparison
    %thichness surfaces
    QC_DIR = [getenv('PP_SCRIPTS') '/SurfacePipeline/QC_scripts/SurfRegQC/CorticalThicknessSurfaces'];

    %the thickness surfaces are organized by age (each folder contains the
    %surfaces for that age).
    if(~exist('AgeSearchRange'))
        AgeSearchRange = 5;
    end

    
end

