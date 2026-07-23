"""Gate reuse of design covariates to the current project, ROI and settings.

Covariates are accepted only when they were downloaded by this workflow and
have a matching raw provenance sidecar. No external/legacy project is searched.
"""

import hashlib
import json
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
import yaml
from rasterio.crs import CRS
from rasterio.features import rasterize


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_BLIND_ROI_TEST"
WORK = PROJECT / "_NOI_BO" / "work" / "design"
QA_FILE = WORK / "qa" / "raw_covariate_coverage.json"
RAW_PROVENANCE_FILE = WORK / "qa" / "raw_covariate_provenance.json"
PCA_QA_FILE = WORK / "qa" / "pca_summary.json"
PCA_REFERENCE_FILE = PROJECT / "_NOI_BO" / "config" / "pca_model_reference.json"
CONFIG_FILE = PROJECT / "_NOI_BO" / "config" / "project.yml"
ROI_FILE = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "roi_field_area.geojson"
SOIL_FILE = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "soil_type.geojson"
SOIL_SETTINGS_FILE = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "sampling.yml"
SOIL_QA_FILE = WORK / "qa" / "soil_group_summary.json"
SOIL_RASTER_FILE = WORK / "Soil_Group_Code.tif"
SOIL_SCHEMA_VERSION = "3.0.0"
SOIL_ENCODING = "nominal_factor_codes_v1; codes are labels, not ordinal values"
TEMPLATE_FILE = WORK / "grid_template.tif"
FEATURES = ["CHIRPS", "DEM", "NDVI", "Slope", "TWI"]
PC_NAMES = [f"PC{i}" for i in range(1, 6)]
MIN_COVERAGE = 0.99


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


def is_lower_sha256(value):
    return (
        isinstance(value, str)
        and len(value) == 64
        and value == value.lower()
        and all(char in "0123456789abcdef" for char in value)
    )


def signature(dataset):
    return (
        dataset.crs.to_wkt() if dataset.crs else None,
        tuple(dataset.transform),
        dataset.width,
        dataset.height,
    )


def date_text(value):
    return value.isoformat() if hasattr(value, "isoformat") else str(value)


def load_expected_identity():
    if not CONFIG_FILE.exists():
        raise FileNotFoundError(f"Missing project configuration: {CONFIG_FILE}")
    cfg = yaml.safe_load(CONFIG_FILE.read_text(encoding="utf-8")) or {}
    if not isinstance(cfg, dict):
        raise ValueError("Project configuration root must be a mapping.")
    legacy = cfg.get("legacy_parameters")
    if not isinstance(legacy, dict):
        legacy = {}
    required = {
        "project_id": cfg.get("project_id"),
        "crs_epsg": cfg.get("crs_epsg"),
        "resolution_m": cfg.get("resolution_m"),
        "gee_project_id": cfg.get("gee_project_id"),
        "start_date": legacy.get("start_date"),
        "end_date": legacy.get("end_date"),
    }
    missing = [name for name, value in required.items() if value in (None, "")]
    if missing:
        raise ValueError(
            "Project configuration is incomplete: " + ", ".join(missing)
        )
    return {
        "project_id": str(required["project_id"]),
        "crs": CRS.from_epsg(int(required["crs_epsg"])),
        "resolution_m": float(required["resolution_m"]),
        "gee_project_id": str(required["gee_project_id"]),
        "start_date": date_text(required["start_date"]),
        "end_date": date_text(required["end_date"]),
        "roi_sha256": sha256_file(ROI_FILE),
    }


