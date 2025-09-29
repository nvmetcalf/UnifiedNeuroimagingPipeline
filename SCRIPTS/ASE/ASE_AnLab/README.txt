This software is designed for OEF calculation from the asymmetric spin-echo sequence developed by Hongyu An et al. If you find this software is helpful, please consider citing the following publications:

H. An, W. Lin - Quantitative measurements of cerebral blood oxygen saturation using magnetic resonance imaging. J Cereb Blood Flow Metab, 2000; 20: 1225-1236.

H. An, W. Lin - Impact of intravascular signal on quantitative measures of cerebral oxygen extraction and blood volume under normo- and hypercapnic conditions using an asymmetric spin-echo approach. Magn Reson Med, 2003; 50: 708-716.

Usage Instructions:
Use SPM to obtain the GM, WM and CSF probability maps and brain masks for the T1 images (in the ../T1 folder). 
The script temp_cal_t1.m will run the SPM segmentation for all subjects in the Original folder. 
Please update the spm path in temp_cal_t1.m and change spm_path_hard to where the spm12b is located in run_spm_seg_brain_mpr_original_header.m. 

Use temp_cal_ase.m as a reference for performing calculations.
Store the original NIfTI files (directly converted from DICOM) in a folder named Original within the ASE directory (e.g., ../ASE/Original).
The script temp_cal_ase.m will run calculations for all subjects in the Original folder.

Use temp_cal_ase_pv.m to calculate OEF with partial volume correction. The files named _OEF_gm.nii.gz, _OEF_wm.nii.gz, and _OEF_combined.nii.gz are the OEF maps (after partial volume correction) in GM, WM, and combined (after removing CSF).   

Recommendations for Using Computation Results:
To obtain reliable OEF values, consider using a large region of interest (ROI), such as gray matter or white matter across the whole brain.  There is an Error file saved for each subject (Error_wm, Error_gm and Error_combined for PVC fitting). When extracting the OEF value from an ROI, please use only the voxels where the fitting error is less than 30 (from the Error file).  For the PVC results, it is suggested to extract values from the voxels with a WM or GM probability greater than 0.5 for WM or GM ROIs using the probability maps(looking for prob_wm.nii.gz and prob_gm.nii.gz files). If your ROI includes both GM and WM, please use combined OEF and fitting error valeus from the voxels with a tissue probability greater than 0.5 (prob_wm + prob_gm). 
 
For any questions or feedback, please contact Hongyu An at hongyuan@wustl.edu.

Updated: 2025/02/26

