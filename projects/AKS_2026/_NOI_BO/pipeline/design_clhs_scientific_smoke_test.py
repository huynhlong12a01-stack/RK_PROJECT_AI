"""Fail-fast QA for true-cLHS core, declared fallback, and nested plans."""

from __future__ import annotations

import json
import re
from pathlib import Path

import geopandas as gpd
import pandas as pd

from true_clhs_backend import FALLBACK_METHOD_ID, TRUE_METHOD_ID


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_2026"
RESULT = PROJECT / "01_THIET_KE_LAY_MAU" / "02_KET_QUA"
INPUT = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO"
WORK_QA = PROJECT / "_NOI_BO" / "work" / "design" / "qa"
REFERENCE = PROJECT / "_NOI_BO" / "config" / "pca_model_reference.json"


def load_json(path):
    if not path.exists():
        raise AssertionError(f"Missing QA file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    full = pd.read_csv(RESULT / "sample_cLHS_FULL.csv")
    reduced = pd.read_csv(RESULT / "sample_cLHS_REDUCED.csv")
    combined = load_json(RESULT / "sampling_QA.json")
    full_qa = load_json(RESULT / "sampling_QA_FULL.json")
    reduced_qa = load_json(RESULT / "sampling_QA_REDUCED.json")
    pca = load_json(WORK_QA / "pca_summary.json")
    reference = load_json(REFERENCE)
    provenance = load_json(RESULT / "covariate_provenance.json")
    coverage = load_json(WORK_QA / "raw_covariate_coverage.json")

    method_id = combined["method_id"]
    require(method_id in {TRUE_METHOD_ID, FALLBACK_METHOD_ID}, "Unknown method_id.")
    method = combined["method_metadata"]
    backend = combined["backend_provenance"]
    require(combined["backend_used"] == backend["backend_used"], "Backend provenance mismatch.")
    if combined["backend_used"] == "r_clhs_cran":
        require(method_id == TRUE_METHOD_ID, "True backend has fallback method_id.")
        require(method["is_original_clhs_optimizer_core"] is True, "Original core flag missing.")
        require(method["is_pure_original_clhs_design"] is False, "Hybrid FULL was labelled pure cLHS.")
        require(method["original_clhs_applies_to_roles"] == ["clhs_core"], "Core role scope wrong.")
        require(backend["package"]["name"] == "clhs", "CRAN package name missing.")
        require(re.fullmatch(r"\d+\.\d+\.\d+", backend["package"]["version"]), "Package version invalid.")
        require(backend["optimiser"]["iterations_per_restart"] >= 1, "Iterations missing.")
        require(backend["optimiser"]["successful_restarts"] >= 1, "No successful restart.")
        require(backend["multi_start_selection"]["no_post_optimisation_point_replacement"] is True, "Core was repaired after cLHS.")
        require(backend["soil_type"]["representation"] in {"categorical_factor", "omitted_single_level"}, "Soil Type was treated as numeric.")
        require(set(reduced.design_role) == {"clhs_core"}, "REDUCED contains non-cLHS augmentation.")
    else:
        require(method_id == FALLBACK_METHOD_ID, "Fallback backend has true method_id.")
        require(method["is_original_clhs_optimizer_core"] is False, "Fallback over-claims original cLHS.")
        require(method["is_pure_original_clhs_design"] is False, "Fallback over-claims pure cLHS.")
        require(bool(backend.get("fallback_reason")), "Fallback reason missing.")
        require(set(reduced.design_role) == {"lhs_core"}, "Fallback REDUCED role wrong.")

    require(set(full.sampling_method_id) == {method_id}, "FULL method_id mismatch.")
    require(set(reduced.sampling_method_id) == {method_id}, "REDUCED method_id mismatch.")
    require(set(reduced.Point_ID).issubset(set(full.Point_ID)), "REDUCED is not nested.")
    require(len(reduced) < len(full), "FULL and REDUCED are not distinct.")
    require(not full.Point_ID.duplicated().any(), "Duplicate FULL Point_ID.")
    require(not reduced.Point_ID.duplicated().any(), "Duplicate REDUCED Point_ID.")
    require(len(full) == full_qa["count"] and len(reduced) == reduced_qa["count"], "QA counts mismatch.")

    roi = gpd.read_file(INPUT / "roi.geojson").to_crs(32649)
    roi_union = roi.geometry.union_all()
    full_geo = gpd.GeoDataFrame(
        full,
        geometry=gpd.points_from_xy(full.Longitude, full.Latitude),
        crs=4326,
    ).to_crs(32649)
    reduced_geo = gpd.GeoDataFrame(
        reduced,
        geometry=gpd.points_from_xy(reduced.Longitude, reduced.Latitude),
        crs=4326,
    ).to_crs(32649)
    require(full_geo.geometry.covered_by(roi_union).all(), "FULL has points outside ROI.")
    require(reduced_geo.geometry.covered_by(roi_union).all(), "REDUCED has points outside ROI.")

    require(coverage["raw_covariates"]["coverage_fraction"] >= 0.99, "Raw coverage <99%.")
    require(coverage["pca_assessment_before_rebuild"]["coverage_fraction"] >= 0.99, "PC coverage <99%.")
    require(coverage["pca_grid_ready"] is True, "PCA grid gate failed.")
    require(pca["n_input"] == 5 and pca["n_retained"] == 5, "PCA dimensions wrong.")
    require(pca["dimension_reduction_applied"] is False, "Full-rank PCA mislabelled.")
    require(pca["reference_frozen"] is True, "PCA reference not frozen.")
    require(reference["parameter_hash"] == pca["reference_hash"], "PCA hash mismatch.")
    require("not evidence of 10 m source detail" in provenance["interpretation_warning"], "Scale warning missing.")
    for name, qa in (("FULL", full_qa), ("REDUCED", reduced_qa)):
        require(qa["plan"] == name, f"{name} QA label wrong.")
        require("not guaranteed" in qa["full_reduced_equivalence_disclaimer"], f"{name} disclaimer missing.")
        require(set(qa["metrics"]["feature_space"]) == {f"PC{i}" for i in range(1, 6)}, f"{name} feature QA incomplete.")

    print(
        "Design cLHS scientific smoke test passed: "
        f"FULL={len(full)}, REDUCED={len(reduced)}, backend={combined['backend_used']}"
    )


if __name__ == "__main__":
    main()
