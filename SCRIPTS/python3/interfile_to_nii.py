#!/usr/bin/env python3

import json
import argparse
import re
from pathlib import Path

import numpy as np
import nibabel as nib


def parse_interfile_header(header_path):
    meta = {}
    raw_lines = []

    with open(header_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            raw_lines.append(line.rstrip("\n"))
            s = line.strip()

            if not s or s.startswith(";"):
                continue

            if s.upper().startswith("!INTERFILE"):
                meta["!INTERFILE"] = True
                continue

            if ":=" in s:
                key, value = s.split(":=", 1)
                key = key.strip()
                value = value.strip()

                if ";" in value:
                    value = value.split(";", 1)[0].strip()

                meta[key] = value

    meta["_raw_lines"] = raw_lines
    return meta


def normalize_key(key):
    return re.sub(r"\s+", " ", key.strip().lower())


def build_normalized_meta(meta):
    return {normalize_key(k): v for k, v in meta.items()}


def get_first(meta_norm, keys, default=None):
    for k in keys:
        nk = normalize_key(k)
        if nk in meta_norm:
            return meta_norm[nk]
    return default


def try_number(x):
    if x is None:
        return None
    if isinstance(x, (int, float)):
        return x

    s = str(x).strip()
    m = re.match(r"^([+-]?\d+(\.\d+)?([eE][+-]?\d+)?)", s)
    if m:
        token = m.group(1)
        try:
            if "." in token or "e" in token.lower():
                return float(token)
            return int(token)
        except Exception:
            return x
    return x


def get_matrix_sizes(meta_norm):
    dims = []
    for i in range(1, 8):
        v = get_first(meta_norm, [
            f"matrix size [{i}]",
            f"!matrix size [{i}]",
            f"matrix size[{i}]",
            f"!matrix size[{i}]",
        ])
        if v is not None:
            dims.append(int(try_number(v)))

    if len(dims) < 3:
        raise ValueError(f"Could not determine at least 3 matrix dimensions, got {dims}")

    return dims


def get_voxel_sizes(meta_norm, ndim=3):
    """
    Read spatial voxel sizes in mm.
    Prefer scaling factor mm/pixel fields.
    For z, also try slice thickness or distance between slices.
    """
    sizes = []

    for i in range(1, min(ndim, 2) + 1):
        v = get_first(meta_norm, [
            f"scaling factor mm/pixel [{i}]",
            f"!scaling factor mm/pixel [{i}]",
            f"pixel size [mm] [{i}]",
            f"!pixel size [mm] [{i}]",
            f"mm/pixel [{i}]",
            f"!mm/pixel [{i}]",
            f"scale factor [{i}]",
            f"!scale factor [{i}]",
        ])
        sizes.append(float(try_number(v)) if v is not None else 1.0)

    if ndim >= 3:
        vz = get_first(meta_norm, [
            "scaling factor mm/pixel [3]",
            "!scaling factor mm/pixel [3]",
            "pixel size [mm] [3]",
            "!pixel size [mm] [3]",
            "mm/pixel [3]",
            "!mm/pixel [3]",
            "slice thickness",
            "!slice thickness",
            "distance between slices",
            "!distance between slices",
            "scale factor [3]",
            "!scale factor [3]",
        ])
        sizes.append(float(try_number(vz)) if vz is not None else 1.0)

    while len(sizes) < ndim:
        sizes.append(1.0)

    return sizes[:ndim]


def get_number_format(meta_norm):
    fmt = get_first(meta_norm, [
        "number format",
        "!number format",
        "data type",
        "image data type",
    ])
    if fmt is None:
        raise ValueError("Could not determine number format")

    fmt = str(fmt).strip().lower()

    bpp = get_first(meta_norm, [
        "number of bytes per pixel",
        "!number of bytes per pixel",
        "bytes per pixel",
    ])
    if bpp is None:
        raise ValueError("Could not determine bytes per pixel")
    bpp = int(try_number(bpp))

    if "float" in fmt and "double" not in fmt:
        mapping = {4: np.float32, 8: np.float64}
        if bpp not in mapping:
            raise ValueError(f"Unsupported float bytes per pixel: {bpp}")
        return mapping[bpp]

    if "double" in fmt:
        return np.float64

    if "unsigned" in fmt:
        mapping = {1: np.uint8, 2: np.uint16, 4: np.uint32, 8: np.uint64}
        if bpp not in mapping:
            raise ValueError(f"Unsupported unsigned integer bytes per pixel: {bpp}")
        return mapping[bpp]

    if "signed" in fmt or "integer" in fmt or "int" in fmt or "short" in fmt:
        mapping = {1: np.int8, 2: np.int16, 4: np.int32, 8: np.int64}
        if bpp not in mapping:
            raise ValueError(f"Unsupported signed integer bytes per pixel: {bpp}")
        return mapping[bpp]

    if "byte" in fmt:
        return np.uint8

    raise ValueError(f"Unsupported number format: fmt={fmt}, bpp={bpp}")


def get_byte_order(meta_norm):
    bo = get_first(meta_norm, [
        "imagedata byte order",
        "image data byte order",
        "!imagedata byte order",
        "!image data byte order",
    ], default="LITTLEENDIAN")

    bo = str(bo).strip().upper().replace(" ", "")
    if "LITTLE" in bo:
        return "<"
    if "BIG" in bo:
        return ">"
    raise ValueError(f"Unknown byte order: {bo}")


def find_data_file(header_path, meta_norm):
    header_path = Path(header_path)

    explicit = get_first(meta_norm, [
        "name of data file",
        "!name of data file",
        "data file",
    ])
    if explicit:
        explicit = explicit.strip().strip('"').strip("'")
        p = header_path.parent / explicit
        if p.exists() and p.is_file():
            return p.resolve()

    name = header_path.name
    candidates = []

    if name.lower().endswith(".i.hdr"):
        candidates.append(header_path.with_name(name[:-4]))

    if header_path.suffix.lower() == ".hdr":
        candidates.append(header_path.with_suffix(".i"))

    candidates.append(header_path.parent / header_path.stem)
    candidates.append(header_path.parent / (header_path.stem + ".i"))

    seen = set()
    unique_candidates = []
    for c in candidates:
        key = str(c.resolve(strict=False))
        if key not in seen:
            seen.add(key)
            unique_candidates.append(c)

    for c in unique_candidates:
        if c.exists() and c.is_file():
            return c.resolve()

    tried = "\n".join(f"  - {c}" for c in unique_candidates)
    raise FileNotFoundError(
        f"Could not locate associated data file for header:\n  {header_path}\nTried:\n{tried}"
    )


def get_data_offset(meta_norm):
    v = get_first(meta_norm, [
        "data offset in bytes",
        "!data offset in bytes",
    ], default=0)
    return int(try_number(v))


def get_rescale(meta_norm):
    slope = get_first(meta_norm, [
        "rescale slope",
        "data rescale slope",
        "quantification factor",
    ], default=1.0)

    intercept = get_first(meta_norm, [
        "rescale intercept",
        "data rescale intercept",
    ], default=0.0)

    return float(try_number(slope)), float(try_number(intercept))


def get_time_spacing(meta_norm):
    candidates = [
        "image duration",
        "!image duration",
        "frame duration",
        "!frame duration",
        "time between frames",
    ]
    for key in candidates:
        v = get_first(meta_norm, [key])
        if v is not None:
            n = try_number(v)
            if isinstance(n, (int, float)) and n > 0:
                return float(n)
    return 1.0


def reshape_image(vec, dims):
    """
    Empirically determined interpretation for Siemens HRRT reconstructed Interfile data:
    - reshape in Fortran order
    - flip axis 1: anterior-posterior
    - flip axis 2: superior-inferior
    Supports 3D and 4D.
    """
    if len(dims) == 3:
        x, y, z = dims
        arr = vec.reshape((x, y, z), order="F")
        arr = arr[:, ::-1, ::-1]
        return arr

    if len(dims) == 4:
        x, y, z, t = dims
        arr = vec.reshape((x, y, z, t), order="F")
        arr = arr[:, ::-1, ::-1, :]
        return arr

    raise ValueError(
        f"Unsupported dimensionality {len(dims)} with dims={dims}. "
        "This script currently supports only 3D and 4D."
    )


def load_interfile_image(header_path, manual_voxel_size=None, verbose=True):
    meta = parse_interfile_header(header_path)
    meta_norm = build_normalized_meta(meta)

    dims = get_matrix_sizes(meta_norm)
    ndim = len(dims)

    if ndim not in (3, 4):
        raise ValueError(
            f"Only 3D and 4D Interfile data are supported by this script, got dims={dims}"
        )

    header_voxel_sizes = get_voxel_sizes(meta_norm, 3)

    if manual_voxel_size is not None:
        if len(manual_voxel_size) != 3:
            raise ValueError("manual_voxel_size must contain exactly 3 values: X Y Z")
        spatial_voxel_sizes = [float(v) for v in manual_voxel_size]
        voxel_source = "manual_override"
    else:
        spatial_voxel_sizes = header_voxel_sizes
        voxel_source = "interfile_header"

    dtype = get_number_format(meta_norm)
    endian = get_byte_order(meta_norm)
    data_file = find_data_file(header_path, meta_norm)
    offset = get_data_offset(meta_norm)
    slope, intercept = get_rescale(meta_norm)
    time_spacing = get_time_spacing(meta_norm) if ndim == 4 else None

    dt = np.dtype(dtype).newbyteorder(endian)

    expected_voxels = int(np.prod(dims))
    expected_bytes = expected_voxels * dt.itemsize

    file_size = data_file.stat().st_size
    available = file_size - offset

    if verbose:
        print("=== Interfile read debug ===")
        print(f"Header file        : {header_path}")
        print(f"Data file          : {data_file}")
        print(f"Dimensions         : {dims}")
        print(f"Header voxel sizes : {header_voxel_sizes}")
        print(f"Using voxel sizes  : {spatial_voxel_sizes}")
        print(f"Voxel size source  : {voxel_source}")
        print(f"Dtype              : {dt}")
        print(f"Byte order         : {endian}")
        print(f"Offset bytes       : {offset}")
        print(f"Expected voxels    : {expected_voxels}")
        print(f"Expected bytes     : {expected_bytes}")
        print(f"Actual file size   : {file_size}")
        print(f"Available bytes    : {available}")
        if ndim == 4:
            print(f"Time spacing       : {time_spacing}")

    if manual_voxel_size is None and all(v == 1.0 for v in spatial_voxel_sizes):
        print("WARNING: voxel sizes defaulted to [1.0, 1.0, 1.0].")
        print("WARNING: header may be missing spatial scaling information.")
        print("WARNING: this can cause registration problems.")
        print("WARNING: consider using --voxel-size X Y Z")

    if available < expected_bytes:
        raise ValueError(
            "Binary file is smaller than expected from header.\n"
            f"Expected {expected_bytes} bytes after offset, found {available}.\n"
            "Possible causes:\n"
            "- wrong matrix size\n"
            "- wrong bytes per pixel\n"
            "- wrong number format\n"
            "- wrong data offset\n"
            "- header refers to a different data file\n"
            "- data are not stored as a simple image volume"
        )

    with open(data_file, "rb") as f:
        f.seek(offset)
        vec = np.fromfile(f, dtype=dt, count=expected_voxels)

    if vec.size != expected_voxels:
        raise ValueError(f"Read {vec.size} voxels but expected {expected_voxels}")

    arr = reshape_image(vec, dims)

    if slope != 1.0 or intercept != 0.0:
        arr = arr.astype(np.float32) * slope + intercept

    return arr, spatial_voxel_sizes, time_spacing, meta, data_file, dims, voxel_source, header_voxel_sizes


def make_affine(voxel_sizes):
    """
    Simple spacing-only affine.
    This preserves voxel size but does not encode full scanner-world geometry.
    """
    affine = np.eye(4, dtype=float)
    for i in range(min(3, len(voxel_sizes))):
        affine[i, i] = float(voxel_sizes[i])
    return affine


def save_nifti(arr, voxel_sizes, out_path, time_spacing=None):
    affine = make_affine(voxel_sizes)
    img = nib.Nifti1Image(arr, affine)

    if arr.ndim == 3:
        zooms = tuple(voxel_sizes[:3])
    elif arr.ndim == 4:
        if time_spacing is None:
            time_spacing = 1.0
        zooms = tuple(list(voxel_sizes[:3]) + [float(time_spacing)])
    else:
        raise ValueError(f"Unsupported array ndim={arr.ndim}")

    img.header.set_zooms(zooms)
    nib.save(img, str(out_path))


def build_json(meta, header_path, data_file, arr, voxel_sizes, dims, time_spacing,
               voxel_source, header_voxel_sizes, manual_voxel_size):
    meta_norm = build_normalized_meta(meta)

    out = {
        "ConversionSoftware": "hrrt_interfile_to_nifti",
        "ConversionSourceFormat": "Interfile",
        "AssumedScannerType": "Siemens HRRT",
        "ConversionNotes": (
            "Empirical Siemens HRRT Interfile interpretation: "
            "Fortran-order reshape with spatial axis 1 and 2 flips. "
            "Affine is spacing-only and may not encode full scanner-world geometry."
        ),
        "SourceHeaderFile": Path(header_path).name,
        "SourceDataFile": Path(data_file).name,
        "Dimensionality": int(arr.ndim),
        "HeaderMatrixSize": list(dims),
        "ImageSize": list(arr.shape),
        "VoxelSize": list(voxel_sizes[:3]),
        "VoxelSizeSource": voxel_source,
        "HeaderVoxelSize": list(header_voxel_sizes[:3]),
        "ManualVoxelSizeOverride": (
            list(manual_voxel_size) if manual_voxel_size is not None else None
        ),
        "ArrayInterpretation": (
            "reshape_xyz_order_F_then_flip_axis_1_and_2"
            if arr.ndim == 3
            else "reshape_xyzt_order_F_then_flip_spatial_axis_1_and_2"
        ),
        "ByteOrder": get_first(meta_norm, [
            "imagedata byte order",
            "image data byte order",
            "!imagedata byte order",
            "!image data byte order",
        ]),
        "NumberFormat": get_first(meta_norm, [
            "number format",
            "!number format",
            "data type",
            "image data type",
        ]),
        "BytesPerPixel": try_number(get_first(meta_norm, [
            "number of bytes per pixel",
            "!number of bytes per pixel",
            "bytes per pixel",
        ])),
        "RescaleSlope": try_number(get_first(meta_norm, [
            "rescale slope",
            "data rescale slope",
            "quantification factor",
        ], default=1.0)),
        "RescaleIntercept": try_number(get_first(meta_norm, [
            "rescale intercept",
            "data rescale intercept",
        ], default=0.0)),
        "PatientName": get_first(meta_norm, ["patient name", "!patient name"]),
        "PatientID": get_first(meta_norm, ["patient id", "!patient id"]),
        "StudyDate": get_first(meta_norm, ["study date", "!study date"]),
        "StudyTime": get_first(meta_norm, ["study time", "!study time"]),
        "Modality": get_first(meta_norm, ["modality", "!modality"]),
        "Radiopharmaceutical": get_first(meta_norm, [
            "radiopharmaceutical",
            "!radiopharmaceutical",
        ]),
        "Scanner": get_first(meta_norm, [
            "originating system",
            "!originating system",
            "manufacturer",
        ]),
        "InstitutionName": get_first(meta_norm, [
            "institution name",
            "!institution name",
        ]),
        "ProcessStatus": get_first(meta_norm, [
            "process status",
            "!process status",
        ]),
        "RawInterfileHeader": {
            k: v for k, v in meta.items() if not k.startswith("_")
        }
    }

    if arr.ndim == 4:
        out["FrameCount"] = int(arr.shape[3])
        out["TimeSpacing"] = float(time_spacing if time_spacing is not None else 1.0)

    return out


def default_output_paths(header_path, out_nii=None, out_json=None):
    header_path = Path(header_path)

    if out_nii is None:
        base = header_path.name
        if base.lower().endswith(".i.hdr"):
            stem = base[:-6]
        elif base.lower().endswith(".hdr"):
            stem = base[:-4]
        else:
            stem = header_path.stem
        out_nii = header_path.with_name(stem + ".nii.gz")
    else:
        out_nii = Path(out_nii)

    if out_json is None:
        if str(out_nii).endswith(".nii.gz"):
            out_json = Path(str(out_nii)[:-7] + ".json")
        else:
            out_json = out_nii.with_suffix(".json")
    else:
        out_json = Path(out_json)

    return out_nii, out_json


def convert_one(header_path, out_nii=None, out_json=None, manual_voxel_size=None, verbose=True):
    header_path = Path(header_path)

    arr, voxel_sizes, time_spacing, meta, data_file, dims, voxel_source, header_voxel_sizes = load_interfile_image(
        header_path,
        manual_voxel_size=manual_voxel_size,
        verbose=verbose,
    )

    out_nii, out_json = default_output_paths(header_path, out_nii, out_json)

    save_nifti(arr, voxel_sizes, out_nii, time_spacing=time_spacing)

    sidecar = build_json(
        meta=meta,
        header_path=header_path,
        data_file=data_file,
        arr=arr,
        voxel_sizes=voxel_sizes,
        dims=dims,
        time_spacing=time_spacing,
        voxel_source=voxel_source,
        header_voxel_sizes=header_voxel_sizes,
        manual_voxel_size=manual_voxel_size,
    )

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(sidecar, f, indent=2)

    return out_nii, out_json


def main():
    parser = argparse.ArgumentParser(
        description="Convert Siemens HRRT-like Interfile reconstructed image data to NIfTI"
    )
    parser.add_argument("header", help="Path to Interfile header file .hdr or .i.hdr")
    parser.add_argument("--out-nii", default=None, help="Output NIfTI path")
    parser.add_argument("--out-json", default=None, help="Output JSON path")
    parser.add_argument(
        "--voxel-size",
        nargs=3,
        type=float,
        metavar=("X", "Y", "Z"),
        default=None,
        help="Manually override voxel size in mm, e.g. --voxel-size 1.22 1.22 1.22",
    )
    parser.add_argument("--quiet", action="store_true", help="Suppress debug output")
    args = parser.parse_args()

    out_nii, out_json = convert_one(
        header_path=args.header,
        out_nii=args.out_nii,
        out_json=args.out_json,
        manual_voxel_size=args.voxel_size,
        verbose=not args.quiet,
    )

    print(f"Saved NIfTI: {out_nii}")
    print(f"Saved JSON : {out_json}")


if __name__ == "__main__":
    main()
