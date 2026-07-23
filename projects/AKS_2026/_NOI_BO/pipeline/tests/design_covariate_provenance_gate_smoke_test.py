"""Fast current-project identity and grid-rebuild gates; no network access."""

import copy
import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np
import rasterio


PIPELINE = Path(__file__).resolve().parents[1]
ROOT = Path(__file__).resolve().parents[5]
spec = importlib.util.spec_from_file_location(
    "ensure_design_covariates", PIPELINE / "ensure_design_covariates.py"
)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


expected = {
    "project_id": "TEST",
    "crs": gate.CRS.from_epsg(32649),
    "resolution_m": 30.0,
    "gee_project_id": "gee-test",
    "start_date": "2025-01-01",
    "end_date": "2026-01-01",
    "roi_sha256": "a" * 64,
}
current = {
    "crs": "EPSG:32649",
    "transform": [30.0, 0.0, 240000.0, 0.0, -30.0, 1500000.0, 0.0, 0.0, 1.0],
    "matches_computational_grid": True,
}
inventory = {
    name: {"sha256": str(index) * 64}
    for index, name in enumerate(gate.FEATURES, start=1)
}
payload = {
    "project_id": "TEST",
    "source_identity": {
        "gee_project_id": "gee-test",
        "roi_field_area_sha256": "a" * 64,
    },
    "output_grid": {"crs": "EPSG:32649", "computational_grid_m": 30.0},
    "temporal_window": {
        "start_date_inclusive": "2025-01-01",
        "end_date_exclusive": "2026-01-01",
    },
    "raw_covariate_sha256": {
        name: values["sha256"] for name, values in inventory.items()
    },
}
assert gate.provenance_assessment(payload, expected, current, inventory)["valid"]

mutations = [
    ("source_identity", "gee_project_id", "wrong-project"),
    ("source_identity", "roi_field_area_sha256", "b" * 64),
    ("output_grid", "crs", "EPSG:32648"),
    ("output_grid", "computational_grid_m", 10.0),
    ("temporal_window", "start_date_inclusive", "2024-01-01"),
    ("temporal_window", "end_date_exclusive", "2025-12-31"),
    ("raw_covariate_sha256", "DEM", "f" * 64),
]
for section, key, value in mutations:
    changed = copy.deepcopy(payload)
    changed[section][key] = value
    assert not gate.provenance_assessment(changed, expected, current, inventory)["valid"]

changed_current = copy.deepcopy(current)
changed_current["matches_computational_grid"] = False
assert not gate.provenance_assessment(payload, expected, changed_current, inventory)["valid"]
changed_current = copy.deepcopy(current)
changed_current["transform"][0] = 10.0
assert not gate.provenance_assessment(payload, expected, changed_current, inventory)["valid"]

for malformed_key in ("source_identity", "output_grid", "temporal_window"):
    malformed = copy.deepcopy(payload)
    malformed[malformed_key] = ["not", "an", "object"]
    assert not gate.provenance_assessment(malformed, expected, current, inventory)["valid"]
malformed = copy.deepcopy(payload)
malformed["raw_covariate_sha256"] = "not-an-object"
assert not gate.provenance_assessment(malformed, expected, current, inventory)["valid"]