def assessment(folder, names, roi):
    paths = [folder / f"{name}.tif" for name in names]
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        return {"valid": False, "missing": missing, "coverage_fraction": 0.0}
    datasets = [rasterio.open(path) for path in paths]
    try:
        first = datasets[0]
        sig = signature(first)
        common_grid = all(signature(ds) == sig for ds in datasets)
        if not common_grid:
            return {
                "valid": False,
                "common_grid": False,
                "coverage_fraction": 0.0,
            }
        projected = roi.to_crs(first.crs)
        mask = rasterize(
            [(geom, 1) for geom in projected.geometry if geom is not None and not geom.is_empty],
            out_shape=(first.height, first.width),
            transform=first.transform,
            fill=0,
            all_touched=True,
            dtype="uint8",
        )
        roi_cells = int(mask.sum())
        common_valid = 0
        for _, window in first.block_windows(1):
            arrays = [ds.read(1, window=window) for ds in datasets]
            valid = np.ones(arrays[0].shape, dtype=bool)
            for values, ds in zip(arrays, datasets):
                valid &= np.isfinite(values)
                if ds.nodata is not None and np.isfinite(ds.nodata):
                    valid &= values != ds.nodata
            r0, c0 = int(window.row_off), int(window.col_off)
            inside = mask[
                r0 : r0 + int(window.height),
                c0 : c0 + int(window.width),
            ] == 1
            common_valid += int(np.sum(valid & inside))
        fraction = common_valid / roi_cells if roi_cells else 0.0
        return {
            "valid": bool(roi_cells > 0 and fraction >= MIN_COVERAGE),
            "common_grid": True,
            "crs": str(first.crs),
            "crs_wkt": first.crs.to_wkt() if first.crs else None,
            "transform": list(first.transform),
            "width": first.width,
            "height": first.height,
            "bounds": list(first.bounds),
            "roi_cell_count": roi_cells,
            "common_valid_roi_count": common_valid,
            "coverage_fraction": fraction,
            "minimum_required_fraction": MIN_COVERAGE,
        }
    finally:
        for dataset in datasets:
            dataset.close()


def matches_template(result):
    if not TEMPLATE_FILE.exists() or not result.get("common_grid"):
        return False
    with rasterio.open(TEMPLATE_FILE) as template:
        expected = signature(template)
    return bool(
        result.get("crs_wkt") == expected[0]
        and result.get("transform") == list(expected[1])
        and result.get("width") == expected[2]
        and result.get("height") == expected[3]
    )


def crs_equal(left, right):
    try:
        return CRS.from_user_input(left) == CRS.from_user_input(right)
    except (TypeError, ValueError):
        return False


def provenance_assessment(payload, expected, current, inventory=None):
    reasons = []
    if not isinstance(payload, dict):
        return {"valid": False, "reasons": ["raw provenance sidecar is missing or invalid"]}
    if not isinstance(current, dict):
        return {"valid": False, "reasons": ["current raster assessment is invalid"]}

    source = payload.get("source_identity")
    grid = payload.get("output_grid")
    temporal = payload.get("temporal_window")
    if not isinstance(source, dict):
        reasons.append("source_identity must be an object")
        source = {}
    if not isinstance(grid, dict):
        reasons.append("output_grid must be an object")
        grid = {}
    if not isinstance(temporal, dict):
        reasons.append("temporal_window must be an object")
        temporal = {}

    if str(payload.get("project_id")) != expected["project_id"]:
        reasons.append("project_id mismatch")
    if str(source.get("gee_project_id")) != expected["gee_project_id"]:
        reasons.append("GEE project mismatch")
    if str(source.get("roi_field_area_sha256", "")).lower() != expected["roi_sha256"]:
        reasons.append("ROI hash mismatch")
    if not crs_equal(grid.get("crs"), expected["crs"]):
        reasons.append("provenance CRS mismatch")
    try:
        recorded_resolution = float(grid.get("computational_grid_m"))
    except (TypeError, ValueError):
        recorded_resolution = float("nan")
    if not np.isclose(recorded_resolution, expected["resolution_m"], rtol=0, atol=1e-9):
        reasons.append("provenance resolution mismatch")
    if str(temporal.get("start_date_inclusive")) != expected["start_date"]:
        reasons.append("start date mismatch")
    if str(temporal.get("end_date_exclusive")) != expected["end_date"]:
        reasons.append("end date mismatch")

    if not crs_equal(current.get("crs"), expected["crs"]):
        reasons.append("raster CRS mismatch")
    transform = current.get("transform")
    try:
        resolution_matches = (
            isinstance(transform, (list, tuple))
            and len(transform) >= 5
            and np.isclose(abs(float(transform[0])), expected["resolution_m"], rtol=0, atol=1e-9)
            and np.isclose(abs(float(transform[4])), expected["resolution_m"], rtol=0, atol=1e-9)
        )
    except (TypeError, ValueError):
        resolution_matches = False
    if not resolution_matches:
        reasons.append("raster resolution mismatch")
    if not current.get("matches_computational_grid"):
        reasons.append("rasters do not match the current ROI/config grid template")

    if inventory is not None:
        recorded_hashes = payload.get("raw_covariate_sha256")
        if not isinstance(recorded_hashes, dict):
            reasons.append("raw_covariate_sha256 must be an object")
            recorded_hashes = {}
        if set(recorded_hashes) != set(FEATURES):
            reasons.append("raw covariate hash keys must exactly match configured features")
        if not isinstance(inventory, dict):
            reasons.append("current raw file inventory is invalid")
            inventory = {}
        for name in FEATURES:
            recorded = recorded_hashes.get(name)
            current_entry = inventory.get(name)
            current_hash = current_entry.get("sha256") if isinstance(current_entry, dict) else None
            if not is_lower_sha256(recorded):
                reasons.append(f"{name} recorded hash is not lowercase SHA-256")
            if not is_lower_sha256(current_hash):
                reasons.append(f"{name} current file hash is invalid")
            if recorded != current_hash:
                reasons.append(f"{name} file hash mismatch")

    return {"valid": not reasons, "reasons": reasons}

