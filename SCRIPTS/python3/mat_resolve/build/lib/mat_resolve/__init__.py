"""
mat_resolve
===========
Average pairwise FSL rigid-body registration matrices into a self-consistent
set of transforms mapping each image to a common resolved space.

Public API
----------
The primary entry point is the CLI::

    python -m mat_resolve --folder ./transforms --output resolved

Key submodules:

- :mod:`mat_resolve.rigid_math`  — quaternion math and analytical Jacobians
- :mod:`mat_resolve.symmetry`    — pre-optimisation consistency diagnostics
- :mod:`mat_resolve.cli`         — command-line interface and main loop
"""

__version__ = "0.1.0"