fixture = ROOT / "_UNG_DUNG" / "runtime" / "tests" / "pca_lineage_gate"
fixture.mkdir(parents=True, exist_ok=True)
old_globals = {
    "WORK": gate.WORK,
    "RAW_PROVENANCE_FILE": gate.RAW_PROVENANCE_FILE,
    "PCA_QA_FILE": gate.PCA_QA_FILE,
    "PCA_REFERENCE_FILE": gate.PCA_REFERENCE_FILE,
}
try:
    gate.WORK = fixture
    gate.RAW_PROVENANCE_FILE = fixture / "raw_covariate_provenance.json"
    gate.PCA_QA_FILE = fixture / "pca_summary.json"
    gate.PCA_REFERENCE_FILE = fixture / "pca_model_reference.json"
    gate.RAW_PROVENANCE_FILE.write_bytes(b"raw-provenance-fixture")
    for index, name in enumerate(gate.PC_NAMES, start=1):
        (fixture / f"{name}.tif").write_bytes(f"pc-{index}".encode("ascii"))

    parameter_hash = "a" * 64
    reference = {
        "reference_frozen": True,
        "feature_order": gate.FEATURES,
        "n_input_features": 5,
        "n_retained_components": 5,
        "dimension_reduction_applied": False,
        "scaler_mean": [0.0] * 5,
        "scaler_scale": [1.0] * 5,
        "pca_components": np.eye(5).tolist(),
        "pca_explained_variance_ratio": [0.2] * 5,
        "reference_hash": parameter_hash,
        "parameter_hash": parameter_hash,
    }
    gate.PCA_REFERENCE_FILE.write_text(json.dumps(reference), encoding="utf-8")
    summary = {
        "schema_version": "2.0.0",
        "pca_input_lineage_verified": True,
        "reference_frozen": True,
        "feature_order": gate.FEATURES,
        "n_input": 5,
        "n_retained": 5,
        "dimension_reduction_applied": False,
        "raw_covariate_sha256": {
            name: values["sha256"] for name, values in inventory.items()
        },
        "raw_provenance_sha256": file_hash(gate.RAW_PROVENANCE_FILE),
        "pca_raster_sha256": {
            name: file_hash(fixture / f"{name}.tif") for name in gate.PC_NAMES
        },
        "reference_hash": parameter_hash,
        "reference_file_sha256": file_hash(gate.PCA_REFERENCE_FILE),
    }

    def write_summary(value):
        gate.PCA_QA_FILE.write_text(json.dumps(value), encoding="utf-8")

    write_summary(summary)
    result = gate.pca_lineage_assessment({"valid": True}, inventory)
    assert result["valid"], result["reasons"]

    pc3 = fixture / "PC3.tif"
    original_pc3 = pc3.read_bytes()
    pc3.write_bytes(original_pc3 + b"x")
    result = gate.pca_lineage_assessment({"valid": True}, inventory)
    assert not result["valid"] and any("PC3" in reason for reason in result["reasons"])
    pc3.write_bytes(original_pc3)

    original_reference = gate.PCA_REFERENCE_FILE.read_text(encoding="utf-8")
    gate.PCA_REFERENCE_FILE.write_text(original_reference + " ", encoding="utf-8")
    result = gate.pca_lineage_assessment({"valid": True}, inventory)
    assert not result["valid"] and any("reference file bytes" in reason for reason in result["reasons"])
    gate.PCA_REFERENCE_FILE.write_text(original_reference, encoding="utf-8")

    semantic_bad = copy.deepcopy(reference)
    semantic_bad["reference_hash"] = "b" * 64
    gate.PCA_REFERENCE_FILE.write_text(json.dumps(semantic_bad), encoding="utf-8")
    semantic_summary = copy.deepcopy(summary)
    semantic_summary["reference_file_sha256"] = file_hash(gate.PCA_REFERENCE_FILE)
    write_summary(semantic_summary)
    result = gate.pca_lineage_assessment({"valid": True}, inventory)
    assert not result["valid"] and any("parameter hashes disagree" in reason for reason in result["reasons"])
    gate.PCA_REFERENCE_FILE.write_text(original_reference, encoding="utf-8")

    bad_keys = copy.deepcopy(summary)
    bad_keys["pca_raster_sha256"].pop("PC5")
    bad_keys["pca_raster_sha256"]["PC6"] = "f" * 64
    write_summary(bad_keys)
    result = gate.pca_lineage_assessment({"valid": True}, inventory)
    assert not result["valid"] and any("exactly match PC1-PC5" in reason for reason in result["reasons"])

    legacy_summary = copy.deepcopy(summary)
    legacy_summary["schema_version"] = "1.0.0"
    legacy_summary.pop("pca_raster_sha256")
    legacy_summary.pop("reference_file_sha256")
    write_summary(legacy_summary)
    result = gate.pca_lineage_assessment({"valid": True}, inventory)
    assert not result["valid"] and any("full rebuild required" in reason for reason in result["reasons"])

    write_summary(summary)
    assert gate.pca_lineage_assessment({"valid": True}, inventory)["valid"]
    zero_scale = copy.deepcopy(reference)
    zero_scale["scaler_scale"][2] = 0.0
    assert gate.reference_structure_reasons(zero_scale)
    short_components = copy.deepcopy(reference)
    short_components["pca_components"] = short_components["pca_components"][:4]
    assert gate.reference_structure_reasons(short_components)
finally:
    for name, value in old_globals.items():
        setattr(gate, name, value)
    for path in fixture.iterdir():
        path.unlink()
    fixture.rmdir()

wrapper_paths = (
    ROOT / "projects" / "AKS_2026" / "_NOI_BO" / "run_design_workflow.ps1",
    ROOT / "projects" / "AKS_BLIND_ROI_TEST" / "_NOI_BO" / "run_design_workflow.ps1",
    ROOT / "_UNG_DUNG" / "project_template" / "_NOI_BO" / "run_design_workflow.ps1",
)
for wrapper_path in wrapper_paths:
    wrapper = wrapper_path.read_text(encoding="utf-8")
    assert wrapper.count("ensure_design_covariates.py") == 4
    assert wrapper.count("build_clhs_pca.R") == 2
    assert wrapper.count("if (-not [bool]$coverage.pca_grid_ready)") == 1
    assert "reference_file_sha256" in wrapper and "pca_raster_sha256" in wrapper
    assert "soil_lineage_ready" in wrapper

interpolation_paths = (
    ROOT / "projects" / "AKS_2026" / "_NOI_BO" / "run_interpolation_workflow.ps1",
    ROOT / "projects" / "AKS_BLIND_ROI_TEST" / "_NOI_BO" / "run_interpolation_workflow.ps1",
    ROOT / "_UNG_DUNG" / "project_template" / "_NOI_BO" / "run_interpolation_workflow.ps1",
)
for interpolation_path in interpolation_paths:
    interpolation = interpolation_path.read_text(encoding="utf-8")
    sync_position = interpolation.index("sync_settings.ps1")
    crs_position = interpolation.index("configure_project_crs.py")
    lineage_position = interpolation.index("ensure_design_covariates.py")
    preflight_position = interpolation.index("preflight_actual.R")
    assert sync_position < crs_position < lineage_position < preflight_position
    assert "raw_provenance_assessment.valid" in interpolation
    assert "pca_grid_ready" in interpolation
    assert "soil_lineage_ready" in interpolation
    assert interpolation.index("soil_lineage_ready") < preflight_position