def pca_assessment(roi):
    if not TEMPLATE_FILE.exists():
        return {"valid": False, "coverage_fraction": 0.0}
    result = assessment(WORK, [f"PC{i}" for i in range(1, 6)], roi)
    result["matches_computational_grid"] = matches_template(result)
    result["valid"] = bool(result.get("valid") and result["matches_computational_grid"])
    return result


def reference_structure_reasons(reference):
    reasons = []
    if not isinstance(reference, dict):
        return ["PCA reference is missing or invalid"]
    if reference.get("reference_frozen") is not True:
        reasons.append("current PCA reference is not frozen")
    if reference.get("feature_order") != FEATURES:
        reasons.append("current PCA reference feature order is invalid")
    try:
        n_input = int(reference.get("n_input_features"))
        n_retained = int(reference.get("n_retained_components"))
    except (TypeError, ValueError):
        n_input = n_retained = -1
    if n_input != 5 or n_retained != 5 or reference.get("dimension_reduction_applied") is not False:
        reasons.append("current PCA reference is not declared full-rank 5x5")

    try:
        means = np.asarray(reference.get("scaler_mean"), dtype=float)
        scales = np.asarray(reference.get("scaler_scale"), dtype=float)
        components = np.asarray(reference.get("pca_components"), dtype=float)
        explained = np.asarray(reference.get("pca_explained_variance_ratio"), dtype=float)
    except (TypeError, ValueError):
        reasons.append("current PCA reference numeric arrays are malformed")
        return reasons
    if means.shape != (5,) or scales.shape != (5,) or components.shape != (5, 5):
        reasons.append("current PCA reference numeric shapes are not 5/5/5x5")
    elif (
        not np.isfinite(means).all()
        or not np.isfinite(scales).all()
        or not np.isfinite(components).all()
        or np.any(scales <= 0)
    ):
        reasons.append("current PCA reference contains non-finite values or non-positive scales")
    elif not np.allclose(components @ components.T, np.eye(5), rtol=0, atol=1e-6):
        reasons.append("current PCA component rows are not orthonormal")
    if (
        explained.shape != (5,)
        or not np.isfinite(explained).all()
        or np.any(explained < 0)
        or not np.isclose(float(explained.sum()), 1.0, rtol=0, atol=1e-6)
    ):
        reasons.append("current PCA explained variance is invalid")
    return reasons


