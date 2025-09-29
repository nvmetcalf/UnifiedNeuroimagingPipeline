"""
Basic script to compute cerebral blood flow from multi-delay pCASL data

Uses methods described in:

    http://doi.org//10.1002/mrm.23103
    http://doi.org/10.1016/j.nicl.2013.06.017
"""

import argparse
import json
import nibabel as nib
import numpy as np
from scipy.interpolate import interp1d


def make_parser():
    """
    Constructs argument parser

    Returns
    -------
    parser : ArgumentParser
       Parser function
    """

    epilog = (
        "Units of output images are mL/hg/min for blood flow (cbf), "
        "seconds for weighted delay (wd) and arterial transit time (att), "
        "and mL/g for arterial blood volume (cbv_art)."
    )
    parser = argparse.ArgumentParser(
        description="Computes weighted CBF from multi-delay pCASL", epilog=epilog
    )
    parser.add_argument("asl", help="Nifti ASL image")
    parser.add_argument("json", help="BIDS JSON file describing ASL image")
    parser.add_argument("out", help="Root for output files")
    parser.add_argument(
        "-m0",
        help="Seperate m0 Nifti image. Otherwise uses first image with a PLD of 0",
    )
    parser.add_argument("-img_mask", help="Binary Nifti mask image")
    parser.add_argument(
        "-frame_mask", help="Text file of frames to include (1) or exclude (0)"
    )
    parser.add_argument(
        "-r1_a",
        help="Inverse of blood T1 relaxation time. Default is 0.61 Hz",
        default=0.61,
        type=float,
    )
    parser.add_argument(
        "-r1_t",
        help="Inverse of tissue T1 relaxation time. Default is 0.67 Hz",
        default=0.67,
        type=float,
    )
    parser.add_argument(
        "-alpha",
        help="Tagging efficiency. Default is 0.8",
        default=0.8,
        type=float,
    )
    parser.add_argument(
        "-tau",
        help="Duration of the labeling pulse. Default is 1.5 seconds",
        default=1.5,
        type=float,
    )
    parser.add_argument(
        "-lmbda",
        help="Blood/tissue water partition coefficient. Default is 0.9 g/mL",
        default=0.9,
        type=float,
    )
    parser.add_argument(
        "-ct", help="Images are control-tag instead of tag-control", action="store_true"
    )

    return parser


def save_img(out_path, data, mask, shape, affine):
    """
    Saves a nifti image given masked image data

    Parameters
    ----------
    out_path : string
        Path to save data to
    data : ndarray
        m x n array of image data to save
    mask : ndarray
        m x 1 boolean array of valid voxels
    shape : list
        3 x 1 list containing dimensions for output image
    affine : ndarray
        4 x 4 affine matrix for Nifti output image
    """

    # Figure out correct 2D dimensions
    if data.ndim == 2:
        flat_shape = [mask.shape[0], data.shape[1]]
    elif data.ndim == 1:
        flat_shape = [mask.shape[0], 1]
    else:
        raise RuntimeError("Dimensions of data must be either 1 or 2")

    img_data = np.zeros(flat_shape)
    img_data[mask, :] = data.reshape((data.shape[0], flat_shape[1]))
    img_nii = nib.Nifti1Image(img_data.reshape(shape), affine)

    img_nii.to_filename(out_path)


def divide_imgs(numerator, denominator):
    """
    Divide two images without raising divide by zero errors

    Parameters
    ----------
    numerator : ndarray
        Image to divide
    denominator : ndarray
        Image to divide by

    Returns
    -------
    quotient : ndarray
        Result of performing numerator / denominator

    Notes
    -----
    `numerator` and `denominator` must be the same shape
    """

    mask = denominator != 0
    quotient = np.zeros_like(denominator)
    quotient[mask] = numerator[mask] / denominator[mask]

    return quotient


