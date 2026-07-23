"""Fast Soil Type lineage, semantics, and workflow gate tests; no GIS run."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path


PIPELINE = Path(__file__).resolve().parents[1]
ROOT = Path(__file__).resolve().parents[5]
spec = importlib.util.spec_from_file_location(
    "ensure_design_covariates_soil_test", PIPELINE / "ensure_design_covariates.py"
)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

fixture = ROOT / "_UNG_DUNG" / "runtime" / "tests" / "soil_lineage_gate"
fixture.mkdir(parents=True, exist_ok=True)
old = {
    "SOIL_FILE": gate.SOIL_FILE,
    "SOIL_SETTINGS_FILE": gate.SOIL_SETTINGS_FILE,
    "SOIL_QA_FILE": gate.SOIL_QA_FILE,
    "SOIL_RASTER_FILE": gate.SOIL_RASTER_FILE,
}
try:
    gate.SOIL_FILE = fixture / "soil_type.geojson"
    gate.SOIL_SETTINGS_FILE = fixture / "sampling.yml"
    gate.SOIL_QA_FILE = fixture / "soil_group_summary.json"
    gate.SOIL_RASTER_FILE = fixture / "Soil_Group_Code.tif"
    gate.SOIL_FILE.write_bytes(b"soil-source-v1")
    gate.SOIL_SETTINGS_FILE.write_text("soil_group_field: Ma1\n", encoding="utf-8")
    gate.SOIL_RASTER_FILE.write_bytes(b"nominal-raster-v1")
    code_labels = {"1": "Xa", "2": "Fa", "3": "Unmapped"}
    summary = {
        "schema_version": "3.0.0",
        "soil_input_present": True,
        "soil_source_sha256": gate.sha256_file(gate.SOIL_FILE),
        "source_field": "Ma1",
        "encoding": gate.SOIL_ENCODING,
        "code_labels": code_labels,
        "code_map_sha256": gate.canonical_sha256(code_labels),
        "soil_group_raster_sha256": gate.sha256_file(gate.SOIL_RASTER_FILE),
        "whole_domain_overlap_qa": {"passed": True, "overlap_pixel_count": 0},
    }

    def write(value):
        gate.SOIL_QA_FILE.write_text(json.dumps(value), encoding="utf-8")

    write(summary)
    result = gate.soil_lineage_assessment()
    assert result["valid"], result["reasons"]

    gate.SOIL_FILE.write_bytes(b"soil-source-v2")
    result = gate.soil_lineage_assessment()
    assert not result["valid"] and any("source file changed" in x for x in result["reasons"])
    gate.SOIL_FILE.write_bytes(b"soil-source-v1")

    gate.SOIL_SETTINGS_FILE.write_text("soil_group_field: SoilCode\n", encoding="utf-8")
    result = gate.soil_lineage_assessment()
    assert not result["valid"] and any("source field changed" in x for x in result["reasons"])
    gate.SOIL_SETTINGS_FILE.write_text("soil_group_field: Ma1\n", encoding="utf-8")

    gate.SOIL_RASTER_FILE.write_bytes(b"tampered-raster")
    result = gate.soil_lineage_assessment()
    assert not result["valid"] and any("raster changed" in x for x in result["reasons"])
    gate.SOIL_RASTER_FILE.write_bytes(b"nominal-raster-v1")

    changed = copy.deepcopy(summary)
    changed["code_labels"]["2"] = "Other"
    changed["code_map_sha256"] = gate.canonical_sha256(changed["code_labels"])
    write(changed)
    result = gate.soil_lineage_assessment()
    assert not result["valid"] and any("model-only Other" in x for x in result["reasons"])

    changed = copy.deepcopy(summary)
    changed["whole_domain_overlap_qa"]["passed"] = False
    write(changed)
    result = gate.soil_lineage_assessment()
    assert not result["valid"] and any("overlap QA" in x for x in result["reasons"])
finally:
    for name, value in old.items():
        setattr(gate, name, value)
    for path in fixture.iterdir():
        path.unlink()
    fixture.rmdir()

for project in ("AKS_2026", "AKS_BLIND_ROI_TEST"):
    project_pipeline = ROOT / "projects" / project / "_NOI_BO" / "pipeline"
    design_source = (project_pipeline / "prepare_clhs_soil.py").read_text(encoding="utf-8")
    interpolation_source = (project_pipeline / "02b_prepare_soil_predictors_v2.py").read_text(encoding="utf-8")
    assert "soil_source_sha256" in design_source
    assert "code_map_sha256" in design_source
    assert "soil_group_raster_sha256" in design_source
    assert "MergeAlg.add" in design_source
    assert '"Unmapped"' in design_source and 'Unmapped and Other are reserved' in design_source
    assert "verify_workflow1_lineage" in interpolation_source
    assert "output_file_sha256" in interpolation_source
    assert "unsupported_prediction_groups_assigned_reference_effect" in interpolation_source
    assert "never includes Unmapped" in interpolation_source
    assert "MergeAlg.add" in interpolation_source

for wrapper in (
    ROOT / "projects" / "AKS_2026" / "_NOI_BO" / "run_interpolation_workflow.ps1",
    ROOT / "projects" / "AKS_BLIND_ROI_TEST" / "_NOI_BO" / "run_interpolation_workflow.ps1",
    ROOT / "_UNG_DUNG" / "project_template" / "_NOI_BO" / "run_interpolation_workflow.ps1",
):
    source = wrapper.read_text(encoding="utf-8")
    assert "soil_lineage_ready" in source
    assert source.index("soil_lineage_ready") < source.index("preflight_actual.R")

print("[OK] Soil Type byte/field/encoding/code-map/output lineage gates passed")