def pca_lineage_assessment(pca, inventory):
    reasons = []
    if not isinstance(pca, dict) or not pca.get("valid"):
        reasons.append("PCA rasters are missing, sparse or do not match the current grid")
    try:
        summary = json.loads(PCA_QA_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError, OSError):
        summary = None
    if not isinstance(summary, dict):
        reasons.append("PCA summary is missing or invalid")
        return {"valid": False, "reasons": reasons}

    if str(summary.get("schema_version")) != "2.0.0":
        reasons.append("PCA summary schema is not v2; full rebuild required")
    if summary.get("pca_input_lineage_verified") is not True:
        reasons.append("PCA summary does not certify its raw input lineage")
    if summary.get("reference_frozen") is not True:
        reasons.append("PCA summary does not certify a frozen reference")
    if summary.get("feature_order") != FEATURES:
        reasons.append("PCA summary feature order is invalid")
    try:
        summary_n_input = int(summary.get("n_input"))
        summary_n_retained = int(summary.get("n_retained"))
    except (TypeError, ValueError):
        summary_n_input = summary_n_retained = -1
    if (
        summary_n_input != 5
        or summary_n_retained != 5
        or summary.get("dimension_reduction_applied") is not False
    ):
        reasons.append("PCA summary is not full-rank 5x5")

    if not isinstance(inventory, dict):
        reasons.append("current raw file inventory is invalid")
        inventory = {}
    recorded_raw = summary.get("raw_covariate_sha256")
    if not isinstance(recorded_raw, dict):
        reasons.append("PCA raw input hashes must be an object")
        recorded_raw = {}
    if set(recorded_raw) != set(FEATURES):
        reasons.append("PCA raw input hash keys must exactly match configured features")
    for name in FEATURES:
        recorded_hash = recorded_raw.get(name)
        entry = inventory.get(name)
        current_hash = entry.get("sha256") if isinstance(entry, dict) else None
        if not is_lower_sha256(recorded_hash):
            reasons.append(f"PCA input hash is invalid for {name}")
        if recorded_hash != current_hash:
            reasons.append(f"PCA input hash mismatch for {name}")

    recorded_sidecar_hash = summary.get("raw_provenance_sha256")
    current_sidecar_hash = sha256_file(RAW_PROVENANCE_FILE) if RAW_PROVENANCE_FILE.exists() else None
    if not is_lower_sha256(recorded_sidecar_hash):
        reasons.append("PCA raw provenance hash is missing or invalid")
    if recorded_sidecar_hash != current_sidecar_hash:
        reasons.append("PCA was not built from the current raw provenance sidecar")

    recorded_pc_hashes = summary.get("pca_raster_sha256")
    if not isinstance(recorded_pc_hashes, dict):
        reasons.append("PCA raster hashes must be an object")
        recorded_pc_hashes = {}
    if set(recorded_pc_hashes) != set(PC_NAMES):
        reasons.append("PCA raster hash keys must exactly match PC1-PC5")
    current_pc_hashes = {}
    for name in PC_NAMES:
        path = WORK / f"{name}.tif"
        current_hash = sha256_file(path) if path.exists() else None
        current_pc_hashes[name] = current_hash
        recorded_hash = recorded_pc_hashes.get(name)
        if not is_lower_sha256(recorded_hash):
            reasons.append(f"PCA raster hash is invalid for {name}")
        if recorded_hash != current_hash:
            reasons.append(f"PCA raster hash mismatch for {name}")

    try:
        reference = json.loads(PCA_REFERENCE_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError, OSError):
        reference = None
    reasons.extend(reference_structure_reasons(reference))
    summary_reference_hash = summary.get("reference_hash")
    reference_hash = reference.get("reference_hash") if isinstance(reference, dict) else None
    parameter_hash = reference.get("parameter_hash") if isinstance(reference, dict) else None
    for label, value in (
        ("summary PCA reference hash", summary_reference_hash),
        ("current PCA reference hash", reference_hash),
        ("current PCA parameter hash", parameter_hash),
    ):
        if not is_lower_sha256(value):
            reasons.append(f"{label} is missing or invalid")
    if not (summary_reference_hash == reference_hash == parameter_hash):
        reasons.append("PCA summary and current reference parameter hashes disagree")

    recorded_reference_file_hash = summary.get("reference_file_sha256")
    current_reference_file_hash = (
        sha256_file(PCA_REFERENCE_FILE) if PCA_REFERENCE_FILE.exists() else None
    )
    if not is_lower_sha256(recorded_reference_file_hash):
        reasons.append("PCA reference file hash is missing or invalid")
    if recorded_reference_file_hash != current_reference_file_hash:
        reasons.append("PCA reference file bytes changed after PCA creation")

    return {
        "valid": not reasons,
        "reasons": reasons,
        "pca_summary_file": str(PCA_QA_FILE.resolve()).replace("\\", "/"),
        "raw_provenance_sha256": current_sidecar_hash,
        "reference_hash": summary_reference_hash,
        "reference_file_sha256": current_reference_file_hash,
        "pca_raster_sha256": current_pc_hashes,
    }

