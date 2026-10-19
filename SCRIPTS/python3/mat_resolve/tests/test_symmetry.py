"""
Tests for mat_resolve.symmetry
================================
Checks that the symmetry-error reporter produces correct values for
both the ideal case (zero error) and a case with known injected errors.
"""

# pylint: disable=invalid-name

import numpy as np
import pytest
from scipy.spatial.transform import Rotation

from mat_resolve.symmetry import compute_symmetry_error


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_random_rigid(rng, max_angle_deg=20.0, max_trans_mm=15.0):
    """Return a random 4x4 rigid-body transform matrix."""
    angle = rng.uniform(0, np.deg2rad(max_angle_deg))
    axis = rng.standard_normal(3)
    axis /= np.linalg.norm(axis)
    R = Rotation.from_rotvec(angle * axis).as_matrix()
    t = rng.uniform(-max_trans_mm, max_trans_mm, 3)
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = t
    return T


def make_consistent_transforms(image_names, T_list):
    """
    Build a fully consistent transform dict from a list of transforms
    T_list[k] = T_{0 -> k} (maps the reference image 0 into image k's space,
    i.e. x_k = T_list[k] @ x_0 -- the FSL convention, x_fixed = M @ x_moving,
    with moving=0, fixed=k).

    The predicted pairwise transform from image j to image i, satisfying
    x_i = T_{j->i} @ x_j, is:
        T_{j->i} = T_{0->i} @ inv(T_{0->j})
    """
    transforms = {}
    n = len(image_names)
    for i in range(n):
        for j in range(n):
            if i == j:
                continue
            T_ji = T_list[i] @ np.linalg.inv(T_list[j])
            transforms[(image_names[j], image_names[i])] = T_ji
    return transforms


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_perfect_consistency_zero_error(capsys):
    """
    Perfectly consistent transforms must report near-zero symmetry error.

    We construct transforms that satisfy all loop constraints exactly, so
    the reported RMS errors should be at floating-point precision.
    """
    rng = np.random.default_rng(0)
    names = ["A", "B", "C", "D"]
    # T_list[k] maps image k to the reference (image 0 = identity)
    T_list = [np.eye(4)] + [make_random_rigid(rng) for _ in range(3)]
    transforms = make_consistent_transforms(names, T_list)

    compute_symmetry_error(transforms, names)
    captured = capsys.readouterr().out

    # Extract the reported rotation RMS values and check they are tiny
    import re  # pylint: disable=import-outside-toplevel

    rot_values = re.findall(r"Rotation\s+RMS\s*:\s*([\d.e+-]+)\s*deg", captured)
    for val_str in rot_values:
        assert float(val_str) < 1e-6, f"Expected near-zero rot RMS, got {val_str}"

    trans_values = re.findall(r"Translation RMS\s*:\s*([\d.e+-]+)\s*mm", captured)
    for val_str in trans_values:
        assert float(val_str) < 1e-6, f"Expected near-zero trans RMS, got {val_str}"


def test_output_contains_expected_sections(capsys):
    """Symmetry report must include pair and triple sections for N=4, but no
    quadruple section unless explicitly requested (it's off by default)."""
    rng = np.random.default_rng(1)
    names = ["W", "X", "Y", "Z"]
    T_list = [np.eye(4)] + [make_random_rigid(rng) for _ in range(3)]
    transforms = make_consistent_transforms(names, T_list)

    compute_symmetry_error(transforms, names)
    out = capsys.readouterr().out

    assert "pairs" in out
    assert "triples" in out
    assert "quadruples" not in out


def test_quadruples_reported_when_requested(capsys):
    """quadruples=True must add a quadruple section for N=4."""
    rng = np.random.default_rng(1)
    names = ["W", "X", "Y", "Z"]
    T_list = [np.eye(4)] + [make_random_rigid(rng) for _ in range(3)]
    transforms = make_consistent_transforms(names, T_list)

    compute_symmetry_error(transforms, names, quadruples=True)
    out = capsys.readouterr().out

    assert "pairs" in out
    assert "triples" in out
    assert "quadruples" in out


def test_only_pairs_reported_for_n2(capsys):
    """For N=2 only pair errors should be reported (no triples/quadruples)."""
    names = ["A", "B"]
    T = make_random_rigid(np.random.default_rng(2))
    transforms = {
        ("A", "B"): T,
        ("B", "A"): np.linalg.inv(T),
    }

    compute_symmetry_error(transforms, names)
    out = capsys.readouterr().out

    assert "pairs" in out
    assert "triples" not in out
    assert "quadruples" not in out


def test_only_pairs_and_triples_for_n3(capsys):
    """For N=3 only pair and triple errors should be reported."""
    rng = np.random.default_rng(3)
    names = ["A", "B", "C"]
    T_list = [np.eye(4)] + [make_random_rigid(rng) for _ in range(2)]
    transforms = make_consistent_transforms(names, T_list)

    compute_symmetry_error(transforms, names)
    out = capsys.readouterr().out

    assert "pairs" in out
    assert "triples" in out
    assert "quadruples" not in out


def test_inconsistent_transforms_nonzero_error(capsys):
    """
    Randomly perturbed transforms should give non-zero symmetry errors.
    """
    rng = np.random.default_rng(4)
    names = ["A", "B", "C"]
    T_list = [np.eye(4)] + [make_random_rigid(rng) for _ in range(2)]
    transforms = make_consistent_transforms(names, T_list)

    # Perturb one transform to break consistency
    key = ("A", "B")
    noise = make_random_rigid(rng, max_angle_deg=5.0, max_trans_mm=2.0)
    transforms[key] = transforms[key] @ noise

    compute_symmetry_error(transforms, names)
    out = capsys.readouterr().out

    rot_values = [
        float(v)
        for v in __import__("re").findall(
            r"Rotation\s+RMS\s*:\s*([\d.e+-]+)\s*deg", out
        )
    ]
    assert any(v > 0.01 for v in rot_values), (
        "Expected non-zero rotation error after perturbation"
    )
