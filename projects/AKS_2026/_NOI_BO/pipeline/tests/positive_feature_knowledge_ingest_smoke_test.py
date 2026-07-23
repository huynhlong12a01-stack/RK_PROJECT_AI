#!/usr/bin/env python3
"""Offline tests for exact, private and atomic AKS knowledge ingestion."""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from pathlib import Path

import pandas as pd


HERE = Path(__file__).resolve()
SCRIPT = HERE.parents[1] / "ingest_positive_feature_knowledge.py"
SOURCE_PROJECT = HERE.parents[3]
REPOSITORY = HERE.parents[5]
FIXTURE_REPOSITORY = REPOSITORY / ".tmp" / "positive_knowledge_ingest_smoke_v2"
PROJECT = FIXTURE_REPOSITORY / "projects" / "AKS_2026"
PACKAGE = PROJECT / "_NOI_BO" / "work" / "field_area" / "reference_package"
CONFIG = PROJECT / "_NOI_BO" / "config"
PIPELINE = PROJECT / "_NOI_BO" / "pipeline"
OUTPUT = FIXTURE_REPOSITORY / "knowledge-private" / "sugarcane" / "AKS_2026" / "positive_reference_v1"
SCHEMA_FIXTURE = HERE.parent / "fixtures" / "aks_positive_feature_schema_v2.json"


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def load_module():
    specification = importlib.util.spec_from_file_location("knowledge_ingest_smoke", SCRIPT)
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module


def invoke(module) -> int:
    previous = sys.argv
    try:
        sys.argv = [str(SCRIPT), "--project-dir", str(PROJECT), "--knowledge-dir", str(OUTPUT)]
        return module.main()
    finally:
        sys.argv = previous