def configured_soil_field():
    if not SOIL_SETTINGS_FILE.exists():
        return "Ma1"
    try:
        settings = yaml.safe_load(SOIL_SETTINGS_FILE.read_text(encoding="utf-8")) or {}
    except (yaml.YAMLError, UnicodeDecodeError, OSError):
        return None
    if not isinstance(settings, dict):
        return None
    value = settings.get("soil_group_field", "Ma1")
    value = str(value).strip() if value is not None else ""
    return value or None


def soil_lineage_assessment():
    reasons = []
    try:
        summary = json.loads(SOIL_QA_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError, OSError):
        summary = None
    if not isinstance(summary, dict):
        return {"valid": False, "reasons": ["Workflow 1 Soil Type QA is missing or invalid"]}

    current_present = SOIL_FILE.exists()
    recorded_present = summary.get("soil_input_present")
    if str(summary.get("schema_version")) != SOIL_SCHEMA_VERSION:
        reasons.append("Soil Type QA schema is not v3; rerun Workflow 1")
    if recorded_present is not current_present:
        reasons.append("configured Soil Type presence changed after Workflow 1")

    recorded_field = summary.get("source_field")
    current_field = configured_soil_field() if current_present else None
    if current_present and current_field is None:
        reasons.append("sampling.yml soil_group_field is missing or invalid")
    if recorded_field != current_field:
        reasons.append("configured Soil Type source field changed after Workflow 1")

    recorded_source_hash = summary.get("soil_source_sha256")
    current_source_hash = sha256_file(SOIL_FILE) if current_present else None
    if current_present:
        if not is_lower_sha256(recorded_source_hash):
            reasons.append("Soil Type source hash is missing or invalid")
        if recorded_source_hash != current_source_hash:
            reasons.append("Soil Type source file changed after Workflow 1")
    elif recorded_source_hash is not None:
        reasons.append("Soil Type QA records a source hash although no source is configured")

    if summary.get("encoding") != SOIL_ENCODING:
        reasons.append("Soil Type encoding declaration is missing or incompatible")
    code_labels = summary.get("code_labels")
    if not isinstance(code_labels, dict) or not code_labels:
        reasons.append("Soil Type code map is missing or invalid")
        code_labels = {}
    normalized_code_labels = {str(key): str(value) for key, value in code_labels.items()}
    if len(set(normalized_code_labels.values())) != len(normalized_code_labels):
        reasons.append("Soil Type code map contains duplicate labels")
    if current_present:
        if list(normalized_code_labels.values()).count("Unmapped") != 1:
            reasons.append("Soil Type code map must contain exactly one Unmapped level")
        if "Other" in normalized_code_labels.values():
            reasons.append("Workflow 1 Soil Type code map must not use the model-only Other level")
    elif normalized_code_labels != {"1": "All"}:
        reasons.append("no-Soil workflow must use the single nominal All level")
    recorded_map_hash = summary.get("code_map_sha256")
    current_map_hash = canonical_sha256(normalized_code_labels) if normalized_code_labels else None
    if not is_lower_sha256(recorded_map_hash):
        reasons.append("Soil Type code-map hash is missing or invalid")
    if recorded_map_hash != current_map_hash:
        reasons.append("Soil Type code map changed after Workflow 1")

    recorded_raster_hash = summary.get("soil_group_raster_sha256")
    current_raster_hash = sha256_file(SOIL_RASTER_FILE) if SOIL_RASTER_FILE.exists() else None
    if not is_lower_sha256(recorded_raster_hash):
        reasons.append("Soil Type output raster hash is missing or invalid")
    if recorded_raster_hash != current_raster_hash:
        reasons.append("Workflow 1 Soil Type raster changed after creation")

    overlap = summary.get("whole_domain_overlap_qa")
    if not isinstance(overlap, dict) or overlap.get("passed") is not True:
        reasons.append("whole-domain Soil Type overlap QA did not pass")

    return {
        "valid": not reasons,
        "reasons": reasons,
        "soil_input_present": current_present,
        "source_field": current_field,
        "soil_source_sha256": current_source_hash,
        "code_map_sha256": current_map_hash,
        "soil_group_raster_sha256": current_raster_hash,
        "soil_group_summary_sha256": sha256_file(SOIL_QA_FILE) if SOIL_QA_FILE.exists() else None,
    }


