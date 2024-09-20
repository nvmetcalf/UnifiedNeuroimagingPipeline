ConvertE7Session.csh:

Usage:    ConvertE7Session.csh <DICOM guide(txt)> <PID> <Session label> <Output directory>
 e.g.:    ConvertE7Session.csh v2.txt NP995_10 _V2 V2
A model DICOM guide follows:
--------------------------------
MPR	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/SCANS/114/DICOM
MRAC	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/SCANS/31/DICOM
CT	PPGdata/rawdata/NP995_10_CT_V1/SCANS/2/DICOM
FDG	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/RESOURCES/RawData/NP995_10_mMR_v2RawData/NP995_10_mMR_v2RawData/NP995_10/CCIR-00500_CCIR-0055/Head_MRAC_PET_60min_
HO	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/RESOURCES/RawData/NP995_10_mMR_v2RawData/NP995_10_mMR_v2RawData/NP995_10/CCIR-00500_CCIR-0055/Head_HO1_HD_PET_Raw_	1
HO	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/RESOURCES/RawData/NP995_10_mMR_v2RawData/NP995_10_mMR_v2RawData/NP995_10/CCIR-00500_CCIR-0055/Head_HO2_HD_PET_Raw_	2
OO	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/RESOURCES/RawData/NP995_10_mMR_v2RawData/NP995_10_mMR_v2RawData/NP995_10/CCIR-00500_CCIR-0055/Head_OO1_HD_PET_Raw_	1
OO	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/RESOURCES/RawData/NP995_10_mMR_v2RawData/NP995_10_mMR_v2RawData/NP995_10/CCIR-00500_CCIR-0055/Head_OO2_HD_PET_Raw_	2
OC	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/RESOURCES/RawData/NP995_10_mMR_v2RawData/NP995_10_mMR_v2RawData/NP995_10/CCIR-00500_CCIR-0055/Head_OC1_HD_MRAC_Raw	1
OC	PPGdata/rawdata/NP995_10_mMR_v2/NP995_10_mMR_v2/RESOURCES/RawData/NP995_10_mMR_v2RawData/NP995_10_mMR_v2RawData/NP995_10/CCIR-00500_CCIR-0055/Head_OC2_HD_MRAC_Raw	2
--------------------------------

ConvertE7Session.csh takes DICOM subdirectories containing an individual's mprage, CT, a UTE UMAP, and PET images (currently only F18 FDG, and O15 water, oxygen, and carbon monoxide), copies them into local, properly sorted subdirectories, and creates attenuation corrected, dynamic images.
The subdirectory listings are stored in the DICOM guide text file, along with mode keywords and optional scan labels. The subdirectory paths are given relative to /cygdrive/z which resolves to /data/nil-bluearc/raichle.
The DIXON UMAP subdirectories in each local PET subdirectory are replaced with the UTE UMAP image, created by dcm_to_4dfp.
Once the local directories are set up, ConvertE7Session.csh uses RunJSRecon.csh to create uncorrected, single frame versions of each PET scan, labeled "NAC". These, along with the mprage are then fed to pet2atl_4dfp which attempts to register every scan to the 711-2B atlas.
The call to RunJSRecon.csh uses the "-uo" option to output a UMAP image based on the supplied UTE UMAP 4dfp. This image, and a copy of the CT image are fed to cusom_umap_4dfp to create a final version of the UMAP, which, once again, overwrites the PET umap subdirectory.
RunJSRecon.csh is run a second time with the modality-appropriate, dynamic, attenuation-correcting recon text files.
Among the files and subdirectories left in the working directory are the corrected PET images (labeled "AC"), and t4 files to transform them into mprage or atlas space.
There are also several resolve logs in the main working subdirectory and the resolve_t4 subdirectory that can be inspected for registration QC. Additionally there is a summary text file in resolve_t4 that contains inter-modal PEt registration QC information.




RunJSRecon.csh:

Usage:    RunJSRecon.csh <input directory> <recon text (F18dyn|O15dyn|O15AC|O15NAC)>
 e.g.:	RunJSRecon.csh FDG_V2 O15NAC.txt -uo NP995_10fdg_v2_umap -o NP995_10fdg_v2_NAC
 e.g.:	RunJSRecon.csh FDG_V2 F18dyn.txt -ui NP995_10fdg_v2_umap -o NP995_10fdg_v2_AC
 options
 -ui <umap(4dfp)>          overwrite umap .v file in umap subdirectory with supplied 4dfp
 -uo <umap(4dfp)>    save umap created by JSRecon12 as 4dfp in working directory
 -o  <output(4dfp)>  save converted image as 4dfp in working directory

RunJSRecon.csh is a wrapper for JSRecon12. It can be used to overwrite the stored UMAP, output the created UMAP, and output a 4dfp. The output images are created by sif_4dfp or IFhdr_to_4dfp, as appropriate.




custom_umap_4dfp:

Usage:    custom_umap_4dfp <(4dfp)input> <(4dfp)secondary umap> <outroot>
 e.g.:	custom_umap_4dfp NP995_10_ct_on_NP995_10_fdg_v2_NAC NP995_10_fdg_v2_umap NP995_10_fdg_v2_umap_flipz
 N.B.:	custom_umap_4dfp outputs a UMAP that must be flipped on the z axis before being used by E7 tools

custom_umap_4dfp applies a piecewise linear transform to the values of the supplied input CT image. It then fills in the gaps in coverage with the secondary UMAP.



