"""Adapter for the official CRAN ``clhs`` conditioned-LHS optimiser.

This module deliberately keeps the package boundary explicit.  The caller
provides an already valid candidate population inside the sampling support;
the R package selects the REDUCED core without any post-optimisation snapping
or replacement.  Spatial augmentation for the FULL plan remains the caller's
responsibility and must not be described as direct cLHS output.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


TRUE_METHOD_ID = "clhs_r_core_spatially_augmented_nested_design"
FALLBACK_METHOD_ID = "clhs_like_spatially_constrained_soil_stratified_lhs"


def method_metadata(backend_metadata: dict[str, Any]) -> dict[str, Any]:
    """Return truthful method identity for the backend that actually ran."""
    true_clhs = backend_metadata.get("backend_used") == "r_clhs_cran"
    if true_clhs:
        return {
            "method_id": TRUE_METHOD_ID,
            "method_family": "conditioned_latin_hypercube_with_spatial_augmentation",
            "method_label": (
                "CRAN clhs core in full-rank PCA space with categorical Soil Type; "
                "FULL adds spatial infill and short-lag support"
            ),
            "backend_used": "r_clhs_cran",
            "is_clhs_like": False,
            "is_original_clhs_optimizer": False,
            "is_original_clhs_optimizer_core": True,
            "is_pure_original_clhs_design": False,
            "original_clhs_applies_to_roles": ["clhs_core"],
            "spatial_augmentation_is_direct_clhs_output": False,
            "selection_objective": (
                "Conditioned Latin-hypercube objective optimised by CRAN clhs; "
                "multi-start choice first respects the declared spacing target."
            ),
            "scientific_scope": (
                "The cLHS core is a stochastic simulated-annealing solution, not "
                "a proof of a global optimum. FULL augmentation is a separate "
                "spatial-design step."
            ),
            "package": backend_metadata.get("package"),
            "compatibility_note": (
                "The sample_cLHS_* filenames remain for backward compatibility."
            ),
        }
    return {
        "method_id": FALLBACK_METHOD_ID,
        "method_family": "spatially_constrained_soil_stratified_lhs",
        "method_label": (
            "Fallback cLHS-like soil-stratified Latin-hypercube targets in PCA space"
        ),
        "backend_used": "python_clhs_like",
        "is_clhs_like": True,
        "is_original_clhs_optimizer": False,
        "is_original_clhs_optimizer_core": False,
        "is_pure_original_clhs_design": False,
        "original_clhs_applies_to_roles": [],
        "spatial_augmentation_is_direct_clhs_output": False,
        "selection_objective": (
            "Nearest feasible candidate to Latin-hypercube targets within hard "
            "Soil Type quotas, followed by spatial augmentation."
        ),
        "scientific_scope": (
            "Fallback only; this does not optimise the original conditioned-LHS "
            "objective. Read fallback_reason in backend provenance."
        ),
        "compatibility_note": (
            "The sample_cLHS_* filenames remain for backward compatibility."
        ),
    }


def select_true_clhs_core(
    *,
    features: np.ndarray,
    coords: np.ndarray,
    soils: np.ndarray,
    soil_labels: dict[int, str],
    sample_size: int,
    seed: int,
    minimum_spacing_m: float,
    iterations: int,
    restarts: int,
    use_cpp: bool,
    auto_install: bool,
    repository: str,
    weights: dict[str, float],
    r_executable: str,
    r_script: Path,
    work_dir: Path,
    qa_dir: Path,
    root: Path,
) -> tuple[list[int], dict[str, Any]]:
    """Run CRAN clhs and return zero-based candidate indices plus provenance."""
    if features.ndim != 2 or features.shape[1] != 5:
        raise ValueError("Official backend requires exactly PC1-PC5.")
    if coords.shape != (len(features), 2) or len(soils) != len(features):
        raise ValueError("Candidate feature, coordinate and soil arrays disagree.")
    if not np.all(np.isfinite(features)) or not np.all(np.isfinite(coords)):
        raise ValueError("All cLHS candidate PCs and coordinates must be finite.")
    if sample_size < 2 or sample_size > len(features):
        raise ValueError("Invalid cLHS sample size.")

    work_dir.mkdir(parents=True, exist_ok=True)
    qa_dir.mkdir(parents=True, exist_ok=True)
    candidate_file = work_dir / "clhs_candidates.csv.gz"
    index_file = qa_dir / "true_clhs_selected_indices.csv"
    metadata_file = qa_dir / "true_clhs_backend.json"
    frame = pd.DataFrame(
        {
            "candidate_id": np.arange(len(features), dtype=int),
            "X_UTM": coords[:, 0],
            "Y_UTM": coords[:, 1],
            **{f"PC{i + 1}": features[:, i] for i in range(5)},
            "soil_group_code": soils.astype(int),
            "soil_group": [soil_labels.get(int(x), str(int(x))) for x in soils],
        }
    )
    frame.to_csv(candidate_file, index=False, compression="gzip")

    command = [
        str(r_executable),
        str(r_script),
        "--input",
        str(candidate_file),
        "--output-index",
        str(index_file),
        "--output-meta",
        str(metadata_file),
        "--size",
        str(int(sample_size)),
        "--iter",
        str(int(iterations)),
        "--restarts",
        str(int(restarts)),
        "--seed",
        str(int(seed)),
        "--min-spacing-m",
        str(float(minimum_spacing_m)),
        "--use-cpp",
        str(bool(use_cpp)).lower(),
        "--auto-install",
        str(bool(auto_install)).lower(),
        "--repository",
        str(repository),
        "--weight-numeric",
        str(float(weights["numeric"])),
        "--weight-factor",
        str(float(weights["factor"])),
        "--weight-correlation",
        str(float(weights["correlation"])),
    ]
    completed = subprocess.run(
        command,
        cwd=str(root),
        check=False,
        text=True,
        capture_output=True,
    )
    if completed.stdout:
        print(completed.stdout.strip())
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(
            f"CRAN clhs backend failed with exit code {completed.returncode}: {detail}"
        )
    if not index_file.exists() or not metadata_file.exists():
        raise RuntimeError("CRAN clhs did not create index and provenance outputs.")

    table = pd.read_csv(index_file)
    if "candidate_id" not in table:
        raise RuntimeError("CRAN clhs index output lacks candidate_id.")
    selected = table["candidate_id"].to_numpy(dtype=int)
    if (
        len(selected) != sample_size
        or len(np.unique(selected)) != sample_size
        or np.any(selected < 0)
        or np.any(selected >= len(features))
    ):
        raise RuntimeError("CRAN clhs returned invalid candidate indices.")
    metadata = json.loads(metadata_file.read_text(encoding="utf-8"))
    if metadata.get("backend_used") != "r_clhs_cran":
        raise RuntimeError("CRAN clhs provenance does not identify the actual backend.")
    return selected.tolist(), metadata


def fallback_metadata(
    *, seed: int, quotas: dict[int, int], soil_labels: dict[int, str], reason: str
) -> dict[str, Any]:
    """Build explicit provenance for the existing cLHS-like fallback."""
    return {
        "schema_version": "1.0.0",
        "status": "success_with_fallback",
        "backend_used": "python_clhs_like",
        "algorithm": "soil_stratified_nearest_latin_hypercube_targets",
        "is_original_clhs_optimizer": False,
        "random_seed": int(seed),
        "continuous_covariates": [f"PC{i}" for i in range(1, 6)],
        "continuous_space": "PCA_full_rank_rotation_PC1_PC5",
        "soil_type_representation": "hard_quota_strata",
        "soil_quotas": {
            soil_labels.get(int(k), str(int(k))): int(v) for k, v in quotas.items()
        },
        "fallback_reason": str(reason),
        "interpretation": (
            "This fallback does not optimise the conditioned Latin-hypercube "
            "objective implemented by CRAN clhs."
        ),
    }
