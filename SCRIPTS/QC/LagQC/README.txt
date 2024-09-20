Readme for resting state hemodynamic lag code.
© 2015 Washington University in St. Louis.
Author(s): Joshua Siegel, siegelj@wusm.wustl.edu, 240-506-3715
All Rights Reserved
No part of this work or any of its contents may be reproduced, copied, modified or adapted, without the prior written consent of the author(s).
Commercial use and distribution of the works is not allowed without express and prior written consent of Maurizio Corbetta, Joshua Siegel, or Washington University in St. Louis.
This matlac code runs cross-correlation based estimation of hemodynamic lags using resting fMRI timecourses that are either in nifti or 4dfp format. It is based on the method described in Siegel et al. 2015 (the manuscript is also included in this directory).
This code is provided ‘as is’ without any warranty. We cannot garuntee technical support for this code. For general questions please contact Josh siegel (siegelj@wustl.edu).
When publishing results using this code, please cite the following paper:
Siegel, J.S., Snyder, A.Z., Ramsey, L., Shulman, G.L., Corbetta, M., 2015. The effects of hemodynamic lag on functional connectivity and behavior after stroke. J Cereb Blood Flow Metab 
Recommended Preprocessing prior to running lag analysis:
Prior to running this, you should do the following preprocessing to your rfMRI data:
0) minimal timecourse cleanup (for example A) compensation for asynchronous slice acquisition using sinc interpolation; B) elimination of odd/even slice intensity differences resulting from inter- leaved acquisition; C) whole brain intensity normalization to achieve a mode value of 1000; D) spatial realignment within and across R-fMRI runs; and E) resampling to 3mm cubic voxels in atlas space including realignment and atlas transformation in one resampling step.) 
1) Atlas registration
2) Niusance regression (motion regressors, CSF regressors) - White matter and whole brain regressors should not be applied.
3) Bandpass filtering. 
4) You should generate a mask identifying high motion frames (as in Power et al 2012). 
3&4 will lower the 0-cross-correlation peak caused by shared noise making% it easier to identify hemodynamic lags. 
* Do not do global signal or white matter signal regression.
Lag Analysis Inputs:
1. A 'conc' file - this is a text file that lists all BOLD resting scans
2. A 'format' file - this is a text file that specifies high motion or DVAR frames that shouldbe excluded from the analysis.
Optional:
1. Lesion mask – it is important to exclude lesions from lag calculation where applicable.
2. Individually segmented gray matter mask – Right now gray-matter signal referenced lag is calculated using a group average gray mask. Individual masks marginally improve calculation of lags.
EXAMPLE:
An example case has been included to illustrate how the code works. This is a stroke patient, scanned 2 weeks after an ischemic stroke. Fun fact, this is the first patient that I calculated lags on. All necessary data for this subject, including 7 preprocessed resting fMRI scans, and a lesion mask, are located in ‘sampledata/’. You should be able to run the example using the wrapper script EXAMPLE_calculatelag.m. 
Primary function:
MapLag.m – generate a voxel-wise map of lagged cross-correlation relative to a reference signal. This reference signal can either be the homologue on the opposite hemisphere (switches.homotopic=1; recommended where possible as SNR is higher), or a global gray-matter reference signal (switches.homotopic=0). 
This function will produce 3 things:
* Output LL – lag laterality. This is a simple measure of left- versus right- hemisphere lag. Anything over 0.5s is suggestive of areas of substantial hemodynamic delays.
* A lag map image – Assuming switches.savepng = 1, this is a brain map of lags that will be generated and saved.
* A lag map – This will be a 4dfp or nifty (depending on input data type) image of lag measures relative to the reference signal in units of seconds. 
