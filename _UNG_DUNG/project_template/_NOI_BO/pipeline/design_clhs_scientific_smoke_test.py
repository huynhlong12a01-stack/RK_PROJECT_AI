"""Fail-fast QA for true-cLHS core, declared fallback, and nested plans."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

import geopandas as gpd
import pandas as pd
import yaml

from scientific_metadata import covariate_provenance
from true_clhs_backend import FALLBACK_METHOD_ID, TRUE_METHOD_ID


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "{{PROJECT_ID}}"
RESULT = PROJECT / "01_THIET_KE_LAY_MAU" / "02_KET_QUA"
INPUT = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO"
WORK_QA = PROJECT / "_NOI_BO" / "work" / "design" / "qa"
REFERENCE = PROJECT / "_NOI_BO" / "config" / "pca_model_reference.json"
PROJECT_CONFIG = PROJECT / "_NOI_BO" / "config" / "project.yml"
SOIL_QA = WORK_QA / "soil_group_summary.json"
SOIL_RASTER = PROJECT / "_NOI_BO" / "work" / "design" / "Soil_Group_Code.tif"
SOIL_SOURCE = INPUT / "soil_type.geojson"


def load_json(path):
    if not path.exists():
        raise AssertionError(f"Missing QA file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_sha256(value):
    payload = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def require_dynamic_grid_warning(payload, grid_m):
    grid_label = f"{float(grid_m):g} m"
    warning = payload["interpretation_warning"]
    expected = (
        f"A {grid_label} computational/output cell alone is not evidence of "
        f"{grid_label} source detail."
    )
    require(expected in warning, f"Scale warning does not match the {grid_label} grid.")
    require(
        payload["output_grid"]["computational_grid_m"] == float(grid_m),
        f"Stored computational grid does not match {grid_label}.",
    )


def require_grid_warning_examples():
    for grid_m in (10, 30):
        example = covariate_provenance(
            "GRID_WARNING_TEST", "EPSG:32649", grid_m, "2025-01-01", "2026-01-01"
        )
        require_dynamic_grid_warning(example, grid_m)


def main():
    require_grid_warning_examples()
    full = pd.read_csv(RESULT / "sample_cLHS_FULL.csv")
    reduced = pd.read_csv(RESULT / "sample_cLHS_REDUCED.csv")
    combined = load_json(RESULT / "sampling_QA.json")
    full_qa = load_json(RESULT / "sampling_QA_FULL.json")
    reduced_qa = load_json(RESULT / "sampling_QA_REDUCED.json")
    pca = load_json(WORK_QA / "pca_summary.json")
    reference = load_json(REFERENCE)
    provenance = load_json(RESULT / "covariate_provenance.json")
    coverage = load_json(WORK_QA / "raw_covariate_coverage.json")
    soil_summary = load_json(SOIL_QA)

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
        spacing = backend["multi_start_selection"]
        require(spacing["minimum_spacing_target_met"] is True, "Selected CRAN core missed minimum spacing.")
        require(int(spacing["selected_spacing_violation_pairs"]) == 0, "CRAN core has spacing violations.")
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
    engine_summary = combined["engine_summary"]
    require(engine_summary.get("minimum_spacing_target_met") is True, "Core spacing gate was not met.")
    core_spacing = engine_summary["core_spacing"]
    require(core_spacing["minimum_spacing_target_met"] is True, "Independent core spacing QA failed.")
    require(int(core_spacing["spacing_violation_pairs"]) == 0, "Independent core spacing QA found violations.")
    require(not full.Point_ID.duplicated().any(), "Duplicate FULL Point_ID.")
    require(not reduced.Point_ID.duplicated().any(), "Duplicate REDUCED Point_ID.")
    require(len(full) == full_qa["count"] and len(reduced) == reduced_qa["count"], "QA counts mismatch.")

    project_config = yaml.safe_load(PROJECT_CONFIG.read_text(encoding="utf-8")) or {}
    project_epsg = int(project_config.get("crs_epsg", 0))
    require(project_epsg > 0, "project.yml has no valid crs_epsg.")
    roi = gpd.read_file(
        PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "roi_field_area.geojson"
    ).to_crs(project_epsg)
    roi_union = roi.geometry.union_all()
    full_geo = gpd.GeoDataFrame(
        full,
        geometry=gpd.points_from_xy(full.Longitude, full.Latitude),
        crs=4326,
    ).to_crs(project_epsg)
    reduced_geo = gpd.GeoDataFrame(
        reduced,
        geometry=gpd.points_from_xy(reduced.Longitude, reduced.Latitude),
        crs=4326,
    ).to_crs(project_epsg)
    require(full_geo.geometry.covered_by(roi_union).all(), "FULL has points outside ROI.")
    require(reduced_geo.geometry.covered_by(roi_union).all(), "REDUCED has points outside ROI.")

    require(coverage["raw_covariates"]["coverage_fraction"] >= 0.99, "Raw coverage <99%.")
    require(coverage["pca_assessment_before_rebuild"]["coverage_fraction"] >= 0.99, "PC coverage <99%.")
    require(coverage["pca_grid_ready"] is True, "PCA grid gate failed.")
    require(coverage["pca_lineage_assessment"]["valid"] is True, "PCA lineage gate failed.")
    require(coverage["soil_lineage_ready"] is True, "Soil Type lineage gate failed.")
    require(coverage["soil_lineage_assessment"]["valid"] is True, "Soil Type lineage assessment failed.")
    require(soil_summary["schema_version"] == "3.0.0", "Soil Type QA schema is not v3.")
    require(soil_summary["encoding"] == "nominal_factor_codes_v1; codes are labels, not ordinal values", "Soil Type is not declared nominal.")
    require(soil_summary["code_map_sha256"] == canonical_sha256(soil_summary["code_labels"]), "Soil Type code-map hash mismatch.")
    require(sha256_file(SOIL_RASTER) == soil_summary["soil_group_raster_sha256"], "Soil Type raster hash mismatch.")
    require(soil_summary["whole_domain_overlap_qa"]["passed"] is True, "Soil Type overlap QA failed.")
    if SOIL_SOURCE.exists():
        require(sha256_file(SOIL_SOURCE) == soil_summary["soil_source_sha256"], "Soil Type source hash mismatch.")
        require("Unmapped" in soil_summary["code_labels"].values(), "Soil Type Unmapped factor is missing.")
        require("Other" not in soil_summary["code_labels"].values(), "Workflow 1 incorrectly used model-only Other.")
    require(combined["soil_type_lineage"]["soil_group_summary_sha256"] == sha256_file(SOIL_QA), "Sampling QA does not chain to Soil Type QA bytes.")
    require(pca["schema_version"] == "2.0.0", "PCA summary schema is not v2.")
    require(pca["n_input"] == 5 and pca["n_retained"] == 5, "PCA dimensions wrong.")
    require(pca["dimension_reduction_applied"] is False, "Full-rank PCA mislabelled.")
    require(pca["reference_frozen"] is True, "PCA reference not frozen.")
    require(pca["pca_input_lineage_verified"] is True, "PCA raw lineage not certified.")
    require(set(pca["raw_covariate_sha256"]) == {"CHIRPS", "DEM", "NDVI", "Slope", "TWI"}, "Raw PCA hash set is not exact.")
    require(set(pca["pca_raster_sha256"]) == {f"PC{i}" for i in range(1, 6)}, "PC hash set is not exact.")
    require(reference["parameter_hash"] == reference["reference_hash"] == pca["reference_hash"], "PCA parameter hash mismatch.")
    require(sha256_file(REFERENCE) == pca["reference_file_sha256"], "PCA reference file hash mismatch.")
    for i in range(1, 6):
        pc_path = PROJECT / "_NOI_BO" / "work" / "design" / f"PC{i}.tif"
        require(sha256_file(pc_path) == pca["pca_raster_sha256"][f"PC{i}"], f"PC{i} byte hash mismatch.")
    if pca.get("reference_mode") == "fitted_and_frozen_for_project":
        require(isinstance(pca.get("pca_fit_random_seed"), int), "New PCA fit seed missing.")
        require(pca.get("pca_fit_sample_complete", 0) >= 1000, "New PCA fit sample count invalid.")
        require(bool(pca.get("pca_fit_r_version")) and bool(pca.get("pca_fit_terra_version")), "New PCA fit software metadata missing.")
    require_dynamic_grid_warning(
        provenance, provenance["output_grid"]["computational_grid_m"]
    )
    for name, qa in (("FULL", full_qa), ("REDUCED", reduced_qa)):
        require(qa["plan"] == name, f"{name} QA label wrong.")
        require(qa["sampling_constraints"]["minimum_spacing_target_met"] is True, f"{name} spacing gate missing.")
        require("not guaranteed" in qa["full_reduced_equivalence_disclaimer"], f"{name} disclaimer missing.")
        require(set(qa["metrics"]["feature_space"]) == {f"PC{i}" for i in range(1, 6)}, f"{name} feature QA incomplete.")

    print(
        "Design cLHS scientific smoke test passed: "
        f"FULL={len(full)}, REDUCED={len(reduced)}, backend={combined['backend_used']}"
    )


if __name__ == "__main__":
    main()