def write_summary(payload):
    QA_FILE.parent.mkdir(parents=True, exist_ok=True)
    QA_FILE.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def fail_gate(status, current, provenance, message):
    payload = {
        "schema_version": "2.0.0",
        "status": status,
        "raw_files_changed": False,
        "current_assessment": current,
        "raw_provenance_assessment": provenance,
        "required_action": (
            "Run the sampling-design workflow with Google Earth Engine access. "
            "It will rebuild the grid from the current ROI/config and download fresh covariates."
        ),
    }
    write_summary(payload)
    print(message)
    for reason in provenance.get("reasons", []):
        print(f"- {reason}")
    raise SystemExit(20)


def main():
    if not ROI_FILE.exists():
        raise FileNotFoundError(f"Missing ROI: {ROI_FILE}")
    roi = gpd.read_file(ROI_FILE)
    if roi.crs is None:
        raise ValueError("ROI has no CRS.")
    roi = roi[roi.geometry.notna() & ~roi.geometry.is_empty].copy()
    if roi.empty:
        raise ValueError("ROI has no valid geometry.")

    expected = load_expected_identity()
    current = assessment(WORK, FEATURES, roi)
    current["matches_computational_grid"] = matches_template(current)
    if not current.get("valid"):
        fail_gate(
            "current_workflow_download_required",
            current,
            {"valid": False, "reasons": ["missing, misaligned or sparse full-area covariates"]},
            "Current-project full-area covariates are required; no legacy source will be imported.",
        )

    try:
        raw_provenance = json.loads(RAW_PROVENANCE_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError, OSError):
        raw_provenance = None
    provenance = provenance_assessment(raw_provenance, expected, current)
    if not provenance["valid"]:
        fail_gate(
            "raw_provenance_mismatch",
            current,
            provenance,
            "Existing covariates cannot be reused because their raw provenance is not current.",
        )

    inventory = {
        name: {
            "path": str((WORK / f"{name}.tif").resolve()).replace("\\", "/"),
            "size_bytes": (WORK / f"{name}.tif").stat().st_size,
            "sha256": sha256_file(WORK / f"{name}.tif"),
        }
        for name in FEATURES
    }
    provenance = provenance_assessment(raw_provenance, expected, current, inventory)
    if not provenance["valid"]:
        fail_gate(
            "raw_file_identity_mismatch",
            current,
            provenance,
            "Existing covariates cannot be reused because one or more files changed.",
        )

    pca = pca_assessment(roi)
    pca_lineage = pca_lineage_assessment(pca, inventory)
    pca["lineage"] = pca_lineage
    pca["valid"] = bool(pca.get("valid") and pca_lineage["valid"])
    soil_lineage = soil_lineage_assessment()
    payload = {
        "schema_version": "2.0.0",
        "status": "ready",
        "materialization_mode": "reused_verified_current_workflow_download",
        "materialization_source": str(WORK.resolve()).replace("\\", "/"),
        "raw_files_changed": False,
        "raw_covariates": current,
        "raw_provenance_assessment": provenance,
        "raw_provenance_file": str(RAW_PROVENANCE_FILE.resolve()).replace("\\", "/"),
        "pca_assessment_before_rebuild": pca,
        "pca_lineage_assessment": pca_lineage,
        "pca_grid_ready": pca.get("valid", False),
        "soil_lineage_assessment": soil_lineage,
        "soil_lineage_ready": soil_lineage["valid"],
        "file_inventory": inventory,
        "verified_source_lineage": raw_provenance.get("source_identity"),
    }
    write_summary(payload)
    print(
        "Design covariate gate passed: "
        f"coverage={current['coverage_fraction']:.6f}; "
        "source=current workflow with matching ROI/config provenance; "
        f"pca_lineage_ready={pca['valid']}; "
        f"soil_lineage_ready={soil_lineage['valid']}"
    )
    if not pca["valid"]:
        for reason in pca_lineage["reasons"]:
            print(f"- PCA rebuild required: {reason}")
    if not soil_lineage["valid"]:
        for reason in soil_lineage["reasons"]:
            print(f"- Soil Type rebuild required: {reason}")


if __name__ == "__main__":
    main()
