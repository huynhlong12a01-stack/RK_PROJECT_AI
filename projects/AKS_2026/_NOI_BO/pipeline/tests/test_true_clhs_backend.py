"""Synthetic smoke tests for the CRAN-clhs adapter and fallback metadata."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import numpy as np


PIPELINE = Path(__file__).resolve().parents[1]
ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(PIPELINE))

from true_clhs_backend import (  # noqa: E402
    fallback_metadata,
    method_metadata,
    select_true_clhs_core,
)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    rscript = shutil.which("Rscript")
    if not rscript:
        raise AssertionError("Rscript is required for the true-cLHS smoke test.")
    rng = np.random.default_rng(20260714)
    n = 600
    features = rng.normal(size=(n, 5))
    # A widely spaced synthetic grid makes the external spacing check exact and
    # isolates backend determinism from field geometry.
    coords = np.column_stack(
        [np.arange(n, dtype=float) * 250.0, (np.arange(n) % 17) * 500.0]
    )
    soils = np.resize(np.asarray([1, 2, 3], dtype=int), n)
    labels = {1: "Xa", 2: "Fa", 3: "Other"}
    selected_runs = []
    metadata_runs = []
    base = ROOT / ".tmp" / "true_clhs_backend_test"
    base.mkdir(parents=True, exist_ok=True)
    for run in (1, 2):
        selected, metadata = select_true_clhs_core(
            features=features,
            coords=coords,
            soils=soils,
            soil_labels=labels,
            sample_size=30,
            seed=42,
            minimum_spacing_m=100.0,
            iterations=500,
            restarts=2,
            use_cpp=True,
            auto_install=False,
            repository="https://cloud.r-project.org",
            weights={"numeric": 1.0, "factor": 1.0, "correlation": 1.0},
            r_executable=rscript,
            r_script=PIPELINE / "run_true_clhs.R",
            work_dir=base / f"run_{run}",
            qa_dir=base / f"run_{run}" / "qa",
            root=ROOT,
        )
        selected_runs.append(selected)
        metadata_runs.append(metadata)
    require(selected_runs[0] == selected_runs[1], "Fixed seed is not deterministic.")
    metadata = metadata_runs[0]
    require(metadata["backend_used"] == "r_clhs_cran", "Wrong backend identity.")
    require(metadata["package"]["name"] == "clhs", "Package provenance missing.")
    require(metadata["soil_type"]["representation"] == "categorical_factor", "Soil Type is not categorical.")
    require(metadata["coordinates_in_clhs_objective"] is False, "Coordinates leaked into cLHS objective.")
    require(metadata["multi_start_selection"]["no_post_optimisation_point_replacement"] is True, "Core was post-processed.")
    true_identity = method_metadata(metadata)
    require(true_identity["is_original_clhs_optimizer"] is False, "Hybrid design was labelled pure original cLHS.")
    require(true_identity["is_original_clhs_optimizer_core"] is True, "True core was under-claimed.")
    require(true_identity["is_pure_original_clhs_design"] is False, "Hybrid FULL was labelled pure cLHS.")
    require(true_identity["original_clhs_applies_to_roles"] == ["clhs_core"], "Role scope missing.")

    fallback = fallback_metadata(
        seed=42,
        quotas={1: 20, 2: 7, 3: 3},
        soil_labels=labels,
        reason="synthetic_missing_package",
    )
    fallback_identity = method_metadata(fallback)
    require(fallback_identity["is_original_clhs_optimizer"] is False, "Fallback was over-claimed.")
    require(fallback_identity["is_original_clhs_optimizer_core"] is False, "Fallback core was over-claimed.")
    require(fallback_identity["is_pure_original_clhs_design"] is False, "Fallback was labelled pure cLHS.")
    require(fallback["fallback_reason"] == "synthetic_missing_package", "Fallback reason lost.")
    print("True-cLHS backend smoke test passed: deterministic, categorical soil, truthful fallback.")


if __name__ == "__main__":
    main()