def compute_perfs(img, plds, mask, ct=True):
    """
    Calculates average perfusion image for each post label delay

    Parameters
    ----------
    img : ndarray
        m x n array of asl data
    plds : ndarray
        n x 1 array of post label delays
    mask : ndarray
        n x 1 boolean array where True values are valid `plds`
    ct : bool
        Images are control, tag instead of tag, control

    Returns
    -------
    perfs : ndarray
        m x p array containing the average perfusion values for each unique delay in `pld`
    """

    # Loop through post label delays
    u_plds = np.unique(plds[plds != 0])
    perfs = np.zeros((img.shape[0], u_plds.shape[0]))
    for idx, pld in enumerate(u_plds):

        # Extract frames for current pld
        pld_mask = plds == pld
        pld_exclude_mask = np.repeat(
            np.logical_and(mask[pld_mask][0::2], mask[pld_mask][1::2]), 2
        )
        if np.sum(pld_exclude_mask) == 0:
            raise RuntimeError(f"Not useable frames for PLD {pld}")

        # Get mean for current pld
        pld_data = img[..., pld_mask][..., pld_exclude_mask]
        pld_mean = np.mean(pld_data[:, 1::2] - pld_data[..., 0::2], axis=1)
        if ct is True:
            pld_mean *= -1
        perfs[:, idx] = pld_mean

    return perfs


def weighted_delay_to_att(
    weighted_delay, plds, att_range=(0.7, 3), r1_a=0.61, r1_t=0.67, tau=1.5
):
    """
    Computes arterial transit time (att) using weighted delay images using the method
    described by http://doi.org//10.1002/mrm.23103

    Parameters
    ----------
    weighted_delay : ndarray
        m x 1 array containing weighted delays (sec)
    plds : ndarray
        n x 1 array of unique post label delays
    att_range : tuple
        Minimum and maximum arterial time
    r1_a : float
        Relaxation rate of arterial blood (Hz)
    r1_t: float
        Relaxation rate of brain tissue (Hz)
    tau : float
        Labeling duration

    Returns
    -------
    att : ndarray
        m x 1 estimates of arterial transit time (sec)
    """

    # Simulate the relationship between weighted delay and arterial transit time
    atts = np.linspace(att_range[0], att_range[1], 100)
    perf_sim = np.exp(-atts[:, np.newaxis] * r1_a) * (
        np.exp(-np.maximum(plds - atts[:, np.newaxis], 0) * r1_t)
        - np.exp(-np.maximum(tau + plds - atts[:, np.newaxis], 0) * r1_t)
    )
    weighted_sim = divide_imgs(
        np.sum(plds * perf_sim, axis=1), np.sum(perf_sim, axis=1)
    )

    # Compute arterial transit time using simulated relationship
    att_img = interp1d(
        weighted_sim,
        atts,
        kind="linear",
        fill_value=(att_range[0], att_range[1]),
        bounds_error=False,
    )(weighted_delay)

    return att_img


def pcasl_cbf(perf, att, m0, plds, alpha=0.8, lmbda=0.9, r1_a=0.61, tau=1.5):
    """
    Computes cerebral blood flow form multi-delay ASL data using the method described by
    http://doi.org/10.1016/j.nicl.2013.06.017

    Parameters
    ----------
    perf : ndarray
        m x n tag - control image for each post label delay
    att : ndarray
        m x 1 arterial transit time image (sec)
    m0 : ndarray
        m x 1 equilibrium magnetization image
    plds : ndarray
        n x 1 array of post label delays (sec)
    lmbda : float
        Blood brain partition coefficient for water
    r1_a : float
        Relaxation rate of arterial blood (Hz)
    r1_t: float
        Relaxation rate of brain tissue (Hz)
    tau : float
        Labeling duration

    Returns
    -------
    cbf : ndarray
        m x n cerebral blood flow image (mL/hg/min) for each post label delay
    """

    # Use delay to calculate cbf
    cbf_numer = lmbda * perf * r1_a
    cbf_denom = (
        2
        * alpha
        * m0[:, np.newaxis]
        * (
            np.exp(
                (np.minimum(att[:, np.newaxis] - plds, 0) - att[:, np.newaxis]) * r1_a
            )
            - np.exp(-(tau + plds) * r1_a)
        )
    )

    return divide_imgs(cbf_numer, cbf_denom) * 60 * 100