status_paths = (
    ROOT / "projects" / "AKS_2026" / "_NOI_BO" / "status.ps1",
    ROOT / "projects" / "AKS_BLIND_ROI_TEST" / "_NOI_BO" / "status.ps1",
    ROOT / "_UNG_DUNG" / "project_template" / "_NOI_BO" / "status.ps1",
)
for status_path in status_paths:
    status_source = status_path.read_text(encoding="utf-8")
    assert "raw provenance {1}" in status_source
    assert "lineage {1}" in status_source
    assert "raw/PCA/Soil lineage chua duoc xac minh" in status_source
    assert "soilLineageStatus" in status_source

for project in ("AKS_2026", "AKS_BLIND_ROI_TEST"):
    source = (
        ROOT / "projects" / project / "_NOI_BO" / "pipeline" / "run_download_clhs.py"
    ).read_text(encoding="utf-8")
    assert "if not grid_file.exists()" not in source
    assert source.index("grid.main()") < source.index("engine.main()")
    pca_source = (ROOT / "projects" / project / "_NOI_BO" / "pipeline" / "build_clhs_pca.R").read_text(encoding="utf-8")
    metadata_start = pca_source.index("if (metadata_only)")
    verify_call = pca_source.index("verify_metadata_refresh_inputs()", metadata_start)
    freeze_call = pca_source.index("frozen <- freeze_reference", metadata_start)
    write_call = pca_source.index("write_pca_qa(", freeze_call)
    assert metadata_start < verify_call < freeze_call < write_call

# Full-area GEE downloads must read the active project settings. A hard-coded
# shim previously made PHU Yen claim a 10 m grid while actually using 30 m and
# omitted gee_project_id, which failed as soon as the support module was loaded.
downloaders = (
    ROOT / "projects" / "AKS_2026" / "_NOI_BO" / "pipeline" / "download_sampling_satellite.py",
    ROOT / "projects" / "AKS_BLIND_ROI_TEST" / "_NOI_BO" / "pipeline" / "download_sampling_satellite.py",
    ROOT / "_UNG_DUNG" / "project_template" / "_NOI_BO" / "pipeline" / "download_sampling_satellite.py",
)
for downloader in downloaders:
    source = downloader.read_text(encoding="utf-8")
    assert 'CONFIG_FILE = PROJECT / "_NOI_BO" / "config" / "project.yml"' in source
    assert 'cfg = yaml.safe_load(stream)' in source
    assert 'GEE_PROJECT_ID = str(cfg["gee_project_id"])' in source
    assert 'TEMPLATE_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "grid_template.tif"' in source
    assert 'TEMPLATE_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "PC1.tif"' not in source
    assert 'yaml_shim' not in source
    assert '"resolution_m": 10' not in source
# Exercise initialize_grid twice to prove the second run overwrites the old
# template after the project resolution changes.
grid_spec = importlib.util.spec_from_file_location(
    "initialize_grid", PIPELINE / "initialize_grid.py"
)
grid = importlib.util.module_from_spec(grid_spec)
grid_spec.loader.exec_module(grid)
test_dir = ROOT / "_UNG_DUNG" / "runtime" / "tests" / "grid_rebuild_gate"
test_dir.mkdir(parents=True, exist_ok=True)
roi_file = test_dir / "roi.geojson"
config_file = test_dir / "project.yml"
grid_file = test_dir / "grid_template.tif"
roi_payload = {
    "type": "FeatureCollection",
    "name": "roi",
    "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:OGC:1.3:CRS84"}},
    "features": [{
        "type": "Feature",
        "properties": {"id": 1},
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[109.1, 13.0], [109.12, 13.0], [109.12, 13.02], [109.1, 13.02], [109.1, 13.0]]],
        },
    }],
}
roi_file.write_text(json.dumps(roi_payload), encoding="utf-8")
grid.ROI_FILE = roi_file
grid.CONFIG_FILE = config_file
grid.OUTPUT_FILE = grid_file
config_file.write_text("crs_epsg: 32649\nresolution_m: 30\n", encoding="utf-8")
grid.main()
with rasterio.open(grid_file) as dataset:
    first = (dataset.crs, dataset.transform, dataset.width, dataset.height)
    assert abs(dataset.transform.a) == 30
config_file.write_text("crs_epsg: 32649\nresolution_m: 100\n", encoding="utf-8")
grid.main()
with rasterio.open(grid_file) as dataset:
    second = (dataset.crs, dataset.transform, dataset.width, dataset.height)
    assert abs(dataset.transform.a) == 100
assert first != second
for path in (grid_file, config_file, roi_file):
    path.unlink(missing_ok=True)
test_dir.rmdir()

print("[OK] current-project covariate provenance and fresh-grid gates passed")
