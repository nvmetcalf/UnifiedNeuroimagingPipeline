import sys
import numpy as np
import nibabel as nib

wmparc_name = sys.argv[1]
gtmseg_name = sys.argv[2]
out_name = sys.argv[3]

wmparc = nib.load(wmparc_name).get_data().astype(int)
waff = nib.load(gtmseg_name).affine

gtmseg = nib.load(gtmseg_name).get_data().astype(int)
gaff = nib.load(gtmseg_name).affine

if not np.allclose(waff, gaff):
    raise

mask = np.zeros_like(wmparc)
for label in (2, 41, 5001, 5002):
    mask = np.logical_or(mask, gtmseg==label)
mask = np.logical_and(mask, wmparc!=0)

gtmseg = np.where(mask, wmparc, gtmseg)

out = nib.Nifti1Image(gtmseg, gaff)
nib.save(out, out_name)