def main():
    """
    Run CBF calculation
    """

    # Get user input
    parser = make_parser()
    args = parser.parse_args()

    # Load in asl data
    asl_nii = nib.load(args.asl)
    asl_img = asl_nii.get_fdata().reshape((-1, asl_nii.shape[-1]))

    # Load in spatial mask
    valid_mask = np.abs(asl_img).min(axis=1) != 0
    if args.img_mask is None:
        mask_img = np.logical_and(np.ones(asl_img.shape[0], dtype=bool), valid_mask)
    else:
        mask_nii = nib.load(args.img_mask)
        mask_img = np.logical_and(mask_nii.get_fdata().flatten() == 1, valid_mask)
    asl_masked = asl_img[mask_img, :]

    # Load in temporal mask
    if args.frame_mask is None:
        frame_mask = np.ones(asl_img.shape[1], dtype=bool)
    else:
        frame_mask = np.loadtxt(args.frame_mask) == 1

    # Load in json to get delay timings
    with open(args.json, "r", encoding="utf-8") as j_id:
        j_data = json.load(j_id)

    # Get m0
    plds = np.array(j_data["PostLabelingDelay"])
    if args.m0 is not None:
        m0_nii = nib.load(args.m0)
        m0_img = m0_nii.get_fdata().flatten()[mask_img]
    elif j_data["M0Type"] == "Included":
        m0_idx = np.argmax(plds == 0)
        if frame_mask[m0_idx] is False:
            raise RuntimeError(f"M0 frame is exluded in {args.frame_mask}")
        m0_img = asl_img[mask_img, :][:, m0_idx]
    else:
        msg = "Must specify a seperate m0 or have one included in the sequence"
        raise RuntimeError(msg)

    # Get average perfusion image for each pld
    perf_img = compute_perfs(asl_masked, plds, frame_mask, ct=args.ct)

    # Compute weighted delay image
    u_plds = np.unique(plds[plds > 0])
    weighted_img = divide_imgs(
        np.sum(u_plds * perf_img, axis=1), np.sum(perf_img, axis=1)
    )
    save_img(
        f"{args.out}_wd.nii.gz",
        weighted_img,
        mask_img,
        asl_nii.shape[0:3],
        asl_nii.affine,
    )

    # Use weighted delay to get cbf
    att_img = weighted_delay_to_att(
        weighted_img,
        u_plds,
        att_range=(0.7, 3),
        r1_a=args.r1_a,
        r1_t=args.r1_t,
        tau=args.tau,
    )
    save_img(
        f"{args.out}_att.nii.gz", att_img, mask_img, asl_nii.shape[0:3], asl_nii.affine
    )

    # Compute cbf at each pld
    cbf_img = pcasl_cbf(
        perf_img,
        att_img,
        m0_img,
        u_plds,
        alpha=args.alpha,
        lmbda=args.lmbda,
        r1_a=args.r1_a,
        tau=args.tau,
    )
    save_img(
        f"{args.out}_cbf.nii.gz",
        cbf_img,
        mask_img,
        list(asl_nii.shape[0:3]) + list(u_plds.shape[0:1]),
        asl_nii.affine,
    )

    # Save average cbf
    cbf_mean_img = cbf_img.mean(axis=1)
    save_img(
        f"{args.out}_cbf_mean.nii.gz",
        cbf_mean_img,
        mask_img,
        asl_nii.shape[0:3],
        asl_nii.affine,
    )

    # Save arterial blood volume
    save_img(
        f"{args.out}_cbv_art.nii.gz",
        cbf_mean_img * att_img / 60 / 100,
        mask_img,
        asl_nii.shape[0:3],
        asl_nii.affine,
    )

    # Save arguments to file
    with open(f"{args.out}_args.json", "w", encoding="utf-8") as f:
        json.dump(args.__dict__, f, indent=2)


if __name__ == "__main__":
    main()