def main() -> None:
    if FIXTURE_REPOSITORY.exists():
        shutil.rmtree(FIXTURE_REPOSITORY)
    PACKAGE.mkdir(parents=True)
    CONFIG.mkdir(parents=True)
    PIPELINE.mkdir(parents=True)
    shutil.copy2(
        SOURCE_PROJECT / "_NOI_BO" / "config" / "positive_reference_knowledge_contract.json",
        CONFIG / "positive_reference_knowledge_contract.json",
    )
    shutil.copy2(
        SCHEMA_FIXTURE,
        PACKAGE / "feature_schema.json",
    )
    shutil.copy2(
        SOURCE_PROJECT / "_NOI_BO" / "pipeline" / "sugarcane_temporal_features.py",
        PIPELINE / "sugarcane_temporal_features.py",
    )
    module = load_module()
    contract = json.loads((CONFIG / "positive_reference_knowledge_contract.json").read_text(encoding="utf-8"))
    schema = json.loads((PACKAGE / "feature_schema.json").read_text(encoding="utf-8"))
    bands = module.RULES.expected_predictor_bands(contract)
    assert len(bands) == 75
    scene_counts = {
        **contract["required_feature_contract"]["temporal"],
        "period_scene_counts": [],
        "empty_periods": [],
        "band_count": 75,
        "sentinel_1_input_unit": "dB",
        "sentinel_1_additional_log_transform": False,
    }
    snapshot = module.RULES.build_extraction_snapshot(
        contract,
        schema,
        PIPELINE / "sugarcane_temporal_features.py",
        bands,
        module.RULES.runtime_overrides(contract),
        scene_counts,
    )
    write_json(PACKAGE / "extraction_contract_snapshot.json", snapshot)

    raw_values = {
        band: [float(index + 1), float(index + 2), float(index + 3)]
        for index, band in enumerate(bands)
    }
    raw = pd.DataFrame(
        {
            "reference_id": ["RAW_A", "RAW_B", "RAW_C"],
            "lon": [108.1, 108.2, 108.3],
            "lat": [13.1, 13.2, 13.3],
            "label": [1, 1, 1],
            "evaluation_eligible": [False, False, False],
            "source_project": ["AKS_2026"] * 3,
            "label_basis": ["verified"] * 3,
            **raw_values,
            "feature_complete": [True, True, True],
        }
    )
    raw_path = PACKAGE / "positive_temporal_features.csv"
    raw.to_csv(raw_path, index=False)
    domain_features = {}
    for band in bands:
        values = raw[band]
        domain_features[band] = {
            "n": 3,
            "p01": float(values.quantile(0.01)),
            "median": float(values.median()),
            "p99": float(values.quantile(0.99)),
        }
    write_json(
        PACKAGE / "positive_feature_domain.json",
        {
            "schema_version": contract["required_schema_version"],
            "status": "POSITIVE_CLASS_DOMAIN_ONLY",
            "not_binary_aoa": True,
            "feature_schema_sha256": module.sha256_file(PACKAGE / "feature_schema.json"),
            "feature_schema_semantic_sha256": module.RULES.canonical_json_sha256(schema),
            "target_year": 2026,
            "scene_counts": scene_counts,
            "features": domain_features,
        },
    )
    write_json(
        PACKAGE / "model_card.json",
        {
            "schema_version": contract["required_schema_version"],
            "artifact_type": "positive_reference_only",
            "binary_classifier_trained": False,
            "positive_reference": {"n_points": 3},
            "positive_feature_library": {
                "status": "POSITIVE_CLASS_TEMPORAL_FEATURES_EXTRACTED_EXACT_CONTRACT",
                "sha256": module.sha256_file(raw_path),
                "n_reference_points": 3,
                "n_sampled": 3,
                "n_complete": 3,
                "complete_fraction": 1.0,
                "predictor_band_count": 75,
            },
        },
    )

    assert invoke(module) == 0
    safe = pd.read_csv(OUTPUT / "positive_temporal_features.csv")
    assert "lon" not in safe.columns and "lat" not in safe.columns
    assert len(safe) == 3 and int(safe["feature_complete"].sum()) == 3
    assert set(safe["reference_id"]).isdisjoint({"RAW_A", "RAW_B", "RAW_C"})
    assert safe["reference_id"].str.startswith("AKS_KNOW_").all()
    prototypes = pd.read_csv(OUTPUT / "positive_feature_prototypes.csv")
    assert len(prototypes) == 3
    manifest = json.loads((OUTPUT / "knowledge_manifest.json").read_text(encoding="utf-8"))
    assert manifest["coordinates_included"] is False
    assert manifest["geometry_included"] is False
    assert manifest["raw_identifiers_rekeyed"] is True
    assert manifest["n_features"] == 75
    assert manifest["multivariate_support_included"] is True
    knowledge_domain = json.loads((OUTPUT / "positive_feature_domain.json").read_text(encoding="utf-8"))
    assert knowledge_domain["multivariate_support"]["status"] == "POSITIVE_CLASS_MULTIVARIATE_SUPPORT_ONLY"
    assert knowledge_domain["multivariate_support"]["n_features"] == 75
    assert set(path.name for path in OUTPUT.iterdir()) == module.EXPECTED_OUTPUT_FILES

    first_ids = safe["reference_id"].tolist()
    assert invoke(module) == 0
    second_ids = pd.read_csv(OUTPUT / "positive_temporal_features.csv")["reference_id"].tolist()
    assert first_ids != second_ids, "Known old output was not atomically replaced/re-keyed"

    policy = contract["coordinate_policy"]
    try:
        module.RULES.audit_table_privacy(pd.DataFrame({"field_centroid_lon": [108.1]}), policy, "malicious")
    except ValueError as error:
        assert "forbidden" in str(error)
    else:
        raise AssertionError("Coordinate-like substring was not rejected")
    findings = module.RULES.privacy_findings(
        {"nested": {"payload": "POINT (108 13)"}}, policy, "malicious_json"
    )
    assert findings and "WKT" in findings[0]

    unexpected = OUTPUT / "old_coordinates.csv"
    unexpected.write_text("lon,lat\n108,13\n", encoding="utf-8")
    try:
        invoke(module)
    except ValueError as error:
        assert "unexpected old entries" in str(error)
    else:
        raise AssertionError("Unexpected old output was not rejected")
    unexpected.unlink()

    card_path = PACKAGE / "model_card.json"
    card = json.loads(card_path.read_text(encoding="utf-8"))
    card["synthetic"] = True
    write_json(card_path, card)
    existing_manifest_hash = module.sha256_file(OUTPUT / "knowledge_manifest.json")
    try:
        invoke(module)
    except ValueError as error:
        assert "Mock/synthetic" in str(error)
    else:
        raise AssertionError("Synthetic source provenance was not rejected")
    assert module.sha256_file(OUTPUT / "knowledge_manifest.json") == existing_manifest_hash
    shutil.rmtree(FIXTURE_REPOSITORY)
    print("[OK] exact 75-band, mock-safe, recursively private, atomic knowledge ingestion")


if __name__ == "__main__":
    main()
