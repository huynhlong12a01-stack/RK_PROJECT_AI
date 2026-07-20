#!/usr/bin/env python3
"""Validate and extract at most 1,000 AKS positives in one guarded process.

The exact GeoDataFrame that passes the consent, provenance and 75-predictor
contract is retained in memory and passed to the GEE extractor.  The core
extractor refuses to run without this in-memory authorization context.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import pandas as pd


EXPECTED_PROJECT = "AKS_2026"
EXPECTED_GEE_PROJECT = "rkapp-492504"
EXPECTED_REFERENCE_COLUMNS = [
    "source_feature_index",
    "label",
    "label_name",
    "label_basis",
    "evaluation_eligible",
    "source_project",
    "geometry",
]


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
RULES = load_module("aks_positive_reference_contract_atomic", HERE / "positive_reference_contract.py")


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_flat_value(path: Path, key: str) -> str:
    for source_line in path.read_text(encoding="utf-8-sig").splitlines():
        line = source_line.split("#", 1)[0].strip()
        if not line or ":" not in line:
            continue
        name, value = line.split(":", 1)
        if name.strip() == key:
            return value.strip().strip("\"'")
    return ""


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    os.close(handle)
    temporary_path = Path(temporary)
    try:
        temporary_path.write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def false_series(values: pd.Series) -> bool:
    normalized = values.astype(str).str.strip().str.lower()
    return bool(normalized.isin({"false", "0"}).all())


def validate(project: Path) -> tuple[gpd.GeoDataFrame, Path, dict]:
    if project.name != EXPECTED_PROJECT:
        raise ValueError(f"External reference extraction is restricted to {EXPECTED_PROJECT}")
    mock_contract = project / "MOCK_CONTRACT.json"
    if mock_contract.exists():
        mock = read_json(mock_contract)
        if mock.get("non_operational") is True or mock.get("knowledge_integration_eligible") is False:
            raise ValueError("Mock/synthetic projects are prohibited from reference extraction")

    internal = project / "_NOI_BO"
    package = internal / "work" / "field_area" / "reference_package"
    reference = package / "positive_reference.geojson"
    card_path = package / "model_card.json"
    schema_path = package / "feature_schema.json"
    contract_path = internal / "config" / "positive_reference_knowledge_contract.json"
    config_path = internal / "config" / "project.yml"
    temporal_engine = internal / "pipeline" / "sugarcane_temporal_features.py"
    for path in (reference, card_path, schema_path, contract_path, config_path, temporal_engine):
        if not path.is_file():
            raise FileNotFoundError(f"Consent input is missing: {path}")

    card = read_json(card_path)
    schema = read_json(schema_path)
    contract = read_json(contract_path)
    RULES.reject_mock_or_synthetic("source model card", card)
    if card.get("artifact_type") != "positive_reference_only":
        raise ValueError("Only positive_reference_only geometry is authorized")
    if bool(card.get("binary_classifier_trained", False)):
        raise ValueError("A fitted classifier is outside this consent")
    if contract.get("artifact_semantics") != "positive_reference_only":
        raise ValueError("Knowledge contract semantics changed")
    if contract.get("source_project") != EXPECTED_PROJECT:
        raise ValueError("Knowledge contract source project changed")
    maximum = int(contract.get("maximum_reference_points", -1))
    if maximum != 1000:
        raise ValueError("The approved consent boundary is exactly 1,000 points maximum")
    feature_gate = RULES.validate_feature_schema(contract, schema, temporal_engine)
    if int(feature_gate["predictor_band_count"]) != 75:
        raise ValueError("AKS transfer requires exactly 75 ordered predictors")

    approved = gpd.read_file(reference)
    actual = int(len(approved))
    declared = int(card.get("positive_reference", {}).get("n_points", -1))
    selection = card.get("positive_reference", {}).get("selection", {})
    selected = int(selection.get("selected_points", -1))
    declared_limit = int(selection.get("reference_max_points", -1))
    if actual <= 0 or min(declared, selected, declared_limit) < 0:
        raise ValueError("Reference count provenance is incomplete")
    if len({actual, declared, selected}) != 1:
        raise ValueError(
            f"Reference counts disagree: actual={actual}, declared={declared}, selected={selected}"
        )
    if actual > maximum or declared_limit > maximum:
        raise ValueError(f"Consent cap exceeded: {actual} rows; maximum={maximum}")
    expected_hash = str(card.get("positive_reference", {}).get("sha256", "")).lower()
    actual_hash = sha256_file(reference)
    if not expected_hash or actual_hash != expected_hash:
        raise ValueError("Reference hash does not match the approved model card")

    if list(approved.columns) != EXPECTED_REFERENCE_COLUMNS:
        raise ValueError(
            "Approved reference columns/order changed: " + ", ".join(map(str, approved.columns))
        )
    if approved.crs is None or approved.crs.to_epsg() != 4326:
        raise ValueError("Authorized reference must be EPSG:4326")
    if approved.geometry.isna().any() or approved.geometry.is_empty.any() or not approved.geom_type.eq("Point").all():
        raise ValueError("Every authorized reference geometry must be a non-empty Point")
    if not approved.geometry.to_wkb().is_unique:
        raise ValueError("Authorized reference contains duplicate point geometry")
    if not pd.to_numeric(approved["label"], errors="coerce").eq(1).all():
        raise ValueError("The package must contain positive labels only")
    if not approved["label_name"].astype(str).str.strip().eq("sugarcane").all():
        raise ValueError("The package label_name must be sugarcane")
    if approved["label_basis"].astype(str).str.strip().eq("").any():
        raise ValueError("Every reference requires a non-empty label_basis")
    if not false_series(approved["evaluation_eligible"]):
        raise ValueError("AKS reference rows must be ineligible for evaluation")
    if not approved["source_project"].astype(str).eq(EXPECTED_PROJECT).all():
        raise ValueError("Reference rows contain an unexpected source project")
    if not approved["source_feature_index"].astype(str).is_unique:
        raise ValueError("Reference source indices must be unique")

    gee_project = read_flat_value(config_path, "gee_project_id")
    if gee_project != EXPECTED_GEE_PROJECT:
        raise ValueError(
            f"GEE project is {gee_project!r}; consent applies only to {EXPECTED_GEE_PROJECT!r}"
        )
    receipt = {
        "status": "PASS_ATOMIC_BEFORE_EXTERNAL_TRANSFER",
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "artifact_type": "positive_reference_only",
        "source_project": EXPECTED_PROJECT,
        "actual_reference_points": actual,
        "maximum_reference_points": maximum,
        "positive_reference_sha256": actual_hash,
        "guarded_file_hashes": {
            "_NOI_BO/config/project.yml": sha256_file(config_path),
            "_NOI_BO/config/positive_reference_knowledge_contract.json": sha256_file(contract_path),
            "_NOI_BO/work/field_area/reference_package/model_card.json": sha256_file(card_path),
            "_NOI_BO/work/field_area/reference_package/feature_schema.json": sha256_file(schema_path),
        },
        "gee_project_id": gee_project,
        "exact_validated_geodataframe_used_for_transfer": True,
        "evaluation_eligible": False,
        "predictor_band_count": feature_gate["predictor_band_count"],
        "feature_schema_semantic_sha256": feature_gate["feature_schema_semantic_sha256"],
        "temporal_engine_normalized_sha256": feature_gate["temporal_engine_normalized_sha256"],
        "knowledge_output_must_remove_coordinates": True,
    }
    atomic_json(package / "external_transfer_consent_receipt.json", receipt)
    return approved, reference.resolve(), receipt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--preflight-only", action="store_true")
    arguments = parser.parse_args()
    project = Path(arguments.project_dir).resolve()
    approved, reference_path, receipt = validate(project)
    print(json.dumps(receipt, ensure_ascii=False, indent=2))
    if arguments.preflight_only:
        return 0

    contract = read_json(project / "_NOI_BO" / "config" / "positive_reference_knowledge_contract.json")
    safe = load_module(
        "aks_positive_extractor_atomic_runtime",
        project / "_NOI_BO" / "pipeline" / "build_positive_feature_library_safe.py",
    )
    original_read_file = safe.EXTRACTOR.gpd.read_file
    context = {
        "status": "AUTHORIZED_IN_MEMORY_BY_ATOMIC_GATE",
        "project_dir": str(project),
        "reference_path": str(reference_path),
        "reference_sha256": receipt["positive_reference_sha256"],
        "guarded_file_hashes": receipt["guarded_file_hashes"],
        "reference_count": receipt["actual_reference_points"],
        "maximum_reference_points": receipt["maximum_reference_points"],
        "gee_project_id": receipt["gee_project_id"],
        "expected_predictor_bands": RULES.expected_predictor_bands(contract),
        "runtime_overrides": RULES.runtime_overrides(contract),
    }

    def read_approved(path, *args, **kwargs):
        try:
            candidate = Path(path).resolve()
        except TypeError:
            candidate = None
        if candidate == reference_path:
            return approved.copy()
        return original_read_file(path, *args, **kwargs)

    safe.EXTRACTOR.gpd.read_file = read_approved
    safe.EXTRACTOR.AUTHORIZED_TRANSFER_CONTEXT = context
    try:
        sys.argv = [sys.argv[0], "--project-dir", str(project)]
        result = int(safe.EXTRACTOR.main())
    finally:
        safe.EXTRACTOR.AUTHORIZED_TRANSFER_CONTEXT = None
        safe.EXTRACTOR.gpd.read_file = original_read_file
    if sha256_file(reference_path) != receipt["positive_reference_sha256"]:
        raise RuntimeError("Source reference changed during extraction; knowledge ingestion is blocked")
    return result


if __name__ == "__main__":
    raise SystemExit(main())
