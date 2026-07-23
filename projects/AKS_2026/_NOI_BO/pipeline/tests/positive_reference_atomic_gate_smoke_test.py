#!/usr/bin/env python3
"""Offline regression tests for the single-process AKS transfer gate."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
from pathlib import Path

import geopandas as gpd
from shapely.geometry import Point


HERE = Path(__file__).resolve().parent
SOURCE_PROJECT = HERE.parents[2]
MODULE_PATH = HERE.parent / "extract_positive_feature_knowledge_atomic.py"
BUILDER_PATH = HERE.parent / "build_positive_feature_library.py"
SCHEMA_FIXTURE = HERE / "fixtures" / "aks_positive_feature_schema_v2.json"


def load(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


MODULE = load("atomic_gate_tested", MODULE_PATH)
BUILDER = load("guarded_builder_tested", BUILDER_PATH)


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


temporary = SOURCE_PROJECT.parents[1] / ".tmp" / "positive_reference_atomic_gate_smoke"
if temporary.exists():
    shutil.rmtree(temporary)
temporary.mkdir(parents=True)
project = temporary / "AKS_2026"
package = project / "_NOI_BO" / "work" / "field_area" / "reference_package"
config_dir = project / "_NOI_BO" / "config"
pipeline = project / "_NOI_BO" / "pipeline"
package.mkdir(parents=True)
config_dir.mkdir(parents=True)
pipeline.mkdir(parents=True)
shutil.copy2(
    SOURCE_PROJECT / "_NOI_BO" / "config" / "positive_reference_knowledge_contract.json",
    config_dir / "positive_reference_knowledge_contract.json",
)
shutil.copy2(
    SCHEMA_FIXTURE,
    package / "feature_schema.json",
)
shutil.copy2(
    SOURCE_PROJECT / "_NOI_BO" / "pipeline" / "sugarcane_temporal_features.py",
    pipeline / "sugarcane_temporal_features.py",
)
reference = package / "positive_reference.geojson"
table = gpd.GeoDataFrame(
    {
        "source_feature_index": ["1", "2", "3"],
        "label": [1, 1, 1],
        "label_name": ["sugarcane"] * 3,
        "label_basis": ["verified"] * 3,
        "evaluation_eligible": [False] * 3,
        "source_project": ["AKS_2026"] * 3,
    },
    geometry=[Point(108.0, 14.0), Point(108.1, 14.1), Point(108.2, 14.2)],
    crs="EPSG:4326",
)
table.to_file(reference, driver="GeoJSON")
materialized = table.copy()
materialized["reference_id"] = ["AKS_POS_0001", "AKS_POS_0002", "AKS_POS_0003"]
coordinates = {
    row.reference_id: (float(row.geometry.x), float(row.geometry.y))
    for row in materialized[["reference_id", "geometry"]].itertuples(index=False)
}
returned = {
    "AKS_POS_0001": {
        "reference_id": "AKS_POS_0001",
        "lon": 108.0,
        "lat": 14.0,
        "label": 1,
        "evaluation_eligible": False,
        "source_project": "AKS_2026",
        "label_basis": "verified",
        "BAND_A": 1.0,
        "BAND_B": 2.0,
    }
}
materialized_table, missing = BUILDER.materialize_authorized_rows(
    materialized, returned, ["BAND_A", "BAND_B"], coordinates
)
assert missing == ["AKS_POS_0002", "AKS_POS_0003"]
assert len(materialized_table) == 3
assert int(materialized_table["feature_complete"].sum()) == 1
assert materialized_table.loc[~materialized_table["feature_complete"], ["BAND_A", "BAND_B"]].isna().all().all()

card_path = package / "model_card.json"
card = {
    "artifact_type": "positive_reference_only",
    "binary_classifier_trained": False,
    "positive_reference": {
        "n_points": 3,
        "sha256": digest(reference),
        "selection": {"selected_points": 3, "reference_max_points": 1000},
    },
}
write_json(card_path, card)
project_config = config_dir / "project.yml"
project_config.write_text("gee_project_id: rkapp-492504\n", encoding="utf-8")

approved, approved_path, receipt = MODULE.validate(project)
assert len(approved) == 3
assert approved_path == reference.resolve()
assert receipt["status"] == "PASS_ATOMIC_BEFORE_EXTERNAL_TRANSFER"
assert receipt["exact_validated_geodataframe_used_for_transfer"] is True
assert receipt["predictor_band_count"] == 75

try:
    BUILDER.require_authorized_context(project.resolve(), reference.resolve(), approved)
except RuntimeError as error:
    assert "cannot run directly" in str(error)
else:
    raise AssertionError("Direct extractor execution was not blocked")

BUILDER.AUTHORIZED_TRANSFER_CONTEXT = {
    "status": "AUTHORIZED_IN_MEMORY_BY_ATOMIC_GATE",
    "project_dir": str(project.resolve()),
    "reference_path": str(reference.resolve()),
    "reference_sha256": receipt["positive_reference_sha256"],
    "guarded_file_hashes": receipt["guarded_file_hashes"],
    "reference_count": 3,
    "maximum_reference_points": 1000,
    "expected_predictor_bands": MODULE.RULES.expected_predictor_bands(
        read_json(config_dir / "positive_reference_knowledge_contract.json")
    ),
}
assert BUILDER.require_authorized_context(project.resolve(), reference.resolve(), approved)
BUILDER.AUTHORIZED_TRANSFER_CONTEXT["guarded_file_hashes"] = {
    **receipt["guarded_file_hashes"],
    "_NOI_BO/config/project.yml": "0" * 64,
}
try:
    BUILDER.require_authorized_context(project.resolve(), reference.resolve(), approved)
except RuntimeError as error:
    assert "Guarded input changed" in str(error)
else:
    raise AssertionError("Post-validation guarded-file change was not rejected")
BUILDER.AUTHORIZED_TRANSFER_CONTEXT = None
tampered = read_json(package / "feature_schema.json")
tampered["sentinel_2"]["cloud_score_threshold"] = 0.1
write_json(package / "feature_schema.json", tampered)
try:
    MODULE.validate(project)
except ValueError as error:
    assert "feature_schema_semantic_sha256" in str(error) or "cloud_score_threshold" in str(error)
else:
    raise AssertionError("Tampered exact feature schema was not rejected")
shutil.copy2(
    SCHEMA_FIXTURE,
    package / "feature_schema.json",
)

card["positive_reference"]["selection"]["reference_max_points"] = 1001
write_json(card_path, card)
try:
    MODULE.validate(project)
except ValueError as error:
    assert "cap" in str(error).lower()
else:
    raise AssertionError("Declared cap above 1,000 was not rejected")
card["positive_reference"]["selection"]["reference_max_points"] = 1000
write_json(card_path, card)

write_json(
    project / "MOCK_CONTRACT.json",
    {"non_operational": True, "knowledge_integration_eligible": False},
)
try:
    MODULE.validate(project)
except ValueError as error:
    assert "Mock/synthetic" in str(error)
else:
    raise AssertionError("Mock project was not rejected")

shutil.rmtree(temporary)
print("[OK] Atomic AKS gate: exact 75-band contract, cap, mock rejection and direct-call block")
