"""Offline regression for strict minimum-spacing acceptance."""

from __future__ import annotations

import inspect
import sys
from pathlib import Path

import numpy as np


PIPELINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PIPELINE))

import design_samples  # noqa: E402
import design_samples_clhs as engine  # noqa: E402


def main():
    signature = inspect.signature(design_samples.select_lhs_for_group)
    assert "minimum_spacing_m" in signature.parameters
    engine.MIN_SPACING_M = 100.0

    coords = np.asarray([[0.0, 0.0], [100.0, 0.0], [250.0, 0.0]])
    accepted = engine._core_spacing_metrics([0, 1, 2], coords)
    assert accepted["minimum_spacing_target_met"] is True
    assert accepted["spacing_violation_pairs"] == 0

    rejected_coords = np.asarray([[0.0, 0.0], [99.0, 0.0], [250.0, 0.0]])
    rejected = engine._core_spacing_metrics([0, 1, 2], rejected_coords)
    assert rejected["minimum_spacing_target_met"] is False
    assert rejected["spacing_violation_pairs"] == 1
    assert rejected["minimum_pair_distance_m"] == 99.0

    adapter = (PIPELINE / "true_clhs_backend.py").read_text(encoding="utf-8")
    r_backend = (PIPELINE / "run_true_clhs.R").read_text(encoding="utf-8")
    assert "the core is rejected before publication" in adapter
    assert "No CRAN-clhs restart met minimum_spacing_m" in r_backend
    print("Minimum-spacing fail-closed regression passed.")


if __name__ == "__main__":
    main()
