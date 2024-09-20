import sys
import numpy as np
import nibabel as nib
#from itertools import izip

wmparc_name = sys.argv[1]
out_name = sys.argv[2]

wmparc = nib.load(wmparc_name).get_fdata()
aff = nib.load(wmparc_name).affine

pwm = np.where(np.logical_and(wmparc>=3000, wmparc<5000), wmparc, 0)
out = pwm.copy()

def edges(x):
    for axis in range(x.ndim):
        s0 = axis*(slice(None),)+(slice(-1),)
        s1 = axis*(slice(None),)+(slice(1,None),)
        yield (x[s0], x[s1])

for (o0, o1), (p0, p1) in zip(edges(out), edges(pwm)):
    o0 += np.where(o0==0, p1, 0)
    o1 += np.where(o1==0, p0, 0)

out = np.where(np.logical_or(wmparc==5001, wmparc==5002), 0, out)

nib.save(nib.Nifti1Image(out, aff), out_name)
    